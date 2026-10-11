import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/features/ai/application/ai_assistant_service.dart';
import 'package:genzeb/features/budget/application/budget_service.dart';
import 'package:genzeb/features/budget/domain/models/budget.dart';
import 'package:genzeb/features/budget/presentation/budget_widgets.dart';
import 'package:genzeb/features/transactions/domain/models/categories.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:genzeb/features/transactions/presentation/add_transaction_sheet.dart';
import 'package:genzeb/features/transactions/presentation/transaction_detail_sheet.dart';
import 'package:genzeb/features/transactions/presentation/transaction_tile.dart';

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    final monthOffset = ref.watch(budgetMonthOffsetProvider);
    final overviewAsync = ref.watch(budgetMonthOverviewProvider(monthOffset));
    // One app-wide privacy switch, shared with Home.
    final showAmounts = !ref.watch(amountsHiddenProvider);

    return Scaffold(
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: safeBottom),
        child: FloatingActionButton.extended(
          heroTag: 'budget-fab',
          onPressed: () => showBudgetEditor(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New budget'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshAppData(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 12, 16, 28 + safeBottom + 84),
          children: [
            _Header(
              monthOffset: monthOffset,
              canGoBack: overviewAsync.valueOrNull?.canGoBack ?? false,
              showAmounts: showAmounts,
            ),
            const SizedBox(height: 16),
            ...overviewAsync.when(
              skipLoadingOnReload: true,
              loading: () => const [
                Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (_, __) => const [
                _Note(
                  icon: Icons.error_outline_rounded,
                  text: 'Could not load budgets. Pull down to try again.',
                ),
              ],
              data: (overview) => _content(context, ref, overview, showAmounts),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    WidgetRef ref,
    BudgetOverview overview,
    bool showAmounts,
  ) {
    if (!overview.hasAnyBudgets) {
      return [_EmptyBudgets(showAmounts: showAmounts)];
    }
    final plan = overview.plan;
    return [
      // One budget is its own total; the summary only helps with several.
      if (plan != null && plan.budgetCount > 1) ...[
        _OverallCard(overview: overview, showAmounts: showAmounts),
        const SizedBox(height: 12),
      ],
      // AI is a Plus perk; free users must not see it.
      if (overview.isCurrentMonth && ref.watch(aiEntitledProvider)) ...[
        _AiBudgetCard(ref: ref),
        const SizedBox(height: 8),
      ],
      if (overview.items.isEmpty)
        _Note(
          icon: Icons.event_busy_rounded,
          text: 'No budgets covered ${formatMonth(overview.month)}.',
        )
      else
        ...overview.items.map(
          (item) => _BudgetCard(
            progress: item,
            showAmounts: showAmounts,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BudgetDetailPage(
                  budgetId: item.budget.id,
                  monthOffset: overview.monthOffset,
                ),
              ),
            ),
            onEdit: () => showBudgetEditor(context, existing: item.budget),
            onDelete: () => _deleteBudget(context, ref, item.budget),
          ),
        ),
      if (overview.unbudgetedSpendMinor > 0)
        _UnbudgetedCard(overview: overview, showAmounts: showAmounts),
    ];
  }

  Future<void> _deleteBudget(
    BuildContext context,
    WidgetRef ref,
    Budget budget,
  ) async {
    final service = ref.read(budgetServiceProvider);
    final dataVersion = ref.read(dataVersionProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    await service.deleteBudget(budget.id);
    dataVersion.state++;
    messenger.showSnackBar(
      SnackBar(
        // Actions make snackbars stay until dismissed; Undo is a courtesy.
        persist: false,
        content: Text('Deleted “${budget.name}”.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await service.saveBudget(budget);
            dataVersion.state++;
          },
        ),
      ),
    );
  }
}

/// "Budget", the amounts switch, and the ‹ October 2026 › switcher.
class _Header extends ConsumerWidget {
  const _Header({
    required this.monthOffset,
    required this.canGoBack,
    required this.showAmounts,
  });

  final int monthOffset;
  final bool canGoBack;
  final bool showAmounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final month = DateTime(now.year, now.month + monthOffset, 1);
    void move(int delta) =>
        ref.read(budgetMonthOffsetProvider.notifier).state += delta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Budget',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              onPressed: () =>
                  ref.read(amountsHiddenProvider.notifier).toggle(),
              icon: Icon(
                showAmounts
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
              ),
              tooltip: showAmounts ? 'Hide amounts' : 'Show amounts',
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: canGoBack ? () => move(-1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Previous month',
              ),
              Expanded(
                child: GestureDetector(
                  // Tap the month to jump back to today.
                  onTap: monthOffset == 0
                      ? null
                      : () => ref
                          .read(budgetMonthOffsetProvider.notifier)
                          .state = 0,
                  child: Column(
                    children: [
                      Text(
                        formatMonth(month),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (monthOffset != 0)
                        Text(
                          'Tap to go back to this month',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: monthOffset < 0 ? () => move(1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Next month',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.overview, required this.showAmounts});
  final BudgetOverview overview;
  final bool showAmounts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = overview.plan!;
    final period = plan.period;
    final isCurrent = period?.contains(plan.now) ?? overview.isCurrentMonth;
    final pace = plan.pace;
    final accent = theme.brightness == Brightness.dark
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
    final barColor = budgetPaceColor(pace, theme, theme.colorScheme.primary);
    final String title;
    if (period == null) {
      title = 'Monthly budgets';
    } else if (period.start.day == 1) {
      title = overview.isCurrentMonth
          ? 'Spent this month'
          : 'Spent in ${formatMonth(period.start)}';
    } else {
      title = 'Spent · ${budgetPeriodLabel(period)}';
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.analytics_outlined, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            showAmounts ? formatMinorEtb(plan.spentMinor) : 'ETB ••••••',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            showAmounts
                ? 'of ${formatMinorEtb(plan.limitMinor)} planned'
                : 'of ETB •••••• planned',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          BudgetProgressBar(
            ratio: plan.ratio,
            color: barColor,
            height: 10,
            todayFraction: isCurrent && period != null
                ? period.elapsedFraction(plan.now)
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            budgetStatusText(
              pace: pace,
              remainingMinor: plan.remainingMinor,
              showAmounts: showAmounts,
              isCurrent: isCurrent,
              perDayMinor: plan.perDayLeftMinor,
              daysLeft: isCurrent ? plan.daysLeft : null,
              start: period?.start,
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: pace == BudgetPace.over || pace == BudgetPace.ahead
                  ? barColor
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.progress,
    required this.showAmounts,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final BudgetProgress progress;
  final bool showAmounts;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final budget = progress.budget;
    final accent = budgetAccent(budget, theme);
    final pace = progress.pace;
    final barColor = budgetPaceColor(pace, theme, accent);
    // A plain calendar month needs no date line: the header names it.
    final showPeriod = !budget.isMonthly || budget.startDay != 1;
    final warn = pace == BudgetPace.over || pace == BudgetPace.ahead;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.cardTheme.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: accent.withValues(alpha: 0.22)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: accent.withValues(alpha: 0.16),
                      child: Icon(budgetIcon(budget), color: accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            budget.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            budgetScopeLabel(budget),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (showPeriod)
                            Text(
                              budgetPeriodLabel(progress.period),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Budget options',
                      onSelected: (value) {
                        if (value == 'edit') onEdit();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'edit', child: Text('Edit budget')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BudgetProgressBar(
                        ratio: progress.ratio,
                        color: barColor,
                        todayFraction: progress.isCurrent
                            ? progress.elapsedFraction
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            showAmounts
                                ? formatMinorEtb(progress.spentMinor)
                                : 'ETB ••••••',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            showAmounts
                                ? 'of ${formatMinorEtb(budget.limitMinor)}'
                                : 'of ETB ••••••',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        budgetProgressStatus(progress,
                            showAmounts: showAmounts),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: warn
                              ? barColor
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: warn ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Spending no budget watches, and budgets that would cover it.
class _UnbudgetedCard extends ConsumerWidget {
  const _UnbudgetedCard({required this.overview, required this.showAmounts});
  final BudgetOverview overview;
  final bool showAmounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final amount = showAmounts
        ? formatMinorEtb(overview.unbudgetedSpendMinor)
        : 'ETB ••••••';
    final when = overview.isCurrentMonth
        ? 'this month'
        : 'in ${formatMonth(overview.month)}';
    final top = overview.unbudgetedByCategory
        .take(2)
        .map((entry) => categoryInfoFor(entry.key).label)
        .toList(growable: false);
    final unbudgetedCategories = {
      for (final entry in overview.unbudgetedByCategory) entry.key,
    };
    final suggestions = overview.isCurrentMonth
        ? (ref.watch(budgetSuggestionsProvider).valueOrNull ?? const [])
            .where((s) =>
                s.categoryIds.isEmpty ||
                unbudgetedCategories.contains(s.categoryIds.first))
            .take(3)
            .toList(growable: false)
        : const <BudgetSuggestion>[];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'You spent $amount $when outside your budgets'
                  '${top.isEmpty ? '' : ', mostly ${top.join(' and ')}'}.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final suggestion in suggestions)
              _SuggestionRow(suggestion: suggestion, showAmounts: showAmounts),
          ],
        ],
      ),
    );
  }
}

/// A one-tap budget built from what the user actually spends.
class _SuggestionRow extends ConsumerStatefulWidget {
  const _SuggestionRow({required this.suggestion, required this.showAmounts});

  final BudgetSuggestion suggestion;
  final bool showAmounts;

  @override
  ConsumerState<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends ConsumerState<_SuggestionRow> {
  bool _adding = false;

  Future<void> _add() async {
    final suggestion = widget.suggestion;
    final service = ref.read(budgetServiceProvider);
    // The row disappears once its budget exists; Undo must not need it.
    final dataVersion = ref.read(dataVersionProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _adding = true);
    final budget = Budget(
      id: 'budget-${DateTime.now().millisecondsSinceEpoch}',
      name: suggestion.name,
      categoryIds: suggestion.categoryIds,
      limitMinor: suggestion.limitMinor,
      createdAt: DateTime.now(),
    );
    try {
      await service.saveBudget(budget);
      dataVersion.state++;
      messenger.showSnackBar(
        SnackBar(
          persist: false,
          content: Text(
            widget.showAmounts
                ? 'Added “${budget.name}”: '
                    '${formatMinorEtb(budget.limitMinor)} a month.'
                : 'Added “${budget.name}”.',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await service.deleteBudget(budget.id);
              dataVersion.state++;
            },
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestion = widget.suggestion;
    final info = suggestion.categoryIds.isEmpty
        ? null
        : categoryInfoFor(suggestion.categoryIds.first);
    final color = info?.color ?? theme.colorScheme.primary;
    final usual = widget.showAmounts
        ? formatMinorEtb(suggestion.monthlyAverageMinor)
        : 'ETB ••••';
    final limit =
        widget.showAmounts ? formatMinorEtb(suggestion.limitMinor) : 'ETB ••••';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.16),
            child: Icon(
              info?.icon ?? Icons.savings_rounded,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Usually $usual a month · limit $limit',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: _adding ? null : _add,
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _AiBudgetCard extends StatefulWidget {
  const _AiBudgetCard({required this.ref});
  final WidgetRef ref;

  @override
  State<_AiBudgetCard> createState() => _AiBudgetCardState();
}

class _AiBudgetCardState extends State<_AiBudgetCard> {
  bool _loading = false;
  String? _insight;

  Future<void> _run() async {
    setState(() => _loading = true);
    try {
      final text = await widget.ref
          .read(aiAssistantServiceProvider)
          .generateInsight(AiInsightKind.budget);
      if (!mounted) return;
      setState(() => _insight = text);
    } catch (error) {
      if (!mounted) return;
      setState(() => _insight = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.4)),
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI budget review',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: _loading ? null : _run,
                child: Text(_loading ? 'Thinking…' : 'Analyse'),
              ),
            ],
          ),
          if (_insight != null) ...[
            const SizedBox(height: 4),
            Text(_insight!,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
          ] else
            Text(
              'Let Genzeb AI flag at-risk budgets and suggest adjustments.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyBudgets extends ConsumerWidget {
  const _EmptyBudgets({required this.showAmounts});
  final bool showAmounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final suggestions =
        ref.watch(budgetSuggestionsProvider).valueOrNull ?? const [];
    if (suggestions.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_graph_rounded,
                size: 36, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              'Start from your real spending',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Based on your last few months. Add one with a tap; you can '
              'change the limit any time.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            for (final suggestion in suggestions)
              _SuggestionRow(suggestion: suggestion, showAmounts: showAmounts),
            const SizedBox(height: 6),
            Center(
              child: TextButton.icon(
                onPressed: () => showBudgetEditor(context),
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Make my own instead'),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.savings_outlined,
              size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            'No budgets yet',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Set a limit for the month, for a few categories, or for a trip.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => showBudgetEditor(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create your first budget'),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One budget for one period: the numbers, where the money went, and the
/// transactions behind them.
class BudgetDetailPage extends ConsumerStatefulWidget {
  const BudgetDetailPage({
    super.key,
    required this.budgetId,
    this.monthOffset = 0,
  });

  final String budgetId;
  final int monthOffset;

  @override
  ConsumerState<BudgetDetailPage> createState() => _BudgetDetailPageState();
}

class _BudgetDetailPageState extends ConsumerState<BudgetDetailPage> {
  /// Swiped away, waiting for the save to land.
  final Set<String> _hidden = {};

  // Read once: the Undo snackbar can outlive this page.
  late final BudgetService _service = ref.read(budgetServiceProvider);
  late final StateController<int> _dataVersion =
      ref.read(dataVersionProvider.notifier);

  /// Saves run one after another so quick swipes can't overwrite each other.
  Future<void> _saves = Future.value();

  ({String budgetId, int monthOffset}) get _key =>
      (budgetId: widget.budgetId, monthOffset: widget.monthOffset);

  void _setExcluded(String transactionId, {required bool excluded}) {
    final budgetId = widget.budgetId;
    _saves = _saves
        .then((_) => _service.setTransactionExcluded(
              budgetId,
              transactionId,
              excluded: excluded,
            ))
        .catchError((Object _) {})
        .then((_) => _dataVersion.state++);
  }

  void _leaveOut(TransactionRecord record, String budgetName) {
    setState(() => _hidden.add(record.id));
    _setExcluded(record.id, excluded: true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // Actions make snackbars stay until dismissed; Undo is a courtesy.
        persist: false,
        content: Text('Left out of “$budgetName”. It stays in your ledger.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _putBack(record.id),
        ),
      ),
    );
  }

  void _putBack(String transactionId) {
    if (mounted) setState(() => _hidden.remove(transactionId));
    _setExcluded(transactionId, excluded: false);
  }

  @override
  void initState() {
    super.initState();
    // Touch both now, while ref is certainly usable.
    _service;
    _dataVersion;
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(budgetDetailProvider(_key));
    final showAmounts = !ref.watch(amountsHiddenProvider);
    final detail = detailAsync.valueOrNull;
    final budget = detail?.progress.budget;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          budget?.name ?? 'Budget',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: () => ref.read(amountsHiddenProvider.notifier).toggle(),
            icon: Icon(
              showAmounts
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
            ),
            tooltip: showAmounts ? 'Hide amounts' : 'Show amounts',
          ),
          if (budget != null)
            IconButton(
              onPressed: () => showBudgetEditor(context, existing: budget),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit budget',
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showAddTransactionSheet(context, ref),
        tooltip: 'Add transaction',
        child: const Icon(Icons.add_rounded),
      ),
      body: detailAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Could not load this budget.'),
          ),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('This budget was deleted.'));
          }
          return _body(context, detail, showAmounts);
        },
      ),
    );
  }

  Widget _body(BuildContext context, BudgetDetail detail, bool showAmounts) {
    final theme = Theme.of(context);
    final progress = detail.progress;
    final visible = detail.transactions
        .where((record) => !_hidden.contains(record.id))
        .toList(growable: false);
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    final count = visible.length;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 96 + safeBottom),
      children: [
        _DetailHeader(progress: progress, showAmounts: showAmounts),
        if (detail.spendByCategory.length > 1) ...[
          const SizedBox(height: 12),
          _CategorySplit(
            entries: detail.spendByCategory,
            totalMinor: progress.spentMinor,
            showAmounts: showAmounts,
          ),
        ],
        const SizedBox(height: 18),
        Text(
          count == 1 ? '1 transaction' : '$count transactions',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Tap one to see or fix its category. Swipe left to leave it out '
          'of this budget.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (visible.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              progress.pace == BudgetPace.upcoming
                  ? 'This budget starts '
                      '${budgetDateLabel(progress.period.start)}.'
                  : progress.isCurrent
                      ? 'Nothing counted toward this budget yet.\n'
                          'Use + to add a cash purchase; it also appears in '
                          'Ledger.'
                      : 'Nothing was counted in this period.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...visible.map(
            (record) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Dismissible(
                key: ValueKey('budget-tx-${record.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.remove_circle_outline_rounded,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Leave out',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                onDismissed: (_) => _leaveOut(record, progress.budget.name),
                child: TransactionTile(
                  record: record,
                  showDate: true,
                  onTap: () => showTransactionDetail(context, ref, record),
                ),
              ),
            ),
          ),
        if (detail.excluded.isNotEmpty) ...[
          const SizedBox(height: 8),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                'Left out of this budget (${detail.excluded.length})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                'Still in your ledger, just not counted here.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              children: [
                for (final record in detail.excluded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Column(
                      children: [
                        TransactionTile(
                          record: record,
                          showDate: true,
                          onTap: () =>
                              showTransactionDetail(context, ref, record),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _putBack(record.id),
                            icon: const Icon(Icons.undo_rounded, size: 18),
                            label: const Text('Count it again'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.progress, required this.showAmounts});

  final BudgetProgress progress;
  final bool showAmounts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final budget = progress.budget;
    final accent = budgetAccent(budget, theme);
    final pace = progress.pace;
    final barColor = budgetPaceColor(pace, theme, accent);
    final warn = pace == BudgetPace.over || pace == BudgetPace.ahead;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_rounded,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                budgetPeriodLabel(progress.period),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (budget.isMonthly) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '· repeats monthly',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            showAmounts ? formatMinorEtb(progress.spentMinor) : 'ETB ••••••',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            showAmounts
                ? 'of ${formatMinorEtb(budget.limitMinor)}'
                : 'of ETB ••••••',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          BudgetProgressBar(
            ratio: progress.ratio,
            color: barColor,
            height: 10,
            todayFraction: progress.isCurrent ? progress.elapsedFraction : null,
          ),
          const SizedBox(height: 8),
          Text(
            budgetProgressStatus(progress, showAmounts: showAmounts),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: warn ? barColor : null,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(budgetIcon(budget), size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  budgetScopeLabel(budget),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Food 4,200 · Groceries 2,100" for budgets that span categories.
class _CategorySplit extends StatelessWidget {
  const _CategorySplit({
    required this.entries,
    required this.totalMinor,
    required this.showAmounts,
  });

  final List<MapEntry<String, int>> entries;
  final int totalMinor;
  final bool showAmounts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where it went',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          for (final entry in entries) ...[
            Row(
              children: [
                Icon(
                  categoryInfoFor(entry.key).icon,
                  size: 18,
                  color: categoryInfoFor(entry.key).color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    categoryInfoFor(entry.key).label,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  showAmounts ? formatMinorEtb(entry.value) : 'ETB ••••',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            BudgetProgressBar(
              ratio: totalMinor <= 0 ? 0 : entry.value / totalMinor,
              color: categoryInfoFor(entry.key).color,
              height: 4,
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

Future<void> showBudgetEditor(BuildContext context, {Budget? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _BudgetEditorSheet(existing: existing),
  );
}

class _BudgetEditorSheet extends ConsumerStatefulWidget {
  const _BudgetEditorSheet({this.existing});
  final Budget? existing;

  @override
  ConsumerState<_BudgetEditorSheet> createState() => _BudgetEditorSheetState();
}

class _BudgetEditorSheetState extends ConsumerState<_BudgetEditorSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  bool _isGeneral = true;
  bool _allInstitutions = true;
  Set<String> _selectedCategories = <String>{};
  Set<String> _selectedInstitutionCodes = <String>{};
  BudgetPeriodKind _periodKind = BudgetPeriodKind.monthly;
  int _startDay = 1;
  DateTimeRange? _customRange;
  bool _saving = false;

  /// Errors show only after the first save attempt.
  bool _submitted = false;

  /// What the user usually spends in the chosen scope, per month.
  int? _typicalMinor;
  int _typicalRequest = 0;

  /// The user typed an amount; never overwrite it.
  bool _amountEdited = false;
  bool _amountAutoFilled = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameController.text = existing.name;
      _amountController.text = _majorText(existing.limitMinor);
      _selectedCategories = {...existing.categoryIds};
      _selectedInstitutionCodes = {...existing.institutionCodes};
      _isGeneral = existing.isGeneral;
      _allInstitutions = existing.isAllInstitutions;
      _periodKind = existing.periodKind;
      _startDay = existing.startDay;
      final start = existing.customStart;
      final end = existing.customEnd;
      if (start != null && end != null) {
        _customRange = DateTimeRange(start: start, end: end);
      }
      _amountEdited = true;
    }
    _loadTypical();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// ETB without needless decimals: 1500 -> "1500", 1500.50 -> "1500.50".
  static String _majorText(int minor) =>
      (minor / 100).toStringAsFixed(minor % 100 == 0 ? 0 : 2);

  int? get _amountMinor {
    final normalized = _amountController.text.replaceAll(',', '').trim();
    final major = double.tryParse(normalized);
    if (major == null || major <= 0) return null;
    return (major * 100).round();
  }

  String? get _amountError =>
      _submitted && _amountMinor == null ? 'Enter an amount above zero' : null;

  String? get _categoryError =>
      _submitted && !_isGeneral && _selectedCategories.isEmpty
          ? 'Pick at least one category'
          : null;

  String? get _institutionError =>
      _submitted && !_allInstitutions && _selectedInstitutionCodes.isEmpty
          ? 'Pick at least one bank or wallet'
          : null;

  String? get _datesError => _submitted &&
          _periodKind == BudgetPeriodKind.custom &&
          _customRange == null
      ? 'Pick the first and last day'
      : null;

  Future<void> _loadTypical() async {
    final request = ++_typicalRequest;
    final scopeMissing = (!_isGeneral && _selectedCategories.isEmpty) ||
        (!_allInstitutions && _selectedInstitutionCodes.isEmpty);
    if (scopeMissing) {
      setState(() => _typicalMinor = null);
      return;
    }
    final value =
        await ref.read(budgetServiceProvider).typicalMonthlySpendMinor(
              categoryIds: _isGeneral
                  ? const <String>[]
                  : _selectedCategories.toList(growable: false),
              institutionCodes: _allInstitutions
                  ? const <String>[]
                  : _selectedInstitutionCodes.toList(growable: false),
            );
    if (!mounted || request != _typicalRequest) return;
    setState(() {
      _typicalMinor = value == null || value <= 0 ? null : value;
      final typical = _typicalMinor;
      // Most people don't know what number to type; start from their own.
      if (!_amountEdited &&
          _periodKind == BudgetPeriodKind.monthly &&
          typical != null) {
        _amountController.text = _majorText(friendlyBudgetLimit(typical));
        _amountAutoFilled = true;
      }
    });
  }

  String? get _amountHelper {
    final typical = _typicalMinor;
    if (typical == null || _periodKind != BudgetPeriodKind.monthly) {
      return null;
    }
    final usual = formatMinorEtb(typical);
    return _amountAutoFilled
        ? 'Filled in from what you usually spend: about $usual a month.'
        : 'You usually spend about $usual a month on this.';
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialDateRange: _customRange,
      helpText: 'Budget dates',
      saveText: 'Done',
    );
    if (picked != null && mounted) setState(() => _customRange = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _submitted = true);
    final minor = _amountMinor;
    if (minor == null ||
        _categoryError != null ||
        _institutionError != null ||
        _datesError != null) {
      return;
    }
    final existing = widget.existing;
    final rawName = _nameController.text.trim();
    final range = _customRange;
    final isCustom = _periodKind == BudgetPeriodKind.custom;
    final budget = Budget(
      id: existing?.id ?? 'budget-${DateTime.now().millisecondsSinceEpoch}',
      name: rawName.isNotEmpty ? rawName : _defaultBudgetName(),
      categoryIds: _isGeneral
          ? const <String>[]
          : _selectedCategories.toList(growable: false),
      institutionCodes: _allInstitutions
          ? const <String>[]
          : _selectedInstitutionCodes.toList(growable: false),
      // Editing must keep what the user already left out.
      excludedTransactionIds: existing?.excludedTransactionIds ?? const [],
      limitMinor: minor,
      createdAt: existing?.createdAt ?? DateTime.now(),
      periodKind: _periodKind,
      startDay: _startDay,
      customStart: isCustom ? range?.start : null,
      customEnd: isCustom ? range?.end : null,
    );
    setState(() => _saving = true);
    try {
      await ref.read(budgetServiceProvider).saveBudget(budget);
      refreshAppData(ref);
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _defaultBudgetName() {
    final range = _customRange;
    if (_isGeneral) {
      if (_periodKind == BudgetPeriodKind.custom && range != null) {
        return 'Spending ${budgetPeriodLabel(BudgetPeriod(
          start: range.start,
          end: DateTime(range.end.year, range.end.month, range.end.day + 1),
        ))}';
      }
      return 'Monthly spending';
    }
    final labels = _selectedCategories
        .map((id) => categoryInfoFor(id).label)
        .toList(growable: false);
    if (labels.isEmpty) return 'My budget';
    if (labels.length == 1) return labels.first;
    if (labels.length == 2) return '${labels[0]} & ${labels[1]}';
    return '${labels.first} + ${labels.length - 1} more';
  }

  static String _ordinal(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    return switch (day % 10) {
      1 => '${day}st',
      2 => '${day}nd',
      3 => '${day}rd',
      _ => '${day}th',
    };
  }

  Widget _errorText(ThemeData theme, String? error) {
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        error,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;
    final institutionOptionsAsync = ref.watch(institutionFilterOptionsProvider);
    final mediaQuery = MediaQuery.of(context);
    final maxSheetHeight = mediaQuery.size.height * 0.85;
    final isMonthly = _periodKind == BudgetPeriodKind.monthly;
    final range = _customRange;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        20 + mediaQuery.viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEdit ? 'Edit budget' : 'New budget',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Text('What does it cover?', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Everything'),
                      icon: Icon(Icons.all_inclusive_rounded),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Some categories'),
                      icon: Icon(Icons.category_outlined),
                    ),
                  ],
                  selected: {_isGeneral},
                  onSelectionChanged: (selection) {
                    setState(() => _isGeneral = selection.first);
                    _loadTypical();
                  },
                ),
              ),
              if (!_isGeneral) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Savings is money kept, never spending: a budget on it
                    // would always read zero.
                    for (final id in kExpenseCategoryIds)
                      if (id != 'savings' || _selectedCategories.contains(id))
                        FilterChip(
                          label: Text(categoryInfoFor(id).label),
                          avatar: Icon(categoryInfoFor(id).icon, size: 18),
                          selected: _selectedCategories.contains(id),
                          onSelected: (_) {
                            setState(() {
                              if (!_selectedCategories.remove(id)) {
                                _selectedCategories.add(id);
                              }
                            });
                            _loadTypical();
                          },
                        ),
                  ],
                ),
                _errorText(theme, _categoryError),
              ],
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('All banks and wallets'),
                subtitle: const Text('Count spending from every account'),
                value: _allInstitutions,
                onChanged: (value) {
                  setState(() => _allInstitutions = value);
                  _loadTypical();
                },
              ),
              if (!_allInstitutions) ...[
                institutionOptionsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => Text(
                    'Could not load your banks and wallets',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  data: (options) {
                    if (options.isEmpty) {
                      return Text(
                        'No banks or wallets yet. They appear here once '
                        'Genzeb reads their SMS.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      );
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in options)
                          FilterChip(
                            label: Text(option.label),
                            selected:
                                _selectedInstitutionCodes.contains(option.code),
                            onSelected: (_) {
                              setState(() {
                                if (!_selectedInstitutionCodes
                                    .remove(option.code)) {
                                  _selectedInstitutionCodes.add(option.code);
                                }
                              });
                              _loadTypical();
                            },
                          ),
                      ],
                    );
                  },
                ),
                _errorText(theme, _institutionError),
              ],
              const SizedBox(height: 14),
              Text('When?', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<BudgetPeriodKind>(
                  segments: const [
                    ButtonSegment(
                      value: BudgetPeriodKind.monthly,
                      label: Text('Every month'),
                      icon: Icon(Icons.autorenew_rounded),
                    ),
                    ButtonSegment(
                      value: BudgetPeriodKind.custom,
                      label: Text('Set dates'),
                      icon: Icon(Icons.date_range_rounded),
                    ),
                  ],
                  selected: {_periodKind},
                  onSelectionChanged: (selection) =>
                      setState(() => _periodKind = selection.first),
                ),
              ),
              const SizedBox(height: 8),
              if (isMonthly) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Each month starts on the',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    DropdownButton<int>(
                      value: _startDay,
                      menuMaxHeight: 320,
                      onChanged: (day) {
                        if (day != null) setState(() => _startDay = day);
                      },
                      items: [
                        for (var day = 1; day <= kMaxBudgetStartDay; day++)
                          DropdownMenuItem(
                            value: day,
                            child: Text(_ordinal(day)),
                          ),
                      ],
                    ),
                  ],
                ),
                Text(
                  'Paid on the 25th? Start on the 25th to plan from salary '
                  'to salary.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: _pickDates,
                  icon: const Icon(Icons.event_rounded),
                  label: Text(
                    range == null
                        ? 'Pick dates'
                        : budgetPeriodLabel(BudgetPeriod(
                            start: range.start,
                            end: DateTime(range.end.year, range.end.month,
                                range.end.day + 1),
                          )),
                  ),
                ),
                Text(
                  'For a trip, a holiday or an event.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                _errorText(theme, _datesError),
              ],
              const SizedBox(height: 18),
              TextField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) {
                  _amountEdited = true;
                  if (_amountAutoFilled || _submitted) {
                    setState(() => _amountAutoFilled = false);
                  }
                },
                decoration: InputDecoration(
                  labelText:
                      isMonthly ? 'Limit per month' : 'Limit for these dates',
                  prefixText: 'ETB ',
                  border: const OutlineInputBorder(),
                  errorText: _amountError,
                  helperText: _amountHelper,
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Name (optional)',
                  hintText: _defaultBudgetName(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(
                    _saving
                        ? 'Saving...'
                        : (isEdit ? 'Save changes' : 'Create budget'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
