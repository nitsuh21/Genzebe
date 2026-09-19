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

    final resolved = await _applyUserKnowledge(sms, parsed);
    final isExpense = resolved.detectedAmountMinor < 0;
    final type = isExpense ? TransactionType.expense : TransactionType.income;
    final record = TransactionRecord(
      id: 'sms-${sms.id}',
      accountId: accountId,
      type: type,
      amount: Money(minorUnits: resolved.detectedAmountMinor.abs()),
      occurredAt: sms.receivedAt,
      categoryId: resolved.categoryHint,
      source: TransactionSource.sms,
      smsSender: sms.sender,
      smsSnippet: sms.body,
      parserConfidence: resolved.confidence,
      reviewStatus: resolved.confidence < kAutoAcceptConfidence
          ? TransactionReviewStatus.pendingReview
          : TransactionReviewStatus.autoAccepted,
      statementBalanceMinor: resolved.balanceMinor,
    );

    await _ledgerRepository.saveTransaction(record);
    AppLogger.info(
      'sms.ingest',
      'ingest: parsed sender=${sms.sender} id=${sms.id} amount=${resolved.detectedAmountMinor} '
          'category=${resolved.categoryHint} confidence=${resolved.confidence.toStringAsFixed(2)} '
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

  /// Layers what the user has taught the app on top of the raw parse.
  ///
  /// The user is the highest authority: a merchant rule replaces the keyword
  /// category and is trusted enough to skip review, and a sender the user
  /// has mapped to an account counts as a recognised institution even when
  /// no built-in template knows it.
  Future<ParsedSmsTransaction> _applyUserKnowledge(
    SmsMessage sms,
    ParsedSmsTransaction parsed,
  ) async {
    final isExpense = parsed.detectedAmountMinor < 0;
    var evidence = parsed.evidence;
    var categoryId = parsed.categoryHint;
    var confidence = parsed.confidence;

    if (evidence != null && !evidence.institutionKnown) {
      final mapping = await _accountMappingService.mappingForSender(sms.sender);
      if (mapping != null &&
          mapping.institution != EthiopianInstitution.unknown) {
        evidence = evidence.copyWith(institutionKnown: true);
        confidence = scoreConfidence(evidence);
      }
    }

    final merchant = extractMerchant(sms.body, isExpense: isExpense);
    if (merchant != null) {
      final ruleCategory =
          await _categoryRules.categoryForMerchant(normalizeMerchant(merchant));
      if (ruleCategory != null) {
        categoryId = ruleCategory;
        evidence = evidence?.copyWith(specificCategory: true);
        confidence = confidence < 0.95 ? 0.95 : confidence;
      }
    }

    return parsed.copyWith(
      categoryHint: categoryId,
      confidence: confidence,
      evidence: evidence,
    );
  }

  Future<List<SmsReviewItem>> getReviewQueue() async {
    final messages = await _smsMessageRepository
        .getByStatus(SmsIngestionStatus.pendingReview);
    final items = <SmsReviewItem>[];
    for (final stored in messages) {
      final parsed = _parser.parse(stored.sms);
      items.add(
        SmsReviewItem(
          id: 'review-${stored.sms.id}',
          smsMessage: stored.sms,
          parsed: parsed == null
              ? ParsedSmsTransaction(
                  detectedAmountMinor: 0,
                  confidence: 0,
                  categoryHint: 'expense',
                  description: stored.sms.body,
                  institution: EthiopianInstitution.unknown,
                )
              : await _applyUserKnowledge(stored.sms, parsed),
          status: 'pending',
        ),
      );
    }
    return items;
  }

  /// Books a pending parse. The reviewer may correct the category and/or
  /// flip the direction ([makeExpense]); a flipped row whose category no
  /// longer fits its direction falls back to the bare income/expense bucket.
  Future<void> approveReviewItem(
    SmsReviewItem item, {
    String? categoryOverride,
    bool? makeExpense,
  }) async {
    final transactionId = 'sms-${item.smsMessage.id}';
    final existing = await _ledgerRepository.getTransactionById(transactionId);
    if (existing == null) return;

    final wasExpense = existing.type == TransactionType.expense;
    final isExpense = makeExpense ?? wasExpense;
    var categoryId = categoryOverride ?? existing.categoryId;
    if (isExpense != wasExpense && categoryOverride == null) {
      categoryId = isExpense ? 'expense' : 'income';
    }
    final updated = existing.copyWith(
      categoryId: categoryId,
      type: isExpense ? TransactionType.expense : TransactionType.income,
      reviewStatus: TransactionReviewStatus.autoAccepted,
    );
    if (categoryOverride != null && categoryOverride != existing.categoryId) {
      await learnRuleFromSms(
        body: item.smsMessage.body,
        isExpense: isExpense,
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

  /// Removes a transaction the user does not want in the ledger. For an
  /// SMS-derived row the stored message is marked rejected too, so the next
  /// rebuild-sync honours the decision instead of re-creating the row.
  Future<void> removeTransaction(String transactionId) async {
    await _ledgerRepository.deleteTransaction(transactionId);
    const prefix = 'sms-';
    if (!transactionId.startsWith(prefix)) return;
    final stored = await _smsMessageRepository
        .getById(transactionId.substring(prefix.length));
    if (stored == null) return;
    await _smsMessageRepository.save(
      stored.copyWith(
        status: SmsIngestionStatus.rejected,
        parsedTransactionId: transactionId,
        failureReason: 'Deleted by user',
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

  /// Re-runs the CURRENT parser + learned rules over every stored SMS and
  /// rewrites the resulting transactions in place (amount, direction,
  /// category, balance). Used after parser upgrades so history benefits from
  /// fixes. Rejected/failed/duplicate messages stay untouched; review status
  /// is preserved. Note: manual category edits without a learned rule will
  /// be recomputed — the UI warns before running. Returns how many
  /// transactions changed.
  Future<int> reparseAllStoredMessages() async {
    final stored = await _smsMessageRepository.getAll();
    var changed = 0;
    for (final message in stored) {
      if (message.status != SmsIngestionStatus.parsed &&
          message.status != SmsIngestionStatus.pendingReview) {
        continue;
      }
      final rawParsed = _parser.parse(message.sms);
      if (rawParsed == null) continue;
      final transactionId = 'sms-${message.sms.id}';
      final existing =
          await _ledgerRepository.getTransactionById(transactionId);
      if (existing == null) continue;

      final parsed = await _applyUserKnowledge(message.sms, rawParsed);
      final isExpense = parsed.detectedAmountMinor < 0;
      final type = isExpense ? TransactionType.expense : TransactionType.income;

      final updated = existing.copyWith(
        type: type,
        amount: Money(minorUnits: parsed.detectedAmountMinor.abs()),
        categoryId: parsed.categoryHint,
        parserConfidence: parsed.confidence,
        statementBalanceMinor: parsed.balanceMinor,
      );
      final unchanged = updated.type == existing.type &&
          updated.amount.minorUnits == existing.amount.minorUnits &&
          updated.categoryId == existing.categoryId;
      if (unchanged) continue;

      final hadEntry =
          await _ledgerRepository.hasLedgerEntryForTransaction(transactionId);
      await _ledgerRepository.deleteTransaction(transactionId);
      await _ledgerRepository.saveTransaction(updated);
      if (hadEntry) {
        await _appendLedgerIfMissing(updated);
      }
      changed += 1;
    }
    AppLogger.info('sms.reparse', 'Re-parsed history: $changed updated');
    return changed;
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
