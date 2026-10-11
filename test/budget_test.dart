import 'package:flutter_test/flutter_test.dart';
import 'package:genzeb/core/l10n/app_strings.dart';
import 'package:genzeb/features/alerts/application/background_sms_handler.dart';
import 'package:genzeb/features/alerts/application/money_alert_service.dart';
import 'package:genzeb/features/alerts/data/money_alert_repositories.dart';
import 'package:genzeb/features/budget/application/budget_service.dart';
import 'package:genzeb/features/budget/data/in_memory_budget_repository.dart';
import 'package:genzeb/features/budget/domain/models/budget.dart';
import 'package:genzeb/features/sms_ingestion/application/account_resolver.dart';
import 'package:genzeb/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzeb/features/sms_ingestion/data/in_memory_category_rule_repository.dart';
import 'package:genzeb/features/sms_ingestion/data/in_memory_sms_message_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/transactions/data/in_memory_ledger_repository.dart';
import 'package:genzeb/features/transactions/domain/models/money.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';

/// Mid-October 2026, noon: 14.5 of 31 days gone.
final _now = DateTime(2026, 10, 15, 12);

TransactionRecord _tx(
  String id, {
  required int etb,
  required DateTime at,
  String categoryId = 'food',
  String accountId = 'cbe-main',
  TransactionType type = TransactionType.expense,
  TransactionReviewStatus reviewStatus = TransactionReviewStatus.autoAccepted,
  OwnTransferOverride ownTransfer = OwnTransferOverride.none,
}) {
  return TransactionRecord(
    id: id,
    accountId: accountId,
    type: type,
    amount: Money(minorUnits: etb * 100),
    occurredAt: at,
    categoryId: categoryId,
    source: TransactionSource.sms,
    reviewStatus: reviewStatus,
    ownTransfer: ownTransfer,
  );
}

Budget _budget(
  String id, {
  required int etb,
  List<String> categories = const [],
  List<String> institutions = const [],
  List<String> excluded = const [],
  BudgetPeriodKind kind = BudgetPeriodKind.monthly,
  int startDay = 1,
  DateTime? customStart,
  DateTime? customEnd,
  String? name,
}) {
  return Budget(
    id: id,
    name: name ?? id,
    categoryIds: categories,
    institutionCodes: institutions,
    excludedTransactionIds: excluded,
    limitMinor: etb * 100,
    createdAt: DateTime(2026, 1, 1),
    periodKind: kind,
    startDay: startDay,
    customStart: customStart,
    customEnd: customEnd,
  );
}

class _Fixture {
  _Fixture()
      : ledger = InMemoryLedgerRepository(),
        budgets = InMemoryBudgetRepository() {
    service = BudgetService(budgetRepository: budgets, ledgerRepository: ledger);
  }

  final InMemoryLedgerRepository ledger;
  final InMemoryBudgetRepository budgets;
  late final BudgetService service;

  Future<void> accounts() async {
    await ledger.upsertAccount(Account(
      id: 'cbe-main',
      name: 'CBE',
      kind: 'bank',
      createdAt: DateTime(2026, 1, 1),
      institutionCode: 'cbe',
    ));
    await ledger.upsertAccount(Account(
      id: 'telebirr-main',
      name: 'telebirr',
      kind: 'wallet',
      createdAt: DateTime(2026, 1, 1),
      institutionCode: 'telebirr',
    ));
  }

  Future<void> add(List<TransactionRecord> records) async {
    for (final record in records) {
      await ledger.saveTransaction(record);
    }
  }

  Future<void> save(List<Budget> list) async {
    for (final budget in list) {
      await budgets.upsertBudget(budget);
    }
  }
}

void main() {
  group('budget periods', () {
    test('a plain monthly budget is the calendar month', () {
      final period = _budget('b', etb: 1).periodContaining(_now);
      expect(period.start, DateTime(2026, 10, 1));
      expect(period.end, DateTime(2026, 11, 1));
      expect(period.totalDays, 31);
      expect(period.daysLeft(_now), 17); // Oct 15..31
    });

    test('a payday budget runs from the 25th to the 24th', () {
      final budget = _budget('b', etb: 1, startDay: 25);
      final before = budget.periodContaining(DateTime(2026, 10, 24, 23));
      expect(before.start, DateTime(2026, 9, 25));
      expect(before.end, DateTime(2026, 10, 25));
      final on = budget.periodContaining(DateTime(2026, 10, 25));
      expect(on.start, DateTime(2026, 10, 25));
      expect(on.end, DateTime(2026, 11, 25));
    });

    test('periods cross the new year', () {
      final period = _budget('b', etb: 1, startDay: 10)
          .periodContaining(DateTime(2027, 1, 5));
      expect(period.start, DateTime(2026, 12, 10));
      expect(period.end, DateTime(2027, 1, 10));
    });

    test('custom dates include the last day', () {
      final period = _budget(
        'trip',
        etb: 1,
        kind: BudgetPeriodKind.custom,
        customStart: DateTime(2026, 12, 20),
        customEnd: DateTime(2027, 1, 5),
      ).periodContaining(_now);
      expect(period.start, DateTime(2026, 12, 20));
      expect(period.end, DateTime(2027, 1, 6));
      expect(period.contains(DateTime(2027, 1, 5, 23, 59)), isTrue);
      expect(period.totalDays, 17);
    });
  });

  group('pace', () {
    BudgetProgress progress(int spentEtb) => BudgetProgress(
          budget: _budget('b', etb: 1000),
          period: _budget('b', etb: 1000).periodContaining(_now),
          spentMinor: spentEtb * 100,
          now: _now,
        );

    test('spending in line with the calendar is on track', () {
      // ~45% of October has passed.
      expect(progress(400).pace, BudgetPace.onTrack);
      expect(progress(400).perDayLeftMinor, 60000 ~/ 17);
    });

    test('spending well ahead of the calendar is flagged', () {
      expect(progress(700).pace, BudgetPace.ahead);
    });

    test('over the limit is over', () {
      expect(progress(1001).pace, BudgetPace.over);
      expect(progress(1001).perDayLeftMinor, isNull);
    });
  });

  group('overview', () {
    test('overlapping budgets count each birr once', () async {
      // The demo setup: an "everything" budget plus two inside it.
      final f = _Fixture();
      await f.save([
        _budget('all', etb: 22000),
        _budget('food', etb: 8000, categories: ['food', 'groceries']),
        _budget('transport', etb: 2500, categories: ['transport']),
      ]);
      await f.add([
        _tx('f1', etb: 1000, at: DateTime(2026, 10, 3)),
        _tx('t1', etb: 500, at: DateTime(2026, 10, 4), categoryId: 'transport'),
        _tx('r1', etb: 3000, at: DateTime(2026, 10, 2), categoryId: 'rent'),
      ]);

      final overview = await f.service.buildOverview(now: _now);
      final plan = overview.plan!;
      expect(plan.limitMinor, 2200000);
      expect(plan.budgetCount, 1);
      expect(plan.spentMinor, 450000);
      expect(plan.period, isNotNull);
      final spent = {
        for (final item in overview.items) item.budget.id: item.spentMinor,
      };
      expect(spent, {'all': 450000, 'food': 100000, 'transport': 50000});
      expect(overview.unbudgetedSpendMinor, 0);
    });

    test('side-by-side budgets add up and name what is left over', () async {
      final f = _Fixture();
      await f.save([
        _budget('food', etb: 8000, categories: ['food']),
        _budget('transport', etb: 2500, categories: ['transport']),
      ]);
      await f.add([
        _tx('f1', etb: 1000, at: DateTime(2026, 10, 3)),
        _tx('r1', etb: 3000, at: DateTime(2026, 10, 2), categoryId: 'rent'),
        _tx('s1', etb: 200, at: DateTime(2026, 10, 5), categoryId: 'shopping'),
      ]);

      final overview = await f.service.buildOverview(now: _now);
      expect(overview.plan!.limitMinor, 1050000);
      expect(overview.plan!.budgetCount, 2);
      expect(overview.plan!.spentMinor, 100000);
      expect(overview.unbudgetedSpendMinor, 320000);
      expect(overview.unbudgetedByCategory.first.key, 'rent');
    });

    test('own transfers and unconfirmed parses never count', () async {
      final f = _Fixture();
      await f.save([_budget('all', etb: 10000)]);
      await f.add([
        _tx('real', etb: 100, at: DateTime(2026, 10, 3)),
        _tx(
          'topup',
          etb: 2000,
          at: DateTime(2026, 10, 4),
          categoryId: 'transfer_out',
          ownTransfer: OwnTransferOverride.own,
        ),
        _tx(
          'unsure',
          etb: 500,
          at: DateTime(2026, 10, 5),
          reviewStatus: TransactionReviewStatus.pendingReview,
        ),
      ]);

      final overview = await f.service.buildOverview(now: _now);
      expect(overview.items.single.spentMinor, 10000);
      // The budget's own page agrees with its card.
      final detail = await f.service.buildDetail('all', now: _now);
      expect(detail!.progress.spentMinor, 10000);
      expect(detail.transactions.map((tx) => tx.id), ['real']);
    });

    test('a left-out transaction moves to the excluded list', () async {
      final f = _Fixture();
      await f.save([
        _budget('food', etb: 8000, categories: ['food'], excluded: ['f2']),
      ]);
      await f.add([
        _tx('f1', etb: 100, at: DateTime(2026, 10, 3)),
        _tx('f2', etb: 900, at: DateTime(2026, 10, 4)),
      ]);

      final detail = await f.service.buildDetail('food', now: _now);
      expect(detail!.progress.spentMinor, 10000);
      expect(detail.transactions.map((tx) => tx.id), ['f1']);
      expect(detail.excluded.map((tx) => tx.id), ['f2']);
    });

    test('putting a transaction back keeps other edits', () async {
      final f = _Fixture();
      await f.save([
        _budget('food', etb: 8000, categories: ['food'], excluded: ['a', 'b']),
      ]);
      await f.service.setTransactionExcluded('food', 'a', excluded: false);
      await f.service.setTransactionExcluded('food', 'c', excluded: true);
      final stored = (await f.budgets.getBudgets()).single;
      expect(stored.excludedTransactionIds.toSet(), {'b', 'c'});
      expect(stored.limitMinor, 800000);
    });

    test('institution-scoped budgets only see their accounts', () async {
      final f = _Fixture();
      await f.accounts();
      await f.save([
        _budget('wallet', etb: 1000, institutions: ['telebirr']),
      ]);
      await f.add([
        _tx('w', etb: 50, at: DateTime(2026, 10, 3), accountId: 'telebirr-main'),
        _tx('b', etb: 70, at: DateTime(2026, 10, 3)),
      ]);
      final overview = await f.service.buildOverview(now: _now);
      expect(overview.items.single.spentMinor, 5000);
    });

    test('a payday budget only counts its own dates', () async {
      final f = _Fixture();
      await f.save([_budget('pay', etb: 5000, startDay: 25)]);
      await f.add([
        _tx('old', etb: 100, at: DateTime(2026, 9, 24)),
        _tx('new', etb: 200, at: DateTime(2026, 9, 25)),
        _tx('now', etb: 300, at: DateTime(2026, 10, 10)),
      ]);
      final item = (await f.service.buildOverview(now: _now)).items.single;
      expect(item.period.start, DateTime(2026, 9, 25));
      expect(item.spentMinor, 50000);
    });

    test('last month shows how it ended', () async {
      final f = _Fixture();
      await f.save([_budget('food', etb: 1000, categories: ['food'])]);
      await f.add([
        _tx('sep', etb: 600, at: DateTime(2026, 9, 12)),
        _tx('oct', etb: 50, at: DateTime(2026, 10, 2)),
      ]);

      final current = await f.service.buildOverview(now: _now);
      expect(current.canGoBack, isTrue);
      final last = await f.service.buildOverview(monthOffset: -1, now: _now);
      expect(last.month, DateTime(2026, 9, 1));
      expect(last.canGoBack, isFalse);
      final item = last.items.single;
      expect(item.spentMinor, 60000);
      expect(item.pace, BudgetPace.finished);
      expect(item.isCurrent, isFalse);
    });

    test('one-off budgets show while upcoming and in the months they touch',
        () async {
      final f = _Fixture();
      await f.save([
        _budget(
          'trip',
          etb: 5000,
          kind: BudgetPeriodKind.custom,
          customStart: DateTime(2026, 12, 20),
          customEnd: DateTime(2027, 1, 5),
        ),
        _budget(
          'september',
          etb: 5000,
          kind: BudgetPeriodKind.custom,
          customStart: DateTime(2026, 9, 1),
          customEnd: DateTime(2026, 9, 10),
        ),
      ]);
      await f.add([_tx('x', etb: 1, at: DateTime(2026, 8, 1))]);

      final current = await f.service.buildOverview(now: _now);
      expect(current.items.map((i) => i.budget.id), ['trip']);
      expect(current.items.single.pace, BudgetPace.upcoming);
      // One-offs don't join the monthly plan.
      expect(current.plan, isNull);

      final september =
          await f.service.buildOverview(monthOffset: -1, now: _now);
      expect(september.items.map((i) => i.budget.id), ['september']);
    });
  });

  group('suggestions', () {
    Future<_Fixture> history() async {
      final f = _Fixture();
      // July, August, September: food 3,000-3,400, rent 9,000, a little
      // airtime under the ETB 300 bar.
      for (final (month, food) in [(7, 3000), (8, 3200), (9, 3400)]) {
        await f.add([
          _tx('food-$month', etb: food, at: DateTime(2026, month, 3)),
          _tx('rent-$month',
              etb: 9000, at: DateTime(2026, month, 2), categoryId: 'rent'),
          _tx('air-$month',
              etb: 100, at: DateTime(2026, month, 9), categoryId: 'airtime'),
        ]);
      }
      return f;
    }

    test('proposes budgets from full months of history', () async {
      final f = await history();
      final suggestions = await f.service.suggestBudgets(now: _now);
      expect(suggestions.map((s) => s.name),
          ['Monthly spending', 'Rent & Housing', 'Food & Drink']);
      final food = suggestions.last;
      expect(food.monthlyAverageMinor, 320000);
      expect(food.limitMinor, 320000);
      expect(suggestions.first.monthlyAverageMinor, 1230000);
      expect(suggestions.first.limitMinor, 1250000);
    });

    test('skips what existing budgets already cover', () async {
      final f = await history();
      await f.save([
        _budget('all', etb: 15000),
        _budget('rent', etb: 9000, categories: ['rent']),
      ]);
      final suggestions = await f.service.suggestBudgets(now: _now);
      expect(suggestions.map((s) => s.categoryIds), [
        ['food'],
      ]);
    });

    test('says nothing without a full month of history', () async {
      final f = _Fixture();
      await f.add([_tx('f', etb: 3000, at: DateTime(2026, 10, 2))]);
      expect(await f.service.suggestBudgets(now: _now), isEmpty);
      expect(
        await f.service.typicalMonthlySpendMinor(
          categoryIds: const ['food'],
          institutionCodes: const [],
          now: _now,
        ),
        isNull,
      );
    });

    test('a half month of history does not count', () async {
      final f = _Fixture();
      await f.add([
        _tx('half', etb: 100, at: DateTime(2026, 8, 20)),
        _tx('full', etb: 3000, at: DateTime(2026, 9, 10)),
      ]);
      expect(
        await f.service.typicalMonthlySpendMinor(
          categoryIds: const ['food'],
          institutionCodes: const [],
          now: _now,
        ),
        300000,
      );
    });

    test('limits round up to friendly numbers', () {
      expect(friendlyBudgetLimit(43210), 45000); // ETB 432.10 -> 450
      expect(friendlyBudgetLimit(637000), 640000); // 6,370 -> 6,400
      expect(friendlyBudgetLimit(2412300), 2450000); // 24,123 -> 24,500
      expect(friendlyBudgetLimit(500000), 500000);
    });
  });

  group('warnings', () {
    Future<_Fixture> spent(int etb) async {
      final f = _Fixture();
      await f.save([
        _budget('food', etb: 1000, categories: ['food'], name: 'Food'),
      ]);
      await f.add([_tx('earlier', etb: etb, at: DateTime(2026, 10, 2))]);
      return f;
    }

    test('crossing 80% warns on the transaction that did it', () async {
      final f = await spent(700);
      final tx = _tx('new', etb: 150, at: DateTime(2026, 10, 15, 9));
      await f.add([tx]);
      final warnings = await f.service.warningsFor([tx], now: _now);
      expect(warnings.single.transactionId, 'new');
      expect(warnings.single.isOver, isFalse);
      expect(warnings.single.message,
          'Food budget is 85% used, 17 days left');
    });

    test('already past 80% stays quiet until the limit', () async {
      final f = await spent(850);
      final tx = _tx('new', etb: 100, at: DateTime(2026, 10, 15, 9));
      await f.add([tx]);
      expect(await f.service.warningsFor([tx], now: _now), isEmpty);
    });

    test('crossing the limit says so', () async {
      final f = await spent(950);
      final tx = _tx('new', etb: 100, at: DateTime(2026, 10, 15, 9));
      await f.add([tx]);
      final warning = (await f.service.warningsFor([tx], now: _now)).single;
      expect(warning.isOver, isTrue);
      expect(warning.message, 'Food budget is now over its limit');
    });

    test('spending outside the budget never warns', () async {
      final f = await spent(790);
      final tx = _tx('rent',
          etb: 5000, at: DateTime(2026, 10, 15, 9), categoryId: 'rent');
      await f.add([tx]);
      expect(await f.service.warningsFor([tx], now: _now), isEmpty);
    });

    test('the alert and its notification carry the warning', () async {
      final f = await spent(790);
      final tx = _tx('new', etb: 100, at: DateTime.now());
      // warningsFor uses the real clock here; keep the budget current.
      await f.ledger.deleteTransaction('earlier');
      await f.add([_tx('earlier', etb: 790, at: DateTime.now()), tx]);
      final alerts = MoneyAlertService(
        InMemoryMoneyAlertRepository(),
        budgets: f.service,
      );
      final alert = await alerts.recordTransaction(tx);
      expect(alert.budgetNote, startsWith('Food budget is 89% used'));

      final ingestion = SmsIngestionService(
        parser: SmsParserEngine(const [GenericAmountParserTemplate()]),
        ledgerRepository: f.ledger,
        smsMessageRepository: InMemorySmsMessageRepository(),
        accountResolver: AccountResolver(f.ledger),
        categoryRuleRepository: InMemoryCategoryRuleRepository(),
      );
      final notification = BackgroundSmsHandler(
        ingestion: ingestion,
        alerts: alerts,
        strings: enStrings,
        amountsHidden: true,
      ).notificationFor(alert);
      expect(notification.text, contains('\nFood budget is 89% used'));
      expect(notification.publicText, isNot(contains('budget')));
    });
  });
}
