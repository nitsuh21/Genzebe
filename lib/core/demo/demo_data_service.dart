import 'package:genzeb/features/budget/domain/models/budget.dart';
import 'package:genzeb/features/budget/domain/repositories/budget_repository.dart';
import 'package:genzeb/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/transactions/domain/models/money.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:genzeb/features/transactions/domain/repositories/ledger_repository.dart';

/// Seeds a realistic three-month Ethiopian money story so every screen —
/// dashboard, ledger, budgets, reports, review queue — has something to show.
/// Deterministic ids make re-seeding overwrite rather than duplicate.
class DemoDataService {
  DemoDataService({
    required LedgerRepository ledgerRepository,
    required BudgetRepository budgetRepository,
    required SmsIngestionService smsIngestionService,
  })  : _ledger = ledgerRepository,
        _budgets = budgetRepository,
        _ingestion = smsIngestionService;

  final LedgerRepository _ledger;
  final BudgetRepository _budgets;
  final SmsIngestionService _ingestion;

  Future<bool> hasAnyData() async {
    final transactions = await _ledger.getTransactions();
    return transactions.isNotEmpty;
  }

  Future<int> seed() async {
    final now = DateTime.now();

    await _ledger.upsertAccount(Account(
      id: 'cbe-main',
      name: 'CBE Main',
      kind: 'bank',
      createdAt: now,
      institutionCode: 'cbe',
      maskedAccount: '****3489',
    ));
    await _ledger.upsertAccount(Account(
      id: 'telebirr-main',
      name: 'Telebirr Wallet',
      kind: 'wallet',
      createdAt: now,
      institutionCode: 'telebirr',
      maskedAccount: '09** *** 782',
    ));
    await _ledger.upsertAccount(Account(
      id: 'awash-main',
      name: 'Awash Savings',
      kind: 'bank',
      createdAt: now,
      institutionCode: 'awash',
      maskedAccount: '****1120',
    ));

    var count = 0;
    Future<void> add({
      required String id,
      required String accountId,
      required TransactionType type,
      required int amountMinor,
      required DateTime at,
      required String categoryId,
      required String sender,
      required String snippet,
      int? balanceMinor,
    }) async {
      // The month loop lays out a full calendar month; days still ahead of
      // us must not appear as history.
      if (at.isAfter(now)) return;
      final record = TransactionRecord(
        id: 'demo-$id',
        accountId: accountId,
        type: type,
        amount: Money(minorUnits: amountMinor),
        occurredAt: at,
        categoryId: categoryId,
        source: TransactionSource.sms,
        smsSender: sender,
        smsSnippet: snippet,
        parserConfidence: 0.96,
        statementBalanceMinor: balanceMinor,
      );
      await _ledger.saveTransaction(record);
      await _ledger.appendLedgerEntry(LedgerEntry(
        id: 'ledger-demo-$id',
        transactionId: record.id,
        accountId: accountId,
        delta: Money(
          minorUnits: type == TransactionType.income ||
                  type == TransactionType.transferIn
              ? amountMinor
              : -amountMinor,
        ),
        createdAt: at,
        source: TransactionSource.sms,
      ));
      count += 1;
    }

    // Three months of life in Addis: salary in, rent out, telebirr everywhere.
    for (var monthAgo = 2; monthAgo >= 0; monthAgo--) {
      final monthAnchor = DateTime(now.year, now.month - monthAgo, 1);
      final m = monthAgo;

      await add(
        id: 'salary-$m',
        accountId: 'cbe-main',
        type: TransactionType.income,
        amountMinor: 2850000,
        at: monthAnchor.add(const Duration(days: 1, hours: 9)),
        categoryId: 'salary',
        sender: 'CBE',
        snippet: 'Dear customer, your account ****3489 has been credited '
            'with ETB 28,500.00 salary payment. Balance ETB 41,203.55',
        balanceMinor: 4120355,
      );
      await add(
        id: 'rent-$m',
        accountId: 'cbe-main',
        type: TransactionType.expense,
        amountMinor: 950000,
        at: monthAnchor.add(const Duration(days: 2, hours: 11)),
        categoryId: 'rent',
        sender: 'CBE',
        snippet: 'Your account ****3489 was debited with ETB 9,500.00 '
            'transferred to W/ro Almaz — house rent. Service charge ETB 25.00',
      );
      await add(
        id: 'savings-$m',
        accountId: 'awash-main',
        type: TransactionType.transferIn,
        amountMinor: 400000,
        at: monthAnchor.add(const Duration(days: 3, hours: 10)),
        categoryId: 'savings',
        sender: 'AWASH',
        snippet: 'Awash Bank: ETB 4,000.00 deposit to your savings account '
            '****1120. Balance ETB 62,400.00',
        balanceMinor: 6240000,
      );
      // Monthly wallet top-up from the bank: two legs, minutes apart, so the
      // flow engine pairs them as an own transfer — and the wallet stays
      // positive despite all the telebirr spending below.
      await add(
        id: 'topup-out-$m',
        accountId: 'cbe-main',
        type: TransactionType.transferOut,
        amountMinor: 1000000,
        at: monthAnchor.add(const Duration(days: 4, hours: 10)),
        categoryId: 'transfer_out',
        sender: 'CBE',
        snippet: 'Dear customer, your account ****3489 has been debited with '
            'ETB 10,000.00 transferred to telebirr 09********2. '
            'Service charge ETB 5.00',
      );
      await add(
        id: 'topup-in-$m',
        accountId: 'telebirr-main',
        type: TransactionType.transferIn,
        amountMinor: 1000000,
        at: monthAnchor.add(const Duration(days: 4, hours: 10, minutes: 3)),
        categoryId: 'transfer_in',
        sender: 'telebirr',
        snippet: 'You have received ETB 10,000.00 from CBE account ****3489 '
            'via telebirr. Your current balance is ETB 10,175.00',
        balanceMinor: 1017500,
      );
      await add(
        id: 'dstv-$m',
        accountId: 'telebirr-main',
        type: TransactionType.expense,
        amountMinor: 82500,
        at: monthAnchor.add(const Duration(days: 5, hours: 19)),
        categoryId: 'bills',
        sender: 'telebirr',
        snippet: 'You have paid ETB 825.00 for DSTV monthly subscription '
            'via telebirr. Transaction number CG7${m}JK20',
      );

      for (var week = 0; week < 4; week++) {
        final w = monthAnchor.add(Duration(days: 6 + week * 7));
        await add(
          id: 'grocery-$m-$week',
          accountId: 'telebirr-main',
          type: TransactionType.expense,
          amountMinor: 120000 + (week * 17500) + (m * 9000),
          at: w.add(const Duration(hours: 18)),
          categoryId: 'groceries',
          sender: 'telebirr',
          snippet: 'You have paid ETB '
              '${((120000 + week * 17500 + m * 9000) / 100).toStringAsFixed(2)} '
              'to Shoa Supermarket via telebirr.',
        );
        await add(
          id: 'transport-$m-$week',
          accountId: 'telebirr-main',
          type: TransactionType.expense,
          amountMinor: 18000 + (week * 4500),
          at: w.add(const Duration(days: 2, hours: 8)),
          categoryId: 'transport',
          sender: 'telebirr',
          snippet: 'You have paid ETB '
              '${((18000 + week * 4500) / 100).toStringAsFixed(2)} '
              'for Ride trip via telebirr.',
        );
      }

      await add(
        id: 'coffee-$m',
        accountId: 'telebirr-main',
        type: TransactionType.expense,
        amountMinor: 46000 + m * 8000,
        at: monthAnchor.add(const Duration(days: 12, hours: 16)),
        categoryId: 'food',
        sender: 'telebirr',
        snippet:
            'You have paid ETB ${((46000 + m * 8000) / 100).toStringAsFixed(2)} '
            'to Tomoca Coffee via telebirr.',
      );
      await add(
        id: 'airtime-$m',
        accountId: 'telebirr-main',
        type: TransactionType.expense,
        amountMinor: 20000,
        at: monthAnchor.add(const Duration(days: 14, hours: 12)),
        categoryId: 'airtime',
        sender: 'telebirr',
        snippet: 'You purchased airtime of ETB 200.00 for 09********2 '
            'via telebirr.',
      );
      await add(
        id: 'family-$m',
        accountId: 'telebirr-main',
        type: TransactionType.transferOut,
        amountMinor: 150000,
        at: monthAnchor.add(const Duration(days: 20, hours: 13)),
        categoryId: 'transfer_out',
        sender: 'telebirr',
        snippet: 'You have sent ETB 1,500.00 to Emebet K. via telebirr. '
            'Transaction number BF3${m}WQ11',
      );
    }

    // Freelance income only in the current month, so the trend line moves.
    await add(
      id: 'freelance-0',
      accountId: 'cbe-main',
      type: TransactionType.income,
      amountMinor: 620000,
      at: DateTime(now.year, now.month, 1).add(const Duration(days: 16)),
      categoryId: 'income',
      sender: 'CBE',
      snippet: 'Dear customer, your account ****3489 has been credited with '
          'ETB 6,200.00. Ref FREELNC01',
    );

    await _budgets.upsertBudget(Budget(
      id: 'demo-budget-food',
      name: 'Food & groceries',
      categoryIds: const ['food', 'groceries'],
      limitMinor: 800000,
      createdAt: now,
    ));
    await _budgets.upsertBudget(Budget(
      id: 'demo-budget-transport',
      name: 'Getting around',
      categoryIds: const ['transport'],
      limitMinor: 250000,
      createdAt: now,
    ));
    await _budgets.upsertBudget(Budget(
      id: 'demo-budget-all',
      name: 'Monthly lifestyle',
      categoryIds: const [],
      limitMinor: 2200000,
      createdAt: now,
    ));

    // Two ambiguous messages land in the review queue so that flow is
    // visible too (unknown sender -> parser confidence below the threshold).
    await _ingestion.ingest(
      sms: SmsMessage(
        id: 'demo-review-1',
        sender: 'EthioMart',
        body: 'You paid 320.00 birr at EthioMart Bole branch. Thank you for '
            'shopping with us.',
        receivedAt: now.subtract(const Duration(days: 1, hours: 3)),
      ),
    );
    await _ingestion.ingest(
      sms: SmsMessage(
        id: 'demo-review-2',
        sender: '8294',
        body: 'Payment of 150.00 birr received for order #4432. GebeyaGo '
            'delivery on the way.',
        receivedAt: now.subtract(const Duration(hours: 5)),
      ),
    );

    return count;
  }
}
