import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';

/// How a budget's dates work.
enum BudgetPeriodKind {
  /// Repeats every month, starting on [Budget.startDay].
  monthly,

  /// One fixed date range (a trip, a holiday, a wedding).
  custom,
}

/// Latest start day offered: every month has a 28th, so a monthly budget
/// never has to guess what "the 31st of February" means.
const kMaxBudgetStartDay = 28;

/// A spending plan over a date range.
///
/// [categoryIds] can be empty which means a general budget that applies to
/// all spending categories.
class Budget {
  const Budget({
    required this.id,
    required this.name,
    required this.categoryIds,
    this.institutionCodes = const [],
    this.excludedTransactionIds = const [],
    required this.limitMinor,
    required this.createdAt,
    this.periodKind = BudgetPeriodKind.monthly,
    this.startDay = 1,
    this.customStart,
    this.customEnd,
  });

  final String id;
  final String name;
  final List<String> categoryIds;
  final List<String> institutionCodes;
  final List<String> excludedTransactionIds;
  final int limitMinor;
  final DateTime createdAt;
  final BudgetPeriodKind periodKind;

  /// Monthly budgets: the day of the month each period starts (1–28), e.g.
  /// payday for someone who plans salary to salary.
  final int startDay;

  /// Custom budgets: first and last day, both inclusive.
  final DateTime? customStart;
  final DateTime? customEnd;

  bool get isGeneral => categoryIds.isEmpty;
  bool get isAllInstitutions => institutionCodes.isEmpty;
  bool get isMonthly => periodKind == BudgetPeriodKind.monthly;

  /// The period [date] falls in. Custom budgets have exactly one period.
  BudgetPeriod periodContaining(DateTime date) {
    if (!isMonthly) {
      final start = _dateOnly(customStart ?? createdAt);
      final last = _dateOnly(customEnd ?? start);
      return BudgetPeriod(
        start: start,
        end: DateTime(last.year, last.month, last.day + 1),
      );
    }
    final day = startDay.clamp(1, kMaxBudgetStartDay);
    final start = date.day >= day
        ? DateTime(date.year, date.month, day)
        : DateTime(date.year, date.month - 1, day);
    return BudgetPeriod(
      start: start,
      end: DateTime(start.year, start.month + 1, day),
    );
  }

  /// Whether [tx] is the kind of spending this budget watches — its
  /// categories and institutions. Ignores dates and exclusions.
  bool covers(TransactionRecord tx, {required String institutionCode}) {
    if (!isAllInstitutions && !institutionCodes.contains(institutionCode)) {
      return false;
    }
    return isGeneral || categoryIds.contains(tx.categoryId);
  }

  /// Whether this budget's scope includes everything [other] watches, so
  /// [other]'s spending is already part of this one.
  bool contains(Budget other) {
    final categoriesCovered =
        isGeneral || (!other.isGeneral && categoryIds.toSet().containsAll(other.categoryIds));
    final institutionsCovered = isAllInstitutions ||
        (!other.isAllInstitutions &&
            institutionCodes.toSet().containsAll(other.institutionCodes));
    return categoriesCovered && institutionsCovered;
  }

  Budget copyWith({
    String? name,
    List<String>? categoryIds,
    List<String>? institutionCodes,
    List<String>? excludedTransactionIds,
    int? limitMinor,
    BudgetPeriodKind? periodKind,
    int? startDay,
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    return Budget(
      id: id,
      name: name ?? this.name,
      categoryIds: categoryIds ?? this.categoryIds,
      institutionCodes: institutionCodes ?? this.institutionCodes,
      excludedTransactionIds:
          excludedTransactionIds ?? this.excludedTransactionIds,
      limitMinor: limitMinor ?? this.limitMinor,
      createdAt: createdAt,
      periodKind: periodKind ?? this.periodKind,
      startDay: startDay ?? this.startDay,
      customStart: customStart ?? this.customStart,
      customEnd: customEnd ?? this.customEnd,
    );
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// Whole days from [from] to [to], safe across daylight-saving changes.
int _daysBetween(DateTime from, DateTime to) =>
    (to.difference(from).inHours / 24).round();

/// `[start, end)` — [end] is midnight after the last day.
class BudgetPeriod {
  const BudgetPeriod({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  /// The last day, for display ("Oct 1 – Oct 31").
  DateTime get lastDay => DateTime(end.year, end.month, end.day - 1);

  int get totalDays => _daysBetween(start, end);

  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);

  bool overlaps(DateTime from, DateTime to) =>
      start.isBefore(to) && end.isAfter(from);

  /// Days still to come, counting today.
  int daysLeft(DateTime now) {
    if (!contains(now)) return now.isBefore(start) ? totalDays : 0;
    return _daysBetween(_dateOnly(now), end);
  }

  /// Share of the period already behind us at [now] (today counts as
  /// half-spent), 0 before it starts and 1 after it ends.
  double elapsedFraction(DateTime now) {
    if (now.isBefore(start)) return 0;
    if (!now.isBefore(end)) return 1;
    final total = end.difference(start).inMinutes;
    if (total <= 0) return 1;
    return now.difference(start).inMinutes / total;
  }

  @override
  bool operator ==(Object other) =>
      other is BudgetPeriod && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Where a budget stands against the calendar.
enum BudgetPace {
  /// A custom budget whose dates haven't started yet.
  upcoming,

  /// Spending is in line with how much of the period has passed.
  onTrack,

  /// Spending is running well ahead of the calendar.
  ahead,

  /// Already past the limit.
  over,

  /// The period ended within the limit.
  finished,
}

/// A budget paired with its actual spend for one period.
class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.period,
    required this.spentMinor,
    required this.now,
    this.transactionCount = 0,
  });

  final Budget budget;
  final BudgetPeriod period;
  final int spentMinor;
  final int transactionCount;

  /// The moment the numbers were computed, for pace and days left.
  final DateTime now;

  int get remainingMinor => budget.limitMinor - spentMinor;

  double get ratio {
    if (budget.limitMinor <= 0) return 0;
    return spentMinor / budget.limitMinor;
  }

  bool get isOverBudget => spentMinor > budget.limitMinor;

  bool get isCurrent => period.contains(now);

  int get daysLeft => period.daysLeft(now);

  double get elapsedFraction => period.elapsedFraction(now);

  /// What could still be spent each remaining day (today included).
  int? get perDayLeftMinor {
    if (!isCurrent || remainingMinor <= 0 || daysLeft <= 0) return null;
    return remainingMinor ~/ daysLeft;
  }

  BudgetPace get pace => paceFor(
        ratio: ratio,
        elapsed: elapsedFraction,
        period: period,
        now: now,
      );
}

/// Shared by single budgets and the overall plan.
BudgetPace paceFor({
  required double ratio,
  required double elapsed,
  required BudgetPeriod period,
  required DateTime now,
}) {
  if (ratio > 1) return BudgetPace.over;
  if (now.isBefore(period.start)) return BudgetPace.upcoming;
  if (!now.isBefore(period.end)) return BudgetPace.finished;
  // Ten points of slack: one bigger purchase early in the month shouldn't
  // turn the bar orange.
  return ratio - elapsed > 0.10 ? BudgetPace.ahead : BudgetPace.onTrack;
}

/// The monthly budgets taken together, each birr counted once even when
/// budgets overlap (a general budget plus a Food budget inside it).
class BudgetPlanSummary {
  const BudgetPlanSummary({
    required this.limitMinor,
    required this.spentMinor,
    required this.now,
    this.budgetCount = 1,
    this.period,
  });

  final int limitMinor;
  final int spentMinor;
  final DateTime now;

  /// Budgets that aren't inside another one. With just one, the plan is
  /// that budget and says nothing new.
  final int budgetCount;

  /// Set when every monthly budget shares the same dates; null when they
  /// start on different days (no single "days left" exists then).
  final BudgetPeriod? period;

  int get remainingMinor => limitMinor - spentMinor;

  double get ratio {
    if (limitMinor <= 0) return 0;
    return spentMinor / limitMinor;
  }

  bool get isOver => spentMinor > limitMinor;

  int? get daysLeft => period?.daysLeft(now);

  int? get perDayLeftMinor {
    final p = period;
    if (p == null || !p.contains(now) || remainingMinor <= 0) return null;
    final days = p.daysLeft(now);
    return days <= 0 ? null : remainingMinor ~/ days;
  }

  BudgetPace? get pace {
    final p = period;
    if (p == null) return isOver ? BudgetPace.over : null;
    return paceFor(
      ratio: ratio,
      elapsed: p.elapsedFraction(now),
      period: p,
      now: now,
    );
  }
}

/// All budgets for one month of the Budget screen.
class BudgetOverview {
  const BudgetOverview({
    required this.items,
    required this.monthOffset,
    required this.month,
    required this.canGoBack,
    required this.hasAnyBudgets,
    required this.unbudgetedSpendMinor,
    this.unbudgetedByCategory = const [],
    this.plan,
  });

  final List<BudgetProgress> items;

  /// 0 = this month, -1 = last month, ...
  final int monthOffset;

  /// First day of the calendar month being shown.
  final DateTime month;

  /// Whether older months hold any transactions to look back on.
  final bool canGoBack;

  /// Budgets exist at all — false means a brand-new user.
  final bool hasAnyBudgets;

  /// Null when no monthly budget applies to this month.
  final BudgetPlanSummary? plan;

  /// Spend this month that no budget watches.
  final int unbudgetedSpendMinor;

  /// [unbudgetedSpendMinor] split by category, biggest first.
  final List<MapEntry<String, int>> unbudgetedByCategory;

  bool get isCurrentMonth => monthOffset == 0;
}

/// One budget's period in full: what counted, what was left out.
class BudgetDetail {
  const BudgetDetail({
    required this.progress,
    required this.transactions,
    required this.excluded,
    required this.spendByCategory,
  });

  final BudgetProgress progress;

  /// Counted toward the budget, newest first.
  final List<TransactionRecord> transactions;

  /// In scope and in the period, but the user left them out.
  final List<TransactionRecord> excluded;

  /// Counted spend per category, biggest first.
  final List<MapEntry<String, int>> spendByCategory;
}

/// A budget Genzeb proposes from the user's own spending history.
class BudgetSuggestion {
  const BudgetSuggestion({
    required this.name,
    required this.categoryIds,
    required this.monthlyAverageMinor,
    required this.limitMinor,
  });

  final String name;

  /// Empty = everything.
  final List<String> categoryIds;
  final int monthlyAverageMinor;

  /// [monthlyAverageMinor] rounded up to a friendly number.
  final int limitMinor;
}

/// A budget that just crossed a warning line because of new spending.
class BudgetWarning {
  const BudgetWarning({
    required this.transactionId,
    required this.progress,
  });

  /// The transaction that pushed it over the line.
  final String transactionId;
  final BudgetProgress progress;

  bool get isOver => progress.isOverBudget;

  /// No amounts: this text also lands in notifications.
  String get message {
    final raw = progress.budget.name.trim();
    // Older default names already end in "budget" ("Food budget").
    final name =
        raw.toLowerCase().endsWith('budget') ? raw : '$raw budget';
    if (isOver) return '$name is now over its limit';
    final percent = (progress.ratio * 100).floor();
    final days = progress.daysLeft;
    final dayText = days == 1 ? '1 day left' : '$days days left';
    return '$name is $percent% used · $dayText';
  }
}
