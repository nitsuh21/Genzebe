import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:genzeb/core/logging/app_logger.dart';
import 'package:genzeb/features/sms_ingestion/application/account_mapping_service.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/category_rule_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/sms_message_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/transactions/domain/models/money.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:genzeb/features/transactions/domain/repositories/ledger_repository.dart';

class SmsIngestionService {
  SmsIngestionService({
    required SmsParserEngine parser,
    required LedgerRepository ledgerRepository,
    required SmsMessageRepository smsMessageRepository,
    required AccountMappingService accountMappingService,
    required CategoryRuleRepository categoryRuleRepository,
  })  : _parser = parser,
        _ledgerRepository = ledgerRepository,
        _smsMessageRepository = smsMessageRepository,
        _accountMappingService = accountMappingService,
        _categoryRules = categoryRuleRepository;

  final SmsParserEngine _parser;
  final LedgerRepository _ledgerRepository;
  final SmsMessageRepository _smsMessageRepository;
  final AccountMappingService _accountMappingService;
  final CategoryRuleRepository _categoryRules;

  Future<void> ingest({
    required SmsMessage sms,
    String? accountIdOverride,
  }) async {
    final hash = _hashSms(sms);

    // Never re-process a message that already has a decision (parsed,
    // rejected, pending review, ...). Re-ingesting would clobber review
    // outcomes, e.g. resurrect a rejected SMS after an app restart.
    final existingById = await _smsMessageRepository.getById(sms.id);
    if (existingById != null &&
        existingById.status != SmsIngestionStatus.pending) {
      return;
    }

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

    final isExpense = parsed.detectedAmountMinor < 0;

    // A user-taught rule for this merchant beats the keyword heuristics and
    // is trusted enough to skip the review queue.
    var categoryId = parsed.categoryHint;
    var confidence = parsed.confidence;
    final merchant = extractMerchant(sms.body, isExpense: isExpense);
    if (merchant != null) {
      final ruleCategory =
          await _categoryRules.categoryForMerchant(normalizeMerchant(merchant));
      if (ruleCategory != null) {
        categoryId = ruleCategory;
        confidence = confidence < 0.95 ? 0.95 : confidence;
      }
    }

    final type =
        isExpense ? TransactionType.expense : TransactionType.income;
    final record = TransactionRecord(
      id: 'sms-${sms.id}',
      accountId: accountId,
      type: type,
      amount: Money(minorUnits: parsed.detectedAmountMinor.abs()),
      occurredAt: sms.receivedAt,
      categoryId: categoryId,
      source: TransactionSource.sms,
      smsSender: sms.sender,
      smsSnippet: sms.body,
      parserConfidence: confidence,
      // Any successful parse scores >= 0.82 (a currency token is required to
      // parse and alone yields 0.82), so a 0.8 threshold made the review
      // queue unreachable. 0.85 routes unknown-sender/terse matches (0.82) to
      // human review while branded bank formats (>= 0.90) auto-accept.
      reviewStatus: confidence < 0.85
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

  Future<void> approveReviewItem(
    SmsReviewItem item, {
    String? categoryOverride,
  }) async {
    final transactionId = 'sms-${item.smsMessage.id}';
    final existing = await _ledgerRepository.getTransactionById(transactionId);
    if (existing == null) return;
    final updated = existing.copyWith(
      categoryId: categoryOverride,
      reviewStatus: TransactionReviewStatus.autoAccepted,
    );
    if (categoryOverride != null && categoryOverride != existing.categoryId) {
      await learnRuleFromSms(
        body: item.smsMessage.body,
        isExpense: item.parsed.detectedAmountMinor < 0,
        categoryId: categoryOverride,
      );
    }
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
    // Ingestion optimistically created a transaction for this SMS; a reject
    // must remove it (and any ledger entry) or it lingers in reports forever.
    await _ledgerRepository.deleteTransaction('sms-${item.smsMessage.id}');
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

  /// Persists an "always categorize `merchant` as `category`" rule extracted
  /// from the SMS body. Returns the merchant the rule was learned for, or
  /// null when the message has no recognizable counterparty.
  Future<String?> learnRuleFromSms({
    required String body,
    required bool isExpense,
    required String categoryId,
  }) async {
    final merchant = extractMerchant(body, isExpense: isExpense);
    if (merchant == null) return null;
    await _categoryRules.saveRule(normalizeMerchant(merchant), categoryId);
    AppLogger.info(
      'sms.rules',
      'Learned rule: "$merchant" -> $categoryId',
    );
    return merchant;
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
