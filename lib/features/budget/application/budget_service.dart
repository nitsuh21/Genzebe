import 'dart:math' as math;

import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/features/budget/domain/models/budget.dart';
import 'package:genzeb/features/budget/domain/repositories/budget_repository.dart';
import 'package:genzeb/features/reports/application/report_service.dart';
import 'package:genzeb/features/transactions/domain/models/categories.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:genzeb/features/transactions/domain/repositories/ledger_repository.dart';

/// Categories Genzeb proposes budgets for. Transfers, cash withdrawals,
/// fees and "Other" are too mixed to plan as one line.
const kSuggestedBudgetCategoryIds = [
  'groceries',
  'food',
  'transport',
  'rent',
  'bills',
  'shopping',
  'airtime',
  'health',
  'education',
  'entertainment',
];

/// Budgets warn once spending passes this share of the limit.
const kBudgetWarningRatio = 0.8;

class BudgetService {
  BudgetService({
    required BudgetRepository budgetRepository,
    required LedgerRepository ledgerRepository,
  })  : _budgetRepository = budgetRepository,
        _ledgerRepository = ledgerRepository;

  final BudgetRepository _budgetRepository;
  final LedgerRepository _ledgerRepository;

  /// Smallest monthly average worth proposing a budget for (ETB 300).
  static const _minSuggestionMinor = 30000;

  Future<List<Budget>> getBudgets() => _budgetRepository.getBudgets();

  Future<void> saveBudget(Budget budget) =>
      _budgetRepository.upsertBudget(budget);

  Future<void> deleteBudget(String id) => _budgetRepository.deleteBudget(id);

  /// Leaves one transaction out of one budget (or puts it back). Reads the
  /// stored budget first so edits made meanwhile aren't overwritten.
  Future<void> setTransactionExcluded(
    String budgetId,
    String transactionId, {
    required bool excluded,
  }) async {
    final budgets = await _budgetRepository.getBudgets();
    final budget = budgets.where((b) => b.id == budgetId).firstOrNull;
    if (budget == null) return;
    final ids = budget.excludedTransactionIds.toSet();
    final changed = excluded ? ids.add(transactionId) : ids.remove(transactionId);
    if (!changed) return;
    await _budgetRepository.upsertBudget(
      budget.copyWith(excludedTransactionIds: ids.toList(growable: false)),
    );
  }

  /// Every budget against actual spend for one calendar month:
  /// [monthOffset] 0 is this month, -1 last month, and so on. Monthly
  /// budgets show the period that month falls in; one-off budgets show
  /// when their dates touch it.
  Future<BudgetOverview> buildOverview({
    int monthOffset = 0,
    Set<String> institutionCodes = const <String>{},
    DateTime? now,
  }) async {
    final clock = now ?? DateTime.now();
    final anchor = _shiftMonths(clock, monthOffset);
    final month = firstOfMonth(anchor);
    final nextMonth = DateTime(month.year, month.month + 1, 1);
    final budgets = await _budgetRepository.getBudgets();
    final ledger = await _loadLedger(institutionCodes: institutionCodes);

    final items = <BudgetProgress>[];
    for (final budget in budgets) {
      final period = budget.periodContaining(anchor);
      if (!budget.isMonthly) {
        final visible = monthOffset == 0
            // This month also lists one-offs still to come.
            ? period.end.isAfter(month)
            : period.overlaps(month, nextMonth);
        if (!visible) continue;
      }
      items.add(_progress(budget, period, ledger, clock));
    }
    items.sort((a, b) {
      final aUpcoming = a.pace == BudgetPace.upcoming;
      final bUpcoming = b.pace == BudgetPace.upcoming;
      if (aUpcoming != bUpcoming) return aUpcoming ? 1 : -1;
      return b.ratio.compareTo(a.ratio);
    });

    final plan = _planSummary(
      items.where((item) => item.budget.isMonthly).toList(growable: false),
      ledger,
      clock,
    );

    // Spending in this month that no budget on screen watches.
    final windowStart = plan?.period?.start ?? month;
    final windowEnd = plan?.period?.end ?? nextMonth;
    final unbudgeted = <String, int>{};
    for (final tx in ledger.spending) {
      if (tx.occurredAt.isBefore(windowStart) ||
          !tx.occurredAt.isBefore(windowEnd)) {
        continue;
      }
      final counted = items.any(
        (item) => _counts(item.budget, item.period, tx, ledger),
      );
      if (counted) continue;
      unbudgeted.update(
        tx.categoryId,
        (value) => value + tx.amount.minorUnits,
        ifAbsent: () => tx.amount.minorUnits,
      );
    }
    final unbudgetedByCategory = unbudgeted.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));

    final earliest = ledger.earliest;
    return BudgetOverview(
      items: items,
      monthOffset: monthOffset,
      month: month,
      canGoBack: earliest != null && earliest.isBefore(month),
      hasAnyBudgets: budgets.isNotEmpty,
      plan: plan,
      unbudgetedSpendMinor:
          unbudgeted.values.fold<int>(0, (sum, value) => sum + value),
      unbudgetedByCategory: unbudgetedByCategory,
    );
  }

  /// One budget's period in full, for its own page. Null when the budget
  /// has been deleted.
  Future<BudgetDetail?> buildDetail(
    String budgetId, {
    int monthOffset = 0,
    DateTime? now,
  }) async {
    final clock = now ?? DateTime.now();
    final budgets = await _budgetRepository.getBudgets();
    final budget = budgets.where((b) => b.id == budgetId).firstOrNull;
    if (budget == null) return null;
    final period = budget.periodContaining(_shiftMonths(clock, monthOffset));
    final ledger = await _loadLedger();
    final excludedIds = budget.excludedTransactionIds.toSet();

    final counted = <TransactionRecord>[];
    final excluded = <TransactionRecord>[];
    for (final tx in ledger.spending) {
      if (!period.contains(tx.occurredAt)) continue;
      if (!budget.covers(tx, institutionCode: ledger.institutionOf(tx))) {
        continue;
      }
      (excludedIds.contains(tx.id) ? excluded : counted).add(tx);
    }
    counted.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    excluded.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    final byCategory = <String, int>{};
    for (final tx in counted) {
      byCategory.update(
        tx.categoryId,
        (value) => value + tx.amount.minorUnits,
        ifAbsent: () => tx.amount.minorUnits,
      );
    }
    return BudgetDetail(
      progress: BudgetProgress(
        budget: budget,
        period: period,
        spentMinor: byCategory.values.fold<int>(0, (sum, v) => sum + v),
        transactionCount: counted.length,
        now: clock,
      ),
      transactions: counted,
      excluded: excluded,
      spendByCategory: byCategory.entries.toList(growable: false)
        ..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  /// Budgets proposed from the last few full months of spending, skipping
  /// what existing monthly budgets already cover. Empty until there is at
  /// least one full month of history.
  Future<List<BudgetSuggestion>> suggestBudgets({DateTime? now}) async {
    final clock = now ?? DateTime.now();
    final ledger = await _loadLedger();
    final window = _historyWindow(ledger.earliest, clock);
    if (window == null) return const [];

    final monthly =
        (await _budgetRepository.getBudgets()).where((b) => b.isMonthly);
    final hasEverythingBudget =
        monthly.any((b) => b.isGeneral && b.isAllInstitutions);
    final budgetedCategories = <String>{
      for (final budget in monthly) ...budget.categoryIds,
    };

    var total = 0;
    final byCategory = <String, int>{};
    for (final tx in ledger.spending) {
      if (tx.occurredAt.isBefore(window.start) ||
          !tx.occurredAt.isBefore(window.end)) {
        continue;
      }
      total += tx.amount.minorUnits;
      byCategory.update(
        tx.categoryId,
        (value) => value + tx.amount.minorUnits,
        ifAbsent: () => tx.amount.minorUnits,
      );
    }

    final suggestions = <BudgetSuggestion>[];
    final totalAverage = total ~/ window.months;
    if (!hasEverythingBudget && totalAverage >= _minSuggestionMinor) {
      suggestions.add(BudgetSuggestion(
        name: 'Monthly spending',
        categoryIds: const [],
        monthlyAverageMinor: totalAverage,
        limitMinor: friendlyBudgetLimit(totalAverage),
      ));
    }
    final categories = [
      for (final id in kSuggestedBudgetCategoryIds)
        if (!budgetedCategories.contains(id) &&
            (byCategory[id] ?? 0) ~/ window.months >= _minSuggestionMinor)
          MapEntry(id, byCategory[id]! ~/ window.months),
    ]..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in categories.take(4)) {
      suggestions.add(BudgetSuggestion(
        name: categoryInfoFor(entry.key).label,
        categoryIds: [entry.key],
        monthlyAverageMinor: entry.value,
        limitMinor: friendlyBudgetLimit(entry.value),
      ));
    }
    return suggestions;
  }

  /// What the user usually spends per month in this scope, from the last
  /// few full months. Null without a full month of history.
  Future<int?> typicalMonthlySpendMinor({
    required List<String> categoryIds,
    required List<String> institutionCodes,
    DateTime? now,
  }) async {
    final clock = now ?? DateTime.now();
    final ledger = await _loadLedger();
    final window = _historyWindow(ledger.earliest, clock);
    if (window == null) return null;
    final scope = Budget(
      id: '',
      name: '',
      categoryIds: categoryIds,
      institutionCodes: institutionCodes,
      limitMinor: 0,
      createdAt: clock,
    );
    var total = 0;
    for (final tx in ledger.spending) {
      if (tx.occurredAt.isBefore(window.start) ||
          !tx.occurredAt.isBefore(window.end)) {
        continue;
      }
      if (scope.covers(tx, institutionCode: ledger.institutionOf(tx))) {
        total += tx.amount.minorUnits;
      }
    }
    return total ~/ window.months;
  }

  /// Budgets that [newTransactions] just pushed past 80% of the limit, or
  /// past the limit itself. A budget warns once per line it crosses.
  Future<List<BudgetWarning>> warningsFor(
    List<TransactionRecord> newTransactions, {
    DateTime? now,
  }) async {
    if (newTransactions.isEmpty) return const [];
    final budgets = await _budgetRepository.getBudgets();
    if (budgets.isEmpty) return const [];
    final clock = now ?? DateTime.now();
    final ledger = await _loadLedger();
    final newIds = {for (final tx in newTransactions) tx.id};

    final warnings = <BudgetWarning>[];
    for (final budget in budgets) {
      final limit = budget.limitMinor;
      if (limit <= 0) continue;
      final period = budget.periodContaining(clock);
      if (!period.contains(clock)) continue;
      final counted = ledger.spending
          .where((tx) => _counts(budget, period, tx, ledger))
          .toList(growable: false)
        ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      final fresh = counted.where((tx) => newIds.contains(tx.id)).toList();
      if (fresh.isEmpty) continue;

      final spent = counted.fold<int>(0, (sum, tx) => sum + tx.amount.minorUnits);
      final before =
          spent - fresh.fold<int>(0, (sum, tx) => sum + tx.amount.minorUnits);
      final warnLine = (limit * kBudgetWarningRatio).ceil();
      final crossedLimit = before <= limit && spent > limit;
      final crossedWarning = before < warnLine && spent >= warnLine;
      if (!crossedLimit && !crossedWarning) continue;
      warnings.add(BudgetWarning(
        transactionId: fresh.last.id,
        progress: BudgetProgress(
          budget: budget,
          period: period,
          spentMinor: spent,
          transactionCount: counted.length,
          now: clock,
        ),
      ));
    }
    return warnings;
  }

  BudgetProgress _progress(
    Budget budget,
    BudgetPeriod period,
    _LedgerView ledger,
    DateTime now,
  ) {
    var spent = 0;
    var count = 0;
    for (final tx in ledger.spending) {
      if (!_counts(budget, period, tx, ledger)) continue;
      spent += tx.amount.minorUnits;
      count += 1;
    }
    return BudgetProgress(
      budget: budget,
      period: period,
      spentMinor: spent,
      transactionCount: count,
      now: now,
    );
  }

  /// Totals for the monthly budgets, counting each birr once. Budgets that
  /// sit inside a broader one (Food inside "Everything") add no limit of
  /// their own — the broader budget already plans for that money.
  BudgetPlanSummary? _planSummary(
    List<BudgetProgress> monthly,
    _LedgerView ledger,
    DateTime now,
  ) {
    if (monthly.isEmpty) return null;
    final topLevel = <BudgetProgress>[];
    for (var i = 0; i < monthly.length; i++) {
      final budget = monthly[i].budget;
      var nested = false;
      for (var j = 0; j < monthly.length && !nested; j++) {
        if (i == j) continue;
        final other = monthly[j].budget;
        // Two budgets with the same scope: the first one is the parent.
        nested = other.contains(budget) && (!budget.contains(other) || j < i);
      }
      if (!nested) topLevel.add(monthly[i]);
    }

    final countedIds = <String>{};
    var spent = 0;
    for (final tx in ledger.spending) {
      final counts =
          topLevel.any((item) => _counts(item.budget, item.period, tx, ledger));
      if (counts && countedIds.add(tx.id)) spent += tx.amount.minorUnits;
    }
    final periods = topLevel.map((item) => item.period).toSet();
    return BudgetPlanSummary(
      limitMinor:
          topLevel.fold<int>(0, (sum, item) => sum + item.budget.limitMinor),
      spentMinor: spent,
      now: now,
      budgetCount: topLevel.length,
      period: periods.length == 1 ? periods.first : null,
    );
  }

  bool _counts(
    Budget budget,
    BudgetPeriod period,
    TransactionRecord tx,
    _LedgerView ledger,
  ) {
    return period.contains(tx.occurredAt) &&
        !budget.excludedTransactionIds.contains(tx.id) &&
        budget.covers(tx, institutionCode: ledger.institutionOf(tx));
  }

  /// The spending budgets measure: money out, minus moves between the
  /// user's own accounts and unconfirmed parses — the same rules as
  /// Reports and the ledger total.
  Future<_LedgerView> _loadLedger({
    Set<String> institutionCodes = const <String>{},
  }) async {
    final all = await _ledgerRepository.getTransactions();
    // Own-transfer pairs are found on the whole ledger: an institution
    // filter would hide one leg of the pair.
    final internalIds = ReportService.analyzeFlows(all).internalIds;
    final accounts = await _ledgerRepository.getAccounts();
    final institutionByAccount = <String, String>{
      for (final account in accounts)
        account.id: account.institutionCode?.trim().toLowerCase() ?? '',
    };
    DateTime? earliest;
    final spending = <TransactionRecord>[];
    for (final tx in all) {
      if (earliest == null || tx.occurredAt.isBefore(earliest)) {
        earliest = tx.occurredAt;
      }
      if (!isOutflowType(tx.type)) continue;
      if (internalIds.contains(tx.id)) continue;
      if (tx.reviewStatus == TransactionReviewStatus.pendingReview) continue;
      if (institutionCodes.isNotEmpty &&
          !institutionCodes.contains(institutionByAccount[tx.accountId])) {
        continue;
      }
      spending.add(tx);
    }
    return _LedgerView(
      spending: spending,
      institutionByAccount: institutionByAccount,
      earliest: earliest,
    );
  }
}

class _LedgerView {
  const _LedgerView({
    required this.spending,
    required this.institutionByAccount,
    required this.earliest,
  });

  final List<TransactionRecord> spending;
  final Map<String, String> institutionByAccount;

  /// Oldest transaction of any kind: where the user's history begins.
  final DateTime? earliest;

  String institutionOf(TransactionRecord tx) =>
      institutionByAccount[tx.accountId] ?? '';
}

/// Up to three full calendar months before [now]'s month. The month
/// history starts in only counts when it starts near the 1st — half a
/// month would drag the average down.
({DateTime start, DateTime end, int months})? _historyWindow(
  DateTime? earliest,
  DateTime now, {
  int maxMonths = 3,
}) {
  if (earliest == null) return null;
  final end = firstOfMonth(now);
  final firstFull = earliest.day <= 5
      ? firstOfMonth(earliest)
      : DateTime(earliest.year, earliest.month + 1, 1);
  var start = DateTime(end.year, end.month - maxMonths, 1);
  if (start.isBefore(firstFull)) start = firstFull;
  final months = (end.year - start.year) * 12 + end.month - start.month;
  if (months <= 0) return null;
  return (start: start, end: end, months: months);
}

/// [date] moved by whole months, keeping the day where the month allows.
DateTime _shiftMonths(DateTime date, int months) {
  if (months == 0) return date;
  final target = DateTime(date.year, date.month + months, 1);
  final lastDay = DateTime(target.year, target.month + 1, 0).day;
  return DateTime(
    target.year,
    target.month,
    math.min(date.day, lastDay),
    date.hour,
    date.minute,
  );
}

/// A monthly average rounded up to a number people would actually pick:
/// ETB 50 steps under 1,000, 100 under 10,000, 500 above.
int friendlyBudgetLimit(int minor) {
  final step = minor < 100000
      ? 5000
      : minor < 1000000
          ? 10000
          : 50000;
  return ((minor + step - 1) ~/ step) * step;
}
