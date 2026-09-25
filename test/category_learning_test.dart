import 'package:flutter_test/flutter_test.dart';
import 'package:genzeb/features/sms_ingestion/application/account_resolver.dart';
import 'package:genzeb/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzeb/features/sms_ingestion/data/in_memory_category_rule_repository.dart';
import 'package:genzeb/features/sms_ingestion/data/in_memory_sms_message_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/transactions/application/transaction_service.dart';
import 'package:genzeb/features/transactions/data/in_memory_ledger_repository.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

SmsIngestionService _ingestion(
  InMemoryLedgerRepository ledger,
  InMemoryCategoryRuleRepository rules,
) {
  return SmsIngestionService(
    parser: buildDefaultSmsParserEngine(),
    ledgerRepository: ledger,
    smsMessageRepository: InMemorySmsMessageRepository(),
    accountResolver: AccountResolver(ledger),
    categoryRuleRepository: rules,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('merchant extraction', () {
    test('telebirr paid-to pattern', () {
      expect(
        extractMerchant(
          'You have paid ETB 120.00 to Shoa Supermarket via telebirr.',
          isExpense: true,
        ),
        'Shoa Supermarket',
      );
    });

    test('CBE transferred-to pattern stops at punctuation', () {
      expect(
        extractMerchant(
          'Your account was debited with ETB 9,500.00 transferred to '
          'W/ro Almaz — house rent.',
          isExpense: true,
        ),
        'W/ro Almaz',
      );
    });

    test('income from pattern', () {
      expect(
        extractMerchant(
          'You have received ETB 500.00 from Emebet K. via telebirr.',
          isExpense: false,
        ),
        'Emebet K',
      );
    });

    test('masked accounts are not merchants', () {
      expect(
        extractMerchant(
          'Debited ETB 100.00 at ****3489',
          isExpense: true,
        ),
        isNull,
      );
    });
  });

  group('expanded dictionary', () {
    test('Ethiopian ride app goes to transport', () {
      expect(
        inferCategory(
          body: 'you have paid etb 260.00 for feres trip via telebirr',
          isExpense: true,
        ),
        'transport',
      );
    });

    test('Amharic salary keyword goes to salary', () {
      expect(
        inferCategory(body: 'ደመወዝ ገቢ ተደርጓል', isExpense: false),
        'salary',
      );
    });

    test('equb goes to savings', () {
      expect(
        inferCategory(
            body: 'paid etb 500 for equb contribution', isExpense: true),
        'savings',
      );
    });
  });

  test('learned rule overrides the keyword guess on the next sync', () async {
    final ledger = InMemoryLedgerRepository();
    final rules = InMemoryCategoryRuleRepository();
    final ingestion = _ingestion(ledger, rules);

    // "hotel" keyword sends this to food, but Soreti Hotel is really rent
    // for this user. First ingest: wrong category.
    final sms1 = SmsMessage(
      id: 'tb-1',
      sender: 'telebirr',
      body: 'You have paid ETB 5,000.00 to Soreti Hotel via telebirr. '
          'Transaction number ABC123',
      receivedAt: DateTime(2026, 7, 1, 10, 0),
    );
    await ingestion.ingest(sms: sms1);
    final first = await ledger.getTransactionById('sms-tb-1');
    expect(first!.categoryId, 'food');

    // The user corrects it; the merchant rule is learned.
    final service = TransactionService(ledger, rules);
    final learned = await service.changeCategory(
      transactionId: 'sms-tb-1',
      categoryId: 'rent',
    );
    expect(learned, 'Soreti Hotel');
    expect(
      (await ledger.getTransactionById('sms-tb-1'))!.categoryId,
      'rent',
    );

    // Next month, same merchant: categorized right automatically, with
    // rule-level confidence (no review queue detour).
    final sms2 = SmsMessage(
      id: 'tb-2',
      sender: 'telebirr',
      body: 'You have paid ETB 5,000.00 to Soreti Hotel via telebirr. '
          'Transaction number DEF456',
      receivedAt: DateTime(2026, 8, 1, 10, 0),
    );
    await ingestion.ingest(sms: sms2);
    final second = await ledger.getTransactionById('sms-tb-2');
    expect(second!.categoryId, 'rent');
    expect(second.reviewStatus, TransactionReviewStatus.autoAccepted);
  });

  test('approving a review item with a category override learns a rule',
      () async {
    final ledger = InMemoryLedgerRepository();
    final rules = InMemoryCategoryRuleRepository();
    final ingestion = _ingestion(ledger, rules);

    // Unknown sender -> generic parse -> review queue.
    await ingestion.ingest(
      sms: SmsMessage(
        id: 'gen-1',
        sender: 'GebeyaGo',
        body: 'You paid 320.00 birr to GebeyaGo Delivery via app. Thank you.',
        receivedAt: DateTime(2026, 7, 2, 12, 0),
      ),
    );
    final queue = await ingestion.getReviewQueue();
    expect(queue, hasLength(1));

    await ingestion.approveReviewItem(queue.first, categoryOverride: 'food');
    expect(
      (await ledger.getTransactionById('sms-gen-1'))!.categoryId,
      'food',
    );
    expect(
      await rules.categoryForMerchant(normalizeMerchant('GebeyaGo Delivery')),
      'food',
    );
  });
}
