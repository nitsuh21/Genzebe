import 'package:flutter/material.dart';
import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/features/budget/domain/models/budget.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart';
import 'package:genzeb/features/transactions/domain/models/categories.dart';
import 'package:intl/intl.dart';

const kBudgetWarningColor = Color(0xFFE8833A);

final _shortDay = DateFormat('MMM d');
final _shortDayYear = DateFormat('MMM d, yyyy');

/// "Oct 1 – 31", "Sep 25 – Oct 24", "Dec 20, 2026 – Jan 5, 2027".
String budgetPeriodLabel(BudgetPeriod period) {
  final first = period.start;
  final last = period.lastDay;
  if (first.year != last.year) {
    return '${_shortDayYear.format(first)} – ${_shortDayYear.format(last)}';
  }
  if (first.month == last.month) {
    return '${_shortDay.format(first)} – ${last.day}';
  }
  return '${_shortDay.format(first)} – ${_shortDay.format(last)}';
}

String budgetDateLabel(DateTime date) => _shortDay.format(date);

String daysLabel(int days) => days == 1 ? '1 day' : '$days days';

/// "Food, Groceries" / "All spending", plus the banks when it's limited
/// to some: "Food · CBE, telebirr".
String budgetScopeLabel(Budget budget) {
  final categories = budget.isGeneral
      ? 'All spending'
      : budget.categoryIds.map((id) => categoryInfoFor(id).label).join(', ');
  if (budget.isAllInstitutions) return categories;
  final institutions = budget.institutionCodes
      .map((code) => institutionInfoForCode(code).shortName)
      .join(', ');
  return '$categories · $institutions';
}

IconData budgetIcon(Budget budget) => budget.isGeneral
    ? Icons.savings_rounded
    : categoryInfoFor(budget.categoryIds.first).icon;

Color budgetAccent(Budget budget, ThemeData theme) => budget.isGeneral
    ? theme.colorScheme.primary
    : categoryInfoFor(budget.categoryIds.first).color;

Color budgetPaceColor(BudgetPace? pace, ThemeData theme, Color accent) {
  switch (pace) {
    case BudgetPace.over:
      return theme.colorScheme.error;
    case BudgetPace.ahead:
      return kBudgetWarningColor;
    case BudgetPace.upcoming:
      return theme.colorScheme.outline;
    case BudgetPace.onTrack:
    case BudgetPace.finished:
    case null:
      return accent;
  }
}

/// One line on how a budget is doing, in plain words:
/// "ETB 3,800 left · about ETB 190 a day for 20 days".
String budgetStatusText({
  required BudgetPace? pace,
  required int remainingMinor,
  required bool showAmounts,
  required bool isCurrent,
  int? perDayMinor,
  int? daysLeft,
  DateTime? start,
}) {
  String money(int minor) => showAmounts ? formatMinorEtb(minor) : 'ETB ••••';
  final toGo = daysLeft == null ? null : '${daysLabel(daysLeft)} to go';
  final forDays = daysLeft == null ? null : 'for ${daysLabel(daysLeft)}';
  switch (pace) {
    case BudgetPace.upcoming:
      return start == null ? 'Not started yet' : 'Starts ${budgetDateLabel(start)}';
    case BudgetPace.over:
      final over = 'Over by ${money(-remainingMinor)}';
      return isCurrent && toGo != null ? '$over · $toGo' : over;
    case BudgetPace.finished:
      return 'Stayed within budget · ${money(remainingMinor)} to spare';
    case BudgetPace.ahead:
      final left = '${money(remainingMinor)} left';
      return forDays == null
          ? '$left · spending faster than planned'
          : '$left $forDays · spending faster than planned';
    case BudgetPace.onTrack:
    case null:
      final left = '${money(remainingMinor)} left';
      if (perDayMinor != null && daysLeft != null) {
        return '$left · about ${money(perDayMinor)} a day for '
            '${daysLabel(daysLeft)}';
      }
      return left;
  }
}

String budgetProgressStatus(BudgetProgress progress, {required bool showAmounts}) {
  return budgetStatusText(
    pace: progress.pace,
    remainingMinor: progress.remainingMinor,
    showAmounts: showAmounts,
    isCurrent: progress.isCurrent,
    perDayMinor: progress.perDayLeftMinor,
    daysLeft: progress.isCurrent ? progress.daysLeft : null,
    start: progress.period.start,
  );
}

/// Progress bar with an optional "today" tick: when spending is left of
/// the tick, the budget is running behind the calendar (good).
class BudgetProgressBar extends StatelessWidget {
  const BudgetProgressBar({
    super.key,
    required this.ratio,
    required this.color,
    this.todayFraction,
    this.height = 8,
  });

  final double ratio;
  final Color color;

  /// Share of the period gone by; null hides the tick.
  final double? todayFraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = todayFraction;
    return SizedBox(
      height: height + 6,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(height),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0).toDouble(),
                  minHeight: height,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              if (today != null && today > 0 && today < 1)
                Positioned(
                  left: (width * today - 1).clamp(0.0, width - 2),
                  top: 0,
                  bottom: 0,
                  child: Tooltip(
                    message: 'Today',
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
