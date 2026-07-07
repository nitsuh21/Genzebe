import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:genzebet/core/logging/app_logger.dart';
import 'package:genzebet/features/sms_ingestion/application/account_mapping_service.dart';
import 'package:genzebet/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzebet/features/sms_ingestion/domain/repositories/sms_message_repository.dart';
import 'package:genzebet/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzebet/features/transactions/domain/models/money.dart';
import 'package:genzebet/features/transactions/domain/models/transaction_models.dart';
import 'package:genzebet/features/transactions/domain/repositories/ledger_repository.dart';

class SmsIngestionService {
  SmsIngestionService({
    required SmsParserEngine parser,
    required LedgerRepository ledgerRepository,
    required SmsMessageRepository smsMessageRepository,
    required AccountMappingService accountMappingService,
  })  : _parser = parser,
        _ledgerRepository = ledgerRepository,
        _smsMessageRepository = smsMessageRepository,
        _accountMappingService = accountMappingService;

  final SmsParserEngine _parser;
  final LedgerRepository _ledgerRepository;
  final SmsMessageRepository _smsMessageRepository;
  final AccountMappingService _accountMappingService;

  Future<void> ingest({
    required SmsMessage sms,
    String? accountIdOverride,
  }) async {
    final hash = _hashSms(sms);
    final existingByHash = await _smsMessageRepository.getByHash(hash);
    if (existingByHash != null && existingByHash.sms.id != sms.id) {
      await _smsMessageRepository.save(
        StoredSmsMessage(
          sms: sms,
          messageHash: hash,
          status: SmsIngestionStatus.duplicate,
          failureReason: 'Duplicate SMS payload',
          ingestedAt: DateTime.now(),
        ),
      );
      AppLogger.info(
        'sms.ingest',
        'ingest: duplicate sender=${sms.sender} id=${sms.id}',
      );
      return;
    }

    final parsed = _parser.parse(sms);
    if (parsed == null) {
      await _smsMessageRepository.save(
        StoredSmsMessage(
          sms: sms,
          messageHash: hash,
          status: SmsIngestionStatus.failed,
          failureReason: 'No parser template matched message',
          ingestedAt: DateTime.now(),
        ),
      );
      AppLogger.info(
        'sms.ingest',
        'ingest: parse_failed sender=${sms.sender} id=${sms.id}',
      );
      return;
    }

    final accountId = accountIdOverride ??
        await _accountMappingService.resolveAccountId(
          sms: sms,
          parsed: parsed,
        );

    final type = parsed.detectedAmountMinor < 0
        ? TransactionType.expense
        : TransactionType.income;
    final record = TransactionRecord(
      id: 'sms-${sms.id}',
      accountId: accountId,
      type: type,
      amount: Money(minorUnits: parsed.detectedAmountMinor.abs()),
      occurredAt: sms.receivedAt,
      categoryId: parsed.categoryHint,
      source: TransactionSource.sms,
      smsSender: sms.sender,
      smsSnippet: sms.body,
      parserConfidence: parsed.confidence,
      reviewStatus: parsed.confidence < 0.8
          ? TransactionReviewStatus.pendingReview
          : TransactionReviewStatus.autoAccepted,
      statementBalanceMinor: parsed.balanceMinor,
    );

    await _ledgerRepository.saveTransaction(record);
    AppLogger.info(
      'sms.ingest',
      'ingest: parsed sender=${sms.sender} id=${sms.id} amount=${parsed.detectedAmountMinor} '
          'category=${parsed.categoryHint} confidence=${parsed.confidence.toStringAsFixed(2)} '
          'account=$accountId',
    );

    if (record.reviewStatus == TransactionReviewStatus.pendingReview) {
      await _smsMessageRepository.save(
        StoredSmsMessage(
          sms: sms,
          messageHash: hash,
          status: SmsIngestionStatus.pendingReview,
          parsedTransactionId: record.id,
          ingestedAt: DateTime.now(),
        ),
      );
      return;
    }

    await _appendLedgerIfMissing(record);
    await _smsMessageRepository.save(
      StoredSmsMessage(
        sms: sms,
        messageHash: hash,
        status: SmsIngestionStatus.parsed,
        parsedTransactionId: record.id,
        ingestedAt: DateTime.now(),
      ),
    );
  }

  Future<List<SmsReviewItem>> getReviewQueue() async {
    final messages = await _smsMessageRepository
        .getByStatus(SmsIngestionStatus.pendingReview);
    return messages
        .map(
          (stored) => SmsReviewItem(
            id: 'review-${stored.sms.id}',
            smsMessage: stored.sms,
            parsed: _parser.parse(stored.sms) ??
                ParsedSmsTransaction(
                  detectedAmountMinor: 0,
                  confidence: 0,
                  categoryHint: 'expense',
                  description: stored.sms.body,
                  institution: EthiopianInstitution.unknown,
                ),
            status: 'pending',
          ),
        )
        .toList(growable: false);
  }

  Future<void> approveReviewItem(SmsReviewItem item) async {
    final transactionId = 'sms-${item.smsMessage.id}';
    final existing = await _ledgerRepository.getTransactionById(transactionId);
    if (existing == null) return;
    final updated = existing.copyWith(
      reviewStatus: TransactionReviewStatus.autoAccepted,
    );
    await _ledgerRepository.saveTransaction(updated);
    await _appendLedgerIfMissing(updated);
    final hash = _hashSms(item.smsMessage);
    await _smsMessageRepository.save(
      StoredSmsMessage(
        sms: item.smsMessage,
        messageHash: hash,
        status: SmsIngestionStatus.parsed,
        parsedTransactionId: transactionId,
        ingestedAt: DateTime.now(),
      ),
    );
  }

  Future<void> rejectReviewItem(SmsReviewItem item, {String? reason}) async {
    final hash = _hashSms(item.smsMessage);
    await _smsMessageRepository.save(
      StoredSmsMessage(
        sms: item.smsMessage,
        messageHash: hash,
        status: SmsIngestionStatus.rejected,
        parsedTransactionId: 'sms-${item.smsMessage.id}',
        failureReason: reason ?? 'Rejected by reviewer',
        ingestedAt: DateTime.now(),
      ),
    );
  }

  Future<void> reingestStoredMessages() async {
    final messages = await _smsMessageRepository.getAll();
    for (final stored in messages) {
      await ingest(sms: stored.sms);
    }
  }

  Future<int> pendingReviewCount() async {
    final queue = await _smsMessageRepository
        .getByStatus(SmsIngestionStatus.pendingReview);
    return queue.length;
  }

  Future<void> _appendLedgerIfMissing(TransactionRecord record) async {
    final hasEntry =
        await _ledgerRepository.hasLedgerEntryForTransaction(record.id);
    if (hasEntry) return;
    await _ledgerRepository.appendLedgerEntry(
      LedgerEntry(
        id: 'ledger-${record.id}',
        transactionId: record.id,
        accountId: record.accountId,
        delta: Money(
          minorUnits: record.type == TransactionType.expense
              ? -record.amount.minorUnits
              : record.amount.minorUnits,
        ),
        createdAt: DateTime.now(),
        source: TransactionSource.sms,
      ),
    );
  }

  String _hashSms(SmsMessage sms) {
    final payload =
        '${sms.sender}|${sms.body}|${sms.receivedAt.toIso8601String()}';
    return sha1.convert(utf8.encode(payload)).toString();
  }
}
