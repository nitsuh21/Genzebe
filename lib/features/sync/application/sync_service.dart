import 'dart:convert';
import 'dart:io';

import 'package:genzeb/core/logging/app_logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:genzeb/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzeb/features/sms_ingestion/application/account_mapping_service.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/device_sms_source.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/sms_message_repository.dart';
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
    required this.deviceMatchedMappings,
    required this.importedCount,
    required this.mappingRuleCount,
    required this.smsPermissionState,
  });

  final int processed;
  final int newlyParsed;
  final int pendingReview;
  final int duplicates;
  final int failed;
  final int deviceFetched;
  final int deviceMatchedMappings;
  final int importedCount;
  final int mappingRuleCount;
  final SmsPermissionState smsPermissionState;
}

class SyncService {
  SyncService({
    required SmsMessageRepository smsMessageRepository,
    required SmsIngestionService smsIngestionService,
    required DeviceSmsSource deviceSmsSource,
    required AccountMappingService accountMappingService,
    LedgerRepository? ledgerRepository,
  })  : _smsMessageRepository = smsMessageRepository,
        _smsIngestionService = smsIngestionService,
        _deviceSmsSource = deviceSmsSource,
        _accountMappingService = accountMappingService,
        _ledgerRepository = ledgerRepository;

  final SmsMessageRepository _smsMessageRepository;
  final SmsIngestionService _smsIngestionService;
  final DeviceSmsSource _deviceSmsSource;
  final AccountMappingService _accountMappingService;
  final LedgerRepository? _ledgerRepository;

  Future<ForceSyncResult> forceSyncFromSms({
    String? importedRawPayload,
    bool syncAllMappings = true,
    Set<String>? selectedMappingSenderPatterns,
    bool rebuild = false,
  }) async {
    if (rebuild) await _clearSmsDerivedData();
    final since = DateTime.now().subtract(const Duration(days: 365 * 2));
    final mappings = await _accountMappingService.getMappings();
    final normalizedSelection = selectedMappingSenderPatterns
            ?.map((pattern) => pattern.toLowerCase())
            .toSet() ??
        const <String>{};
    final activeMappings = mappings.where((mapping) {
      if (syncAllMappings) return true;
      return normalizedSelection.contains(mapping.senderPattern.toLowerCase());
    }).toList(growable: false);
    final permissionState = await _deviceSmsSource.ensurePermission();
    final fetchedDeviceMessages = permissionState == SmsPermissionState.granted
        ? await _deviceSmsSource.fetchRecentMessages(
            since: since,
          )
        : const <SmsMessage>[];
    final deviceMessages = fetchedDeviceMessages.where((message) {
      if (mappings.isEmpty) return true;
      if (activeMappings.isEmpty) return false;
      final sender = message.sender;
      return activeMappings.any(
        (rule) => _senderMatchesPattern(sender, rule.senderPattern),
      );
    }).toList(growable: false);
    final importedMessages = _parseImportedPayload(importedRawPayload);
    final allMessages = <SmsMessage>[
      ...deviceMessages,
      ...importedMessages,
    ];
    AppLogger.info(
      'sync.force',
      'forceSyncFromSms: fetchedDevice=${fetchedDeviceMessages.length}, '
          'mappedDevice=${deviceMessages.length}, imported=${importedMessages.length}, '
          'mappingRules=${mappings.length}, activeRules=${activeMappings.length}, '
          'syncAllMappings=$syncAllMappings, permission=$permissionState, since=$since',
    );
    var duplicates = 0;
    var failed = 0;
    for (final message in allMessages) {
      await _smsIngestionService.ingest(sms: message);
      final stored = await _smsMessageRepository.getById(message.id);
      if (stored == null) continue;
      if (stored.status == SmsIngestionStatus.duplicate) duplicates += 1;
      if (stored.status == SmsIngestionStatus.failed) failed += 1;
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
      deviceMatchedMappings: deviceMessages.length,
      importedCount: importedMessages.length,
      mappingRuleCount: activeMappings.length,
      smsPermissionState: permissionState,
    );
  }

  /// One-time export of every stored SMS with its parse result to
  /// learning_base.json in the app documents directory — a corpus for
  /// studying how real Ethiopian receipts should be categorized (fees,
  /// debits, credits, transfers). Runs once, entirely on-device.
  Future<void> _maybeExportLearningBase() async {
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

  bool _senderMatchesPattern(String sender, String pattern) {
    final lowerSender = sender.toLowerCase();
    final lowerPattern = pattern.toLowerCase();
    if (lowerSender.contains(lowerPattern)) return true;

    final normalizedSender = _normalizeSenderToken(lowerSender);
    final normalizedPattern = _normalizeSenderToken(lowerPattern);
    if (normalizedPattern.isEmpty) return false;
    return normalizedSender.contains(normalizedPattern);
  }

  String _normalizeSenderToken(String value) {
    return value.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
