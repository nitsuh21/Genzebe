import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/core/l10n/app_strings.dart';
import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/design_system/institution_avatar.dart';
import 'package:genzeb/design_system/theme.dart';
import 'package:genzeb/design_system/widgets.dart';
import 'package:genzeb/features/account/presentation/profile_screen.dart';
import 'package:genzeb/features/alerts/presentation/alert_widgets.dart';
import 'package:genzeb/features/budget/domain/models/budget.dart';
import 'package:genzeb/features/budget/presentation/budget_screen.dart';
import 'package:genzeb/features/budget/presentation/budget_widgets.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/device_sms_source.dart';
import 'package:genzeb/features/reports/application/report_service.dart';
import 'package:genzeb/features/transactions/domain/models/categories.dart';
import 'package:genzeb/features/transactions/presentation/add_transaction_sheet.dart';
import 'package:genzeb/features/transactions/presentation/transaction_detail_sheet.dart';
import 'package:genzeb/features/transactions/presentation/transaction_tile.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _syncing = false;

  /// Incremental refresh — the same one that runs on launch and resume.
  /// It never rebuilds history, so review decisions are never undone.
  Future<void> _forceSync() async {
    setState(() => _syncing = true);
    final permission =
        await ref.read(deviceSmsSourceProvider).ensurePermission();
    await ref.read(autoSyncControllerProvider).refresh();
    refreshAppData(ref);
    if (!mounted) return;
    setState(() => _syncing = false);
    final pending = ref.read(reviewQueueProvider).valueOrNull?.length ?? 0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          permission != SmsPermissionState.granted
              ? 'Allow SMS access to sync your bank messages.'
              : pending > 0
                  ? 'Up to date. $pending waiting for your review.'
                  : 'Up to date.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final insightsAsync = ref.watch(dashboardInsightsProvider);
    final transactionsAsync = ref.watch(ledgerTransactionsProvider);
    final seriesAsync = ref.watch(monthlySeriesProvider);
    final institutionOptionsAsync = ref.watch(institutionFilterOptionsProvider);
    final selectedInstitutionCodes =
        ref.watch(selectedInstitutionCodesProvider);
    final showAmounts = !ref.watch(amountsHiddenProvider);
    final pendingReview =
        ref.watch(reviewQueueProvider).valueOrNull?.length ?? 0;

    return RefreshIndicator(
      onRefresh: () async => refreshAppData(ref),
      child: insightsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Something went wrong: $e')),
        data: (insights) {
          final recent = transactionsAsync.valueOrNull ?? const [];
          final series = seriesAsync.valueOrNull ?? const [];
          final safeBottom = MediaQuery.of(context).viewPadding.bottom;
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 28 + safeBottom + 84),
            children: [
              _Header(
                displayName: ref
                    .watch(accountControllerProvider)
                    .profile
                    ?.displayName
                    ?.split(' ')
                    .first,
              ),
              const SizedBox(height: 16),
              institutionOptionsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (options) {
                  if (options.isEmpty) return const SizedBox.shrink();
                  return SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            selected: selectedInstitutionCodes.isEmpty,
                            showCheckmark: false,
                            label: Text(strings.allInstitutions),
                            onSelected: (_) => clearInstitutionFilters(ref),
                          ),
                        ),
                        ...options.map(
                          (option) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              selected: selectedInstitutionCodes
                                  .contains(option.code),
                              showCheckmark: false,
                              label: Text(option.label),
                              onSelected: (_) =>
                                  toggleInstitutionFilter(ref, option.code),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _BalanceHero(
                insights: insights,
                showAmounts: showAmounts,
                onToggleAmounts: () =>
                    ref.read(amountsHiddenProvider.notifier).toggle(),
              ),
              const SizedBox(height: 16),
              _QuickActions(
                syncing: _syncing,
                onAdd: () => showAddTransactionSheet(context, ref),
                onSync: _syncing ? null : _forceSync,
              ),
              if (pendingReview > 0) ...[
                const SizedBox(height: 12),
                _ReviewNudge(
                  count: pendingReview,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const SmsOpsPage()),
                  ),
                ),
              ],
              if (insights.accountCards.isNotEmpty) ...[
                const SizedBox(height: 20),
                SectionHeader(title: strings.accounts),
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: insights.accountCards.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) => _AccountCard(
                      card: insights.accountCards[index],
                      showAmounts: showAmounts,
                    ),
                  ),
                ),
              ],
              _BudgetGlance(showAmounts: showAmounts),
              const SizedBox(height: 20),
              SectionHeader(title: strings.cashFlow),
              _CashflowCard(series: series),
              const SizedBox(height: 20),
              SectionHeader(title: strings.insights),
              if (insights.incomeMinor == 0 && insights.expenseMinor == 0)
                const _QuietMonthCard()
              else
                _MonthNotes(insights: insights, showAmounts: showAmounts),
              const SizedBox(height: 20),
              SectionHeader(
                title: strings.recentActivity,
                action: TextButton(
                  onPressed: () => ref.read(homeTabProvider.notifier).state = 1,
                  child: Text('See all (${insights.transactionCount})'),
                ),
              ),
              if (recent.isEmpty)
                _EmptyState(onAdd: () => showAddTransactionSheet(context, ref))
              else
                TransactionGroup(
                  children: [
                    for (final record in recent.take(6))
                      TransactionTile(
                        record: record,
                        dense: true,
                        showDate: true,
                        grouped: true,
                        onTap: () =>
                            showTransactionDetail(context, ref, record),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({this.displayName});

  final String? displayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final strings = ref.watch(stringsProvider);
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? strings.goodMorning
        : hour < 18
            ? strings.goodAfternoon
            : strings.goodEvening;
    final name = displayName?.trim();
    final hasName = name != null && name.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasName ? greeting : formatDay(DateTime.now()),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                hasName ? name : greeting,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
        const AlertBellButton(),
      ],
    );
  }
}

class _BalanceHero extends ConsumerWidget {
  const _BalanceHero({
    required this.insights,
    required this.showAmounts,
    required this.onToggleAmounts,
  });

  final DashboardInsights insights;
  final bool showAmounts;
  final VoidCallback onToggleAmounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final strings = ref.watch(stringsProvider);
    final quiet = insights.incomeMinor == 0 && insights.expenseMinor == 0;
    // Same deep indigo as onboarding: one flat brand surface, so the total
    // is the only thing that stands out.
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 6, 6, 20),
      decoration: BoxDecoration(
        color: kBrandIndigoDeep,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                strings.totalBalance,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: showAmounts ? 'Hide amounts' : 'Show amounts',
                onPressed: onToggleAmounts,
                icon: Icon(
                  showAmounts
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.white.withValues(alpha: 0.7),
                  size: 22,
                ),
              ),
            ],
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'ETB ',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text: showAmounts
                      ? formatMinorPlain(insights.totalBalanceMinor)
                      : '••••••',
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            maxLines: 1,
          ),
          const SizedBox(height: 18),
          if (quiet)
            Text(
              'No activity yet this month',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    color: const Color(0xFF5FD39A),
                    label: strings.income,
                    value: showAmounts
                        ? formatCompactEtb(insights.incomeMinor)
                        : 'ETB ••••',
                  ),
                ),
                Expanded(
                  child: _HeroStat(
                    color: const Color(0xFFFF8A78),
                    label: strings.expense,
                    value: showAmounts
                        ? formatCompactEtb(insights.expenseMinor)
                        : 'ETB ••••',
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// This month's money in or out; the dot matches the cash-flow chart.
class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions({
    required this.syncing,
    required this.onAdd,
    required this.onSync,
  });

  final bool syncing;
  final VoidCallback onAdd;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final auto = ref.watch(autoSyncStatusProvider).valueOrNull;
    final busy = syncing || (auto?.running ?? false);
    final last = auto?.lastSyncedAt;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildAdd(strings)),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                icon: busy ? null : Icons.sync_rounded,
                label: busy ? strings.syncing : strings.syncSms,
                onPressed: busy ? null : onSync,
                busy: busy,
              ),
            ),
          ],
        ),
        // Auto-sync runs on launch, on return and when a bank SMS arrives;
        // this line makes that visible.
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            busy
                ? 'Checking your bank messages…'
                : (auto?.smsAccessOff ?? false)
                    ? 'SMS access is off. Tap Sync SMS to allow it.'
                    : last == null
                        ? 'Syncs automatically when bank messages arrive'
                        : _syncedLabel(last),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }

  /// "Synced today at 9:41 AM", "Synced on Fri, Oct 2 at 6:05 PM".
  String _syncedLabel(DateTime last) {
    final day = relativeDayLabel(last);
    final when =
        day == 'Today' || day == 'Yesterday' ? day.toLowerCase() : 'on $day';
    return 'Synced $when at ${formatTime(last)}';
  }

  Widget _buildAdd(AppStrings strings) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.add_rounded,
            label: strings.add,
            onPressed: onAdd,
            filled: true,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.busy = false,
  });

  final IconData? icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (icon != null)
            Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return filled
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(shape: shape),
            child: child,
          )
        : FilledButton.tonal(
            onPressed: onPressed,
            style: FilledButton.styleFrom(shape: shape),
            child: child,
          );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.card,
    required this.showAmounts,
  });

  final AccountInsightCard card;
  final bool showAmounts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.cardTheme.color,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InstitutionAvatar.forCode(card.institutionCode, size: 34),
          const Spacer(),
          Text(
            card.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            showAmounts ? formatMinorEtb(card.balanceMinor) : 'ETB ••••••',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _CashflowCard extends ConsumerWidget {
  const _CashflowCard({required this.series});

  final List<MonthBucket> series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final bars = series
        .map(
          (b) => MonthlyBar(
            label: formatShortMonth(b.month),
            incomeMajor: b.incomeMinor / 100.0,
            expenseMajor: b.expenseMinor / 100.0,
          ),
        )
        .toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              LegendDot(color: const Color(0xFF2E9E6B), label: strings.income),
              const SizedBox(width: 16),
              LegendDot(color: const Color(0xFFEF6C5A), label: strings.expense),
            ],
          ),
          const SizedBox(height: 16),
          if (bars.isEmpty)
            const SizedBox(
              height: 80,
              child: Center(child: Text('No data yet')),
            )
          else
            MonthlyBarChart(bars: bars, valueLabel: formatCompactNumber),
        ],
      ),
    );
  }
}

/// This month in plain sentences: what was kept, where most of it went,
/// and what the banks charged. Only lines that have something to say.
class _MonthNotes extends StatelessWidget {
  const _MonthNotes({required this.insights, required this.showAmounts});

  final DashboardInsights insights;
  final bool showAmounts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      if (insights.incomeMinor > 0)
        insights.savingsRate >= 0
            ? ('Kept', '${insights.savingsRate.toStringAsFixed(0)}% of income')
            : (
                'Spent more than earned',
                'by ${(-insights.savingsRate).toStringAsFixed(0)}%'
              ),
      if (insights.topExpenseCategory != 'No data')
        (
          'Spent most on',
          '${categoryInfoFor(insights.topExpenseCategory).label}, '
              '${insights.topExpenseShare.toStringAsFixed(0)}%',
        ),
      if (insights.feesMinor > 0)
        (
          'Bank fees',
          showAmounts ? formatMinorEtb(insights.feesMinor) : 'ETB ••••',
        ),
    ];
    if (rows.isEmpty) return const _QuietMonthCard();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[i].$1,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    rows[i].$2,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_rounded,
              size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('No transactions yet',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Add one manually or sync your bank SMS to get started.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add transaction'),
          ),
        ],
      ),
    );
  }
}

/// "2 transactions need your review" — the one action the parser cannot
/// take for the user, surfaced where they will actually see it.
/// This month's budgets at a glance, most at risk first. With no budgets
/// yet, a nudge toward the Budget tab once there is history to plan from.
class _BudgetGlance extends ConsumerWidget {
  const _BudgetGlance({required this.showAmounts});

  final bool showAmounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final strings = ref.watch(stringsProvider);
    final overview = ref.watch(budgetOverviewProvider).valueOrNull;
    if (overview == null) return const SizedBox.shrink();
    void openBudgetTab() => ref.read(homeTabProvider.notifier).state = 2;

    if (!overview.hasAnyBudgets) {
      final suggestions =
          ref.watch(budgetSuggestionsProvider).valueOrNull ?? const [];
      if (suggestions.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Material(
          color: theme.colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: openBudgetTab,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.savings_outlined,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Plan your month. Genzeb can suggest budgets from '
                      'your spending.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: theme.colorScheme.primary),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final items = overview.items
        .where((item) => item.pace != BudgetPace.upcoming)
        .take(3)
        .toList(growable: false);
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: strings.budgets,
            action: TextButton(
              onPressed: openBudgetTab,
              child: Text(
                overview.items.length > items.length
                    ? 'See all (${overview.items.length})'
                    : 'See all',
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                for (final item in items)
                  _BudgetGlanceRow(
                    progress: item,
                    showAmounts: showAmounts,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            BudgetDetailPage(budgetId: item.budget.id),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetGlanceRow extends StatelessWidget {
  const _BudgetGlanceRow({
    required this.progress,
    required this.showAmounts,
    required this.onTap,
  });

  final BudgetProgress progress;
  final bool showAmounts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final budget = progress.budget;
    final accent = budgetAccent(budget, theme);
    final pace = progress.pace;
    final color = budgetPaceColor(pace, theme, accent);
    final percent = (progress.ratio * 100).round();
    final String status;
    if (pace == BudgetPace.over) {
      status = 'Over budget';
    } else if (progress.isCurrent) {
      status = pace == BudgetPace.ahead
          ? 'Spending fast, ${daysLabel(progress.daysLeft)} left'
          : '${daysLabel(progress.daysLeft)} left';
    } else {
      status = 'Ended';
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Icon(budgetIcon(budget), size: 20, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          budget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '$percent%',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: pace == BudgetPace.over ||
                                  pace == BudgetPace.ahead
                              ? color
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  BudgetProgressBar(
                    ratio: progress.ratio,
                    color: color,
                    height: 6,
                    todayFraction:
                        progress.isCurrent ? progress.elapsedFraction : null,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    showAmounts && progress.remainingMinor > 0
                        ? '$status, ${formatMinorEtb(progress.remainingMinor)} '
                            'to spend'
                        : status,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewNudge extends StatelessWidget {
  const _ReviewNudge({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const tint = Color(0xFFE8833A);
    return Material(
      color: tint.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.rule_rounded, color: tint),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 transaction needs your review'
                      : '$count transactions need your review',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: tint),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuietMonthCard extends StatelessWidget {
  const _QuietMonthCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.insights_rounded,
              color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Insights appear once this month has some activity.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
