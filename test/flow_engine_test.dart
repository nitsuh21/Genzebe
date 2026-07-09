import 'package:flutter_test/flutter_test.dart';
import 'package:genzeb/features/reports/application/report_service.dart';
import 'package:genzeb/features/sms_ingestion/application/account_mapping_service.dart';
import 'package:genzeb/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzeb/features/sms_ingestion/data/in_memory_category_rule_repository.dart';
import 'package:genzeb/features/sms_ingestion/data/in_memory_sms_message_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/transactions/data/in_memory_ledger_repository.dart';
import 'package:genzeb/features/transactions/domain/models/money.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _cbeTransferBody =
    'Dear Nitsuh Demissew Mekonnen You have successfully transferred '
    'ETB1100.00 from account 1**9722 to account 1**4607. Service charge of '
    'ETB 1.00 and VAT(15%) of ETB0.15 and Disaster Recovery(5%) of 0.05 '
    'with total of ETB1101.20 .Your current balance is ETB89,468.32.';

TransactionRecord _tx({
  required String id,
  required String accountId,
  required TransactionType type,
  required int amountMinor,
  required DateTime at,
  String categoryId = 'expense',
  String? snippet,
  int? balanceMinor,
  TransactionReviewStatus reviewStatus = TransactionReviewStatus.autoAccepted,
}) {
  return TransactionRecord(
    id: id,
    accountId: accountId,
    type: type,
    amount: Money(minorUnits: amountMinor),
    occurredAt: at,
    categoryId: categoryId,
    source: TransactionSource.sms,
    smsSender: accountId,
    smsSnippet: snippet,
    statementBalanceMinor: balanceMinor,
    reviewStatus: reviewStatus,
  );
}

Future<ReportService> _service(InMemoryLedgerRepository ledger) async {
  final ingestion = SmsIngestionService(
    parser: SmsParserEngine(const [GenericAmountParserTemplate()]),
    ledgerRepository: ledger,
    smsMessageRepository: InMemorySmsMessageRepository(),
    accountMappingService: AccountMappingService(ledger),
    categoryRuleRepository: InMemoryCategoryRuleRepository(),
  );
  return ReportService(ledger, ingestion);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('itemized fees parse from a real CBE receipt', () {
    // 1.00 + 0.15 + 0.05 = ETB 1.20
    expect(extractItemizedFeesMinor(_cbeTransferBody), 120);
  });

  test('a CBE->telebirr transfer pair never counts as income or spending',
      () async {
    final ledger = InMemoryLedgerRepository();
    final t = DateTime(2026, 7, 5, 10, 0);
    // Outflow leg: total incl. fees. Inflow leg: net amount, minutes later.
    await ledger.saveTransaction(_tx(
      id: 'out-1',
      accountId: 'cbe-main',
      type: TransactionType.transferOut,
      amountMinor: 110120,
      at: t,
      categoryId: 'transfer_out',
      snippet: _cbeTransferBody,
    ));
    await ledger.saveTransaction(_tx(
      id: 'in-1',
      accountId: 'telebirr-main',
      type: TransactionType.income,
      amountMinor: 110000,
      at: t.add(const Duration(minutes: 3)),
      categoryId: 'income',
    ));
    // Plus a real salary and a real purchase for contrast.
    await ledger.saveTransaction(_tx(
      id: 'salary-1',
      accountId: 'cbe-main',
      type: TransactionType.income,
      amountMinor: 2000000,
      at: DateTime(2026, 7, 1),
      categoryId: 'salary',
    ));
    await ledger.saveTransaction(_tx(
      id: 'spend-1',
      accountId: 'telebirr-main',
      type: TransactionType.expense,
      amountMinor: 50000,
      at: DateTime(2026, 7, 6),
      categoryId: 'groceries',
    ));

    final service = await _service(ledger);
    final report = await service.generateReportForRange(
      startInclusive: DateTime(2026, 7, 1),
      endExclusive: DateTime(2026, 8, 1),
    );

    // Income = salary only; the telebirr credit is an internal leg.
    expect(report.incomeMinor, 2000000);
    // Expense = groceries + the ETB 1.20 fee lost in the transfer.
    expect(report.expenseMinor, 50000 + 120);
    expect(report.categoryTotalsMinor['groceries'], 50000);
    expect(report.categoryTotalsMinor['fees'], 120);
    expect(report.internalMovedMinor, 110120);
    expect(report.feesMinor, 120);
  });

  test('savings outflow counts as own transfer, not spending', () async {
    final ledger = InMemoryLedgerRepository();
    await ledger.saveTransaction(_tx(
      id: 'sav-1',
      accountId: 'cbe-main',
      type: TransactionType.expense,
      amountMinor: 400000,
      at: DateTime(2026, 7, 3),
      categoryId: 'savings',
    ));
    final service = await _service(ledger);
    final report = await service.generateReportForRange(
      startInclusive: DateTime(2026, 7, 1),
      endExclusive: DateTime(2026, 8, 1),
    );
    expect(report.expenseMinor, 0);
    expect(report.internalMovedMinor, 400000);
  });

  test('same-account opposite flows are NOT paired (refund stays income)',
      () async {
    final ledger = InMemoryLedgerRepository();
    final t = DateTime(2026, 7, 4, 9, 0);
    await ledger.saveTransaction(_tx(
      id: 'buy-1',
      accountId: 'telebirr-main',
      type: TransactionType.expense,
      amountMinor: 30000,
      at: t,
      categoryId: 'shopping',
    ));
    await ledger.saveTransaction(_tx(
      id: 'refund-1',
      accountId: 'telebirr-main',
      type: TransactionType.income,
      amountMinor: 30000,
      at: t.add(const Duration(hours: 1)),
      categoryId: 'income',
    ));
    final service = await _service(ledger);
    final report = await service.generateReportForRange(
      startInclusive: DateTime(2026, 7, 1),
      endExclusive: DateTime(2026, 8, 1),
    );
    expect(report.incomeMinor, 30000);
    expect(report.expenseMinor, 30000);
    expect(report.internalMovedMinor, 0);
  });

  test(
      'coincidental same-amount purchase and credit are NOT a transfer pair',
      () async {
    final ledger = InMemoryLedgerRepository();
    final t = DateTime(2026, 7, 10, 12, 0);
    // A grocery payment (not transfer-ish) and an unrelated same-amount
    // credit on another account an hour later — real income + real expense.
    await ledger.saveTransaction(_tx(
      id: 'buy-x',
      accountId: 'telebirr-main',
      type: TransactionType.expense,
      amountMinor: 50000,
      at: t,
      categoryId: 'groceries',
      snippet: 'You have paid ETB 500.00 to Shoa Supermarket via telebirr.',
    ));
    await ledger.saveTransaction(_tx(
      id: 'gift-x',
      accountId: 'cbe-main',
      type: TransactionType.income,
      amountMinor: 50000,
      at: t.add(const Duration(hours: 1)),
      categoryId: 'income',
      snippet: 'Dear customer your account has been credited with ETB 500.00',
    ));
    final service = await _service(ledger);
    final report = await service.generateReportForRange(
      startInclusive: DateTime(2026, 7, 1),
      endExclusive: DateTime(2026, 8, 1),
    );
    expect(report.incomeMinor, 50000);
    expect(report.expenseMinor, 50000);
    expect(report.internalMovedMinor, 0);
  });

  test('transfer legs more than 3 hours apart are not paired', () async {
    final ledger = InMemoryLedgerRepository();
    final t = DateTime(2026, 7, 11, 8, 0);
    await ledger.saveTransaction(_tx(
      id: 'slow-out',
      accountId: 'cbe-main',
      type: TransactionType.transferOut,
      amountMinor: 100000,
      at: t,
      categoryId: 'transfer_out',
      snippet: 'You have successfully transferred ETB1000.00 from account '
          '1**9722 to account 1**4607.',
    ));
    await ledger.saveTransaction(_tx(
      id: 'slow-in',
      accountId: 'telebirr-main',
      type: TransactionType.income,
      amountMinor: 100000,
      at: t.add(const Duration(hours: 5)),
      categoryId: 'income',
    ));
    final service = await _service(ledger);
    final report = await service.generateReportForRange(
      startInclusive: DateTime(2026, 7, 1),
      endExclusive: DateTime(2026, 8, 1),
    );
    expect(report.internalMovedMinor, 0);
  });

  test('salary credit is never swallowed as a transfer leg', () async {
    final ledger = InMemoryLedgerRepository();
    final t = DateTime(2026, 7, 12, 9, 0);
    await ledger.saveTransaction(_tx(
      id: 'send-y',
      accountId: 'telebirr-main',
      type: TransactionType.transferOut,
      amountMinor: 2000000,
      at: t,
      categoryId: 'transfer_out',
      snippet: 'You have transferred ETB 20,000.00 to Abebe via telebirr',
    ));
    await ledger.saveTransaction(_tx(
      id: 'salary-y',
      accountId: 'cbe-main',
      type: TransactionType.income,
      amountMinor: 2000000,
      at: t.add(const Duration(minutes: 30)),
      categoryId: 'salary',
    ));
    final service = await _service(ledger);
    final report = await service.generateReportForRange(
      startInclusive: DateTime(2026, 7, 1),
      endExclusive: DateTime(2026, 8, 1),
    );
    expect(report.incomeMinor, 2000000);
    expect(report.internalMovedMinor, 0);
  });

  test('fees are never overstated: itemized charge wins over category',
      () async {
    final ledger = InMemoryLedgerRepository();
    // Historic misparse: a 5,000 debit that mentions charges got
    // categorized as fees. Only the itemized ETB 11.50 is a bank fee.
    await ledger.saveTransaction(_tx(
      id: 'fee-mis',
      accountId: 'cbe-main',
      type: TransactionType.expense,
      amountMinor: 501200,
      at: DateTime(2026, 7, 5),
      categoryId: 'fees',
      snippet: 'Your account has been debited with ETB5,000.00. Service '
          'charge of ETB 10.00 and VAT(15%) of ETB1.50 with a total of '
          'ETB 5012.00.',
    ));
    // A genuine standalone charge with no itemization counts fully.
    await ledger.saveTransaction(_tx(
      id: 'fee-pure',
      accountId: 'cbe-main',
      type: TransactionType.expense,
      amountMinor: 230,
      at: DateTime(2026, 7, 6),
      categoryId: 'fees',
      snippet: 'Your account was debited ETB 2.30 for SMS alert.',
    ));
    final service = await _service(ledger);
    final report = await service.generateReportForRange(
      startInclusive: DateTime(2026, 7, 1),
      endExclusive: DateTime(2026, 8, 1),
    );
    expect(report.feesMinor, 1150 + 230);
  });

  test('pending parses are excluded and counted', () async {
    final ledger = InMemoryLedgerRepository();
    await ledger.saveTransaction(_tx(
      id: 'pend-1',
      accountId: 'main-wallet',
      type: TransactionType.expense,
      amountMinor: 99900,
      at: DateTime(2026, 7, 2),
      reviewStatus: TransactionReviewStatus.pendingReview,
    ));
    final service = await _service(ledger);
    final report = await service.generateReportForRange(
      startInclusive: DateTime(2026, 7, 1),
      endExclusive: DateTime(2026, 8, 1),
    );
    expect(report.expenseMinor, 0);
    expect(report.pendingCount, 1);
  });

  test('period report: merchants, biggest, balance series, previous window',
      () async {
    final ledger = InMemoryLedgerRepository();
    for (var i = 0; i < 3; i++) {
      await ledger.saveTransaction(_tx(
        id: 'shoa-$i',
        accountId: 'telebirr-main',
        type: TransactionType.expense,
        amountMinor: 100000 + i * 10000,
        at: DateTime(2026, 7, 2 + i),
        categoryId: 'groceries',
        snippet:
            'You have paid ETB ${(1000 + i * 100)}.00 to Shoa Supermarket via telebirr.',
        balanceMinor: 900000 - i * 100000,
      ));
    }
    await ledger.saveTransaction(_tx(
      id: 'prev-1',
      accountId: 'telebirr-main',
      type: TransactionType.expense,
      amountMinor: 70000,
      at: DateTime(2026, 6, 20),
      categoryId: 'food',
    ));

    final service = await _service(ledger);
    final period = await service.generatePeriodReport(
      startInclusive: DateTime(2026, 7, 1),
      endExclusive: DateTime(2026, 8, 1),
    );

    expect(period.totals.expenseMinor, 100000 + 110000 + 120000);
    expect(period.previousTotals.expenseMinor, 70000);
    expect(period.topMerchants.single.name, 'Shoa Supermarket');
    expect(period.topMerchants.single.count, 3);
    expect(period.biggestSpends.first.amount.minorUnits, 120000);
    expect(period.balanceSeries, hasLength(3));
    expect(period.balanceSeries.last.balanceMinor, 700000);
  });
}
