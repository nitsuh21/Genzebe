import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:genzeb/core/logging/app_logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:genzeb/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/device_sms_source.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/sms_message_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:genzeb/features/transactions/domain/repositories/ledger_repository.dart';

class ForceSyncResult {
  const ForceSyncResult({
    required this.processed,
    required this.newlyParsed,
    required this.pendingReview,
    required this.duplicates,
    required this.failed,
    required this.deviceFetched,
    required this.deviceFinancial,
    required this.importedCount,
    required this.smsPermissionState,
    required this.newTransactions,
    required this.institutionsFound,
    required this.wasIncremental,
  });

  final int processed;
  final int newlyParsed;
  final int pendingReview;
  final int duplicates;
  final int failed;

  /// Every inbox message read in the window.
  final int deviceFetched;

  /// The subset sent by a recognised bank or wallet — the only ones ingested.
  final int deviceFinancial;
  final int importedCount;
  final SmsPermissionState smsPermissionState;

  /// Transactions this run created (booked or waiting for review).
  final List<TransactionRecord> newTransactions;

  /// Institutions seen in the inbox window.
  final Set<EthiopianInstitution> institutionsFound;

  /// True for a resume/incoming-SMS refresh that followed an earlier sync.
  final bool wasIncremental;
}

/// Reads the inbox and books every message from a recognised Ethiopian bank
/// or wallet. There is no setup step: whichever institutions appear in the
/// inbox are synced, each into its own account. Messages from anyone else
/// (people, OTP services, promos) are skipped before they are stored.
class SyncService {
  SyncService({
    required SmsMessageRepository smsMessageRepository,
    required SmsIngestionService smsIngestionService,
    required DeviceSmsSource deviceSmsSource,
    LedgerRepository? ledgerRepository,
  })  : _smsMessageRepository = smsMessageRepository,
        _smsIngestionService = smsIngestionService,
        _deviceSmsSource = deviceSmsSource,
        _ledgerRepository = ledgerRepository;

  final SmsMessageRepository _smsMessageRepository;
  final SmsIngestionService _smsIngestionService;
  final DeviceSmsSource _deviceSmsSource;
  final LedgerRepository? _ledgerRepository;

  static const _lastSyncPref = 'sms_last_sync_at';
  static const _cleanupPref = 'sms_non_financial_cleanup_v1';
  static const _parserVersionPref = 'sms_parser_version';

  /// How far back the first sync reads.
  static const historyWindow = Duration(days: 365 * 2);

  /// Overlap on incremental syncs, so a message the SMS provider wrote late
  /// is still picked up. Already-ingested ids are skipped cheaply.
  static const _incrementalOverlap = Duration(days: 2);

  Future<ForceSyncResult> forceSyncFromSms({
    String? importedRawPayload,
    bool rebuild = false,
    bool incremental = false,
    bool requestPermission = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncMillis = prefs.getInt(_lastSyncPref);
    // History parsed by an older parser is rewritten once, in full.
    final parserUpgraded = lastSyncMillis != null &&
        (prefs.getInt(_parserVersionPref) ?? 1) < kParserVersion;
    if (parserUpgraded) {
      rebuild = true;
      AppLogger.info('sync.force', 'Parser upgraded: rebuilding history');
    }
    final permissionState = requestPermission
        ? await _deviceSmsSource.ensurePermission()
        : await _deviceSmsSource.currentPermission();
    // Never clear history we can't re-read: without SMS access a rebuild
    // would only delete the ledger.
    if (rebuild && permissionState != SmsPermissionState.granted) {
      rebuild = false;
    }
    if (rebuild) await _clearSmsDerivedData();
    await _purgeNonFinancialMessagesOnce();

    final isIncremental = incremental && !rebuild && lastSyncMillis != null;
    final now = DateTime.now();
    final since = isIncremental
        ? DateTime.fromMillisecondsSinceEpoch(lastSyncMillis)
            .subtract(_incrementalOverlap)
        : now.subtract(historyWindow);

    final fetchedDeviceMessages = permissionState == SmsPermissionState.granted
        ? await _deviceSmsSource.fetchRecentMessages(since: since)
        : const <SmsMessage>[];
    final deviceMessages = fetchedDeviceMessages
        .where((message) => isFinancialSender(message.sender))
        .toList(growable: false);
    // Pasted messages are the user's explicit choice; ingest them as-is.
    final importedMessages = _parseImportedPayload(importedRawPayload);
    final allMessages = <SmsMessage>[
      ...deviceMessages,
      ...importedMessages,
    ];
    AppLogger.info(
      'sync.force',
      'forceSyncFromSms: fetchedDevice=${fetchedDeviceMessages.length}, '
          'financial=${deviceMessages.length}, imported=${importedMessages.length}, '
          'incremental=$isIncremental, permission=$permissionState, since=$since',
    );

    var duplicates = 0;
    var failed = 0;
    final created = <TransactionRecord>[];
    final institutions = <EthiopianInstitution>{};
    for (final message in allMessages) {
      final institution = institutionForSender(message.sender);
      if (institution != EthiopianInstitution.unknown) {
        institutions.add(institution);
      }
      final record = await _smsIngestionService.ingest(sms: message);
      if (record != null) {
        created.add(record);
        continue;
      }
      final stored = await _smsMessageRepository.getById(message.id);
      if (stored == null) continue;
      if (stored.status == SmsIngestionStatus.duplicate) duplicates += 1;
      if (stored.status == SmsIngestionStatus.failed) failed += 1;
    }

    if (permissionState == SmsPermissionState.granted) {
      await prefs.setInt(_lastSyncPref, now.millisecondsSinceEpoch);
      await prefs.setInt(_parserVersionPref, kParserVersion);
    }
    await _maybeExportLearningBase();

    final allStored = await _smsMessageRepository.getAll();
    final newlyParsed = allStored
        .where((message) => message.status == SmsIngestionStatus.parsed)
        .length;
    final pendingReview = allStored
        .where((message) => message.status == SmsIngestionStatus.pendingReview)
        .length;
    return ForceSyncResult(
      processed: allMessages.length,
      newlyParsed: newlyParsed,
      pendingReview: pendingReview,
      duplicates: duplicates,
      failed: failed,
      deviceFetched: fetchedDeviceMessages.length,
      deviceFinancial: deviceMessages.length,
      importedCount: importedMessages.length,
      smsPermissionState: permissionState,
      newTransactions: List.unmodifiable(created),
      institutionsFound: Set.unmodifiable(institutions),
      wasIncremental: isIncremental,
    );
  }

  /// Earlier versions ingested the WHOLE inbox when no sender mapping
  /// existed, filling the review queue (and the database) with personal
  /// messages. Drop everything from unrecognised senders that the user
  /// hasn't explicitly kept; rejected rows stay so rejections are honoured.
  Future<void> _purgeNonFinancialMessagesOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_cleanupPref) ?? false) return;
    final stored = await _smsMessageRepository.getAll();
    var removed = 0;
    for (final message in stored) {
      if (isFinancialSender(message.sms.sender)) continue;
      if (message.status == SmsIngestionStatus.parsed ||
          message.status == SmsIngestionStatus.rejected) {
        continue;
      }
      // Pasted messages ('imported-…') were the user's explicit choice.
      if (message.sms.id.startsWith('imported-')) continue;
      final txId = message.parsedTransactionId;
      if (txId != null) await _ledgerRepository?.deleteTransaction(txId);
      await _smsMessageRepository.delete(message.sms.id);
      removed += 1;
    }
    await prefs.setBool(_cleanupPref, true);
    AppLogger.info('sync.cleanup', 'Removed $removed non-financial messages');
  }

  /// Debug-only export of every stored SMS with its parse result to
  /// learning_base.json in the app documents directory — the corpus used to
  /// grow the parser fixtures. Never runs in a release build.
  Future<void> _maybeExportLearningBase() async {
    if (kReleaseMode) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('learning_base_exported_v1') ?? false) return;

      final stored = await _smsMessageRepository.getAll();
      if (stored.isEmpty) return;
      final ledger = _ledgerRepository;

      final rows = <Map<String, dynamic>>[];
      for (final message in stored) {
        Map<String, dynamic>? parsed;
        if (ledger != null) {
          final tx = await ledger.getTransactionById('sms-${message.sms.id}');
          if (tx != null) {
            parsed = {
              'amountMinor': tx.amount.minorUnits,
              'type': tx.type.name,
              'category': tx.categoryId,
              'accountId': tx.accountId,
              'confidence': tx.parserConfidence,
              'statementBalanceMinor': tx.statementBalanceMinor,
              'reviewStatus': tx.reviewStatus.name,
            };
          }
        }
        rows.add({
          'sender': message.sms.sender,
          'body': message.sms.body,
          'receivedAt': message.sms.receivedAt.toIso8601String(),
          'status': message.status.name,
          'parsed': parsed,
        });
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/learning_base.json');
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'exportedAt': DateTime.now().toIso8601String(),
          'count': rows.length,
          'messages': rows,
        }),
      );
      await prefs.setBool('learning_base_exported_v1', true);
      AppLogger.info(
        'sync.learning',
        'Learning base exported: ${rows.length} messages -> ${file.path}',
      );
    } catch (error) {
      // Never let the export interfere with a sync.
      AppLogger.info('sync.learning', 'Learning base export skipped: $error');
    }
  }

  /// Rebuild support: drops every SMS-derived transaction and stored message
  /// so the following ingest re-parses the whole inbox with the CURRENT
  /// parser and learned rules. Manual transactions are untouched; rejected
  /// messages are kept so user rejections stay honored across rebuilds.
  Future<void> _clearSmsDerivedData() async {
    final ledger = _ledgerRepository;
    if (ledger != null) {
      final transactions = await ledger.getTransactions();
      for (final tx in transactions) {
        if (tx.source == TransactionSource.sms) {
          await ledger.deleteTransaction(tx.id);
        }
      }
    }
    final stored = await _smsMessageRepository.getAll();
    for (final message in stored) {
      if (message.status == SmsIngestionStatus.rejected) continue;
      await _smsMessageRepository.delete(message.sms.id);
    }
    AppLogger.info('sync.rebuild', 'Cleared SMS-derived data for rebuild');
  }

  List<SmsMessage> _parseImportedPayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) return const [];
    final lines = payload
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final now = DateTime.now();
    return lines.asMap().entries.map((entry) {
      final index = entry.key;
      final line = entry.value;
      final parts = line.split('|');
      final sender = parts.length > 1 ? parts.first.trim() : 'IMPORTED';
      final body = parts.length > 1 ? parts.sublist(1).join('|').trim() : line;
      return SmsMessage(
        id: 'imported-${now.microsecondsSinceEpoch}-$index',
        sender: sender,
        body: body,
        receivedAt: now.subtract(Duration(minutes: index)),
      );
    }).toList(growable: false);
  }
}
