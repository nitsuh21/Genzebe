import 'package:flutter_test/flutter_test.dart';
import 'package:genzeb/features/sms_ingestion/application/account_mapping_service.dart';
import 'package:genzeb/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzeb/features/sms_ingestion/data/in_memory_category_rule_repository.dart';
import 'package:genzeb/features/sms_ingestion/data/in_memory_sms_message_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/transactions/data/in_memory_ledger_repository.dart';
import 'package:genzeb/features/transactions/domain/models/money.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

SmsIngestionService _buildIngestion(
  InMemoryLedgerRepository ledger,
  InMemorySmsMessageRepository smsStore,
) {
  return SmsIngestionService(
    parser: SmsParserEngine(
      const [
        CbeSmsParserTemplate(),
        AwashSmsParserTemplate(),
        TelebirrSmsParserTemplate(),
        BoaSmsParserTemplate(),
        HibretSmsParserTemplate(),
        DashenSmsParserTemplate(),
        GenericAmountParserTemplate(),
      ],
    ),
    ledgerRepository: ledger,
    smsMessageRepository: smsStore,
    accountMappingService: AccountMappingService(ledger),
      categoryRuleRepository: InMemoryCategoryRuleRepository(),
  );
}

// Unknown sender parsed by the generic template scores 0.82, which lands in
// the review queue (threshold 0.85).
final _lowConfidenceSms = SmsMessage(
  id: 'unknown-1',
  sender: 'SOMEBANK',
  body: 'You paid 320.00 birr at cafe. Thank you.',
  receivedAt: DateTime(2026, 6, 3, 10, 0),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('re-parse history rescues rows frozen with an old wrong parse',
      () async {
    final ledger = InMemoryLedgerRepository();
    final smsStore = InMemorySmsMessageRepository();
    final ingestion = _buildIngestion(ledger, smsStore);

    // The user's real CBE transfer, stored as it was ingested by the OLD
    // parser: income, base amount instead of total.
    final sms = SmsMessage(
      id: 'cbe-old-1',
      sender: 'CBE',
      body: 'Dear Nitsuh Demissew Mekonnen You have successfully '
          'transferred ETB1100.00 from account 1**9722 to account 1**4607 '
          '(Nebyou Elias Zewde). Service charge of ETB 1.00 and VAT(15%) of '
          'ETB0.15 and Disaster Recovery(5%) of 0.05 with total of '
          'ETB1101.20 .Your current balance is ETB89,468.32. Thanks for '
          'Banking with CBE.',
      receivedAt: DateTime(2026, 7, 8, 9, 0),
    );
    await smsStore.save(StoredSmsMessage(
      sms: sms,
      messageHash: 'legacy-hash',
      status: SmsIngestionStatus.parsed,
      parsedTransactionId: 'sms-cbe-old-1',
      ingestedAt: DateTime(2026, 7, 8, 9, 1),
    ));
    await ledger.saveTransaction(TransactionRecord(
      id: 'sms-cbe-old-1',
      accountId: 'cbe-main',
      type: TransactionType.income, // the old misparse
      amount: const Money(minorUnits: 110000),
      occurredAt: DateTime(2026, 7, 8, 9, 0),
      categoryId: 'income',
      source: TransactionSource.sms,
      smsSender: 'CBE',
      smsSnippet: sms.body,
    ));
    await ledger.appendLedgerEntry(LedgerEntry(
      id: 'ledger-sms-cbe-old-1',
      transactionId: 'sms-cbe-old-1',
      accountId: 'cbe-main',
      delta: const Money(minorUnits: 110000),
      createdAt: DateTime(2026, 7, 8, 9, 1),
      source: TransactionSource.sms,
    ));

    final changed = await ingestion.reparseAllStoredMessages();

    expect(changed, 1);
    final fixed = await ledger.getTransactionById('sms-cbe-old-1');
    expect(fixed!.type, TransactionType.expense);
    expect(fixed.amount.minorUnits, 110120); // total incl. charges
    expect(fixed.categoryId, 'transfer_out');
    final entry = (await ledger.getLedgerEntries()).single;
    expect(entry.delta.minorUnits, -110120);
  });

  test('rejecting a review item deletes its transaction and ledger entries',
      () async {
    final ledger = InMemoryLedgerRepository();
    final smsStore = InMemorySmsMessageRepository();
    final ingestion = _buildIngestion(ledger, smsStore);

    await ingestion.ingest(sms: _lowConfidenceSms);
    final queue = await ingestion.getReviewQueue();
    expect(queue, hasLength(1));
    expect(await ledger.getTransactionById('sms-unknown-1'), isNotNull);

    await ingestion.rejectReviewItem(queue.first, reason: 'not mine');

    expect(await ledger.getTransactionById('sms-unknown-1'), isNull);
    expect(await ledger.getLedgerEntries(), isEmpty);
    expect(await ingestion.getReviewQueue(), isEmpty);
  });

  test('re-ingesting after a decision does not clobber it', () async {
    final ledger = InMemoryLedgerRepository();
    final smsStore = InMemorySmsMessageRepository();
    final ingestion = _buildIngestion(ledger, smsStore);

    await ingestion.ingest(sms: _lowConfidenceSms);
    final queue = await ingestion.getReviewQueue();
    await ingestion.approveReviewItem(queue.first);
    final approved = await ledger.getTransactionById('sms-unknown-1');
    expect(approved!.reviewStatus, TransactionReviewStatus.autoAccepted);

    // Simulate the next force sync after an app restart: a new service
    // instance sees the same device SMS again. The persisted decision must
    // survive instead of the transaction dropping back to pending review.
    final rebooted = _buildIngestion(ledger, smsStore);
    await rebooted.ingest(sms: _lowConfidenceSms);

    final after = await ledger.getTransactionById('sms-unknown-1');
    expect(after!.reviewStatus, TransactionReviewStatus.autoAccepted);
    expect(await rebooted.getReviewQueue(), isEmpty);

    // A rejected message must stay rejected too.
    await rebooted.rejectReviewItem(
      SmsReviewItem(
        id: 'review-unknown-1',
        smsMessage: _lowConfidenceSms,
        parsed: const ParsedSmsTransaction(
          detectedAmountMinor: -32000,
          confidence: 0.6,
          categoryHint: 'food',
          description: 'cafe',
          institution: EthiopianInstitution.unknown,
        ),
        status: 'pending',
      ),
    );
    await rebooted.ingest(sms: _lowConfidenceSms);
    expect(await ledger.getTransactionById('sms-unknown-1'), isNull);
  });
}
