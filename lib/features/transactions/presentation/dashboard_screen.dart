import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/design_system/widgets.dart';
import 'package:genzeb/features/reports/application/report_service.dart';
import 'package:genzeb/features/transactions/domain/models/categories.dart';
import 'package:genzeb/features/transactions/presentation/add_transaction_sheet.dart';
import 'package:genzeb/features/transactions/presentation/transaction_tile.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _syncing = false;
  bool _showAmounts = false;

  Future<void> _forceSync() async {
    setState(() => _syncing = true);
    final result = await ref.read(syncServiceProvider).forceSyncFromSms();
    refreshAppData(ref);
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Synced ${result.processed} SMS • ${result.newlyParsed} parsed • '
          '${result.pendingReview} need review',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = ref.watch(stringsProvider);
    final insightsAsync = ref.watch(dashboardInsightsProvider);
    final transactionsAsync = ref.watch(ledgerTransactionsProvider);
    final seriesAsync = ref.watch(monthlySeriesProvider);
    final themeMode = ref.watch(themeModeProvider);
    final institutionOptionsAsync = ref.watch(institutionFilterOptionsProvider);
    final selectedInstitutionCodes = ref.watch(selectedInstitutionCodesProvider);

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
                themeMode: themeMode,
                onCycleTheme: () {
                  final next = switch (themeMode) {
                    ThemeMode.system => ThemeMode.light,
                    ThemeMode.light => ThemeMode.dark,
                    ThemeMode.dark => ThemeMode.system,
                  };
                  ref.read(themeModeProvider.notifier).setMode(next);
                },
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
                              selected: selectedInstitutionCodes.contains(option.code),
                              showCheckmark: false,
                              label: Text(option.label),
                              onSelected: (_) => toggleInstitutionFilter(ref, option.code),
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
                showAmounts: _showAmounts,
                onToggleAmounts: () {
                  setState(() => _showAmounts = !_showAmounts);
                },
              ),
              const SizedBox(height: 16),
              _QuickActions(
                syncing: _syncing,
                onAdd: () => showAddTransactionSheet(context, ref),
                onSync: _syncing ? null : _forceSync,
              ),
              if (insights.accountCards.isNotEmpty) ...[
                const SizedBox(height: 20),
                SectionHeader(title: strings.accounts),
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: insights.accountCards.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) =>
                        _AccountCard(
                          card: insights.accountCards[index],
                          showAmounts: _showAmounts,
                        ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SectionHeader(title: strings.cashFlow),
              _CashflowCard(series: series),
              const SizedBox(height: 20),
              SectionHeader(title: strings.insights),
              _InsightsGrid(insights: insights),
              const SizedBox(height: 20),
              SectionHeader(
                title: strings.recentActivity,
                action: Text(
                  '${insights.transactionCount} total',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (recent.isEmpty)
                _EmptyState(onAdd: () => showAddTransactionSheet(context, ref))
              else
                ...recent.take(6).map(
                      (record) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TransactionTile(record: record, dense: true),
                      ),
                    ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.themeMode,
    required this.onCycleTheme,
    this.displayName,
  });

  final ThemeMode themeMode;
  final VoidCallback onCycleTheme;
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
    final icon = switch (themeMode) {
      ThemeMode.system => Icons.brightness_auto_rounded,
      ThemeMode.light => Icons.light_mode_rounded,
      ThemeMode.dark => Icons.dark_mode_rounded,
    };
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                displayName ?? 'Genzeb',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: onCycleTheme,
          icon: Icon(icon),
          tooltip: 'Toggle theme',
        ),
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
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        // Fixed stops: colorScheme.secondary washes out to near-white in dark
        // mode, killing the contrast of the white text on this card.
        gradient: const LinearGradient(
          colors: [
            Color(0xFF4E5AE8),
            Color(0xFF6E5AE0),
            Color(0xFF9A66E0),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4E5AE8).withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                strings.totalBalance,
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
              const Spacer(),
              IconButton(
                tooltip: showAmounts ? 'Hide amounts' : 'Show amounts',
                onPressed: onToggleAmounts,
                icon: Icon(
                  showAmounts
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            showAmounts
                ? formatMinorEtb(insights.totalBalanceMinor)
                : 'ETB ••••••',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  icon: Icons.south_west_rounded,
                  label: strings.income,
                  value: showAmounts
                      ? formatCompactEtb(insights.incomeMinor)
                      : 'ETB ••••••',
                ),
              ),
              Container(
                width: 1,
                height: 34,
                color: Colors.white24,
              ),
              Expanded(
                child: _HeroStat(
                  icon: Icons.north_east_rounded,
                  label: strings.expense,
                  value: showAmounts
                      ? formatCompactEtb(insights.expenseMinor)
                      : 'ETB ••••••',
                  alignEnd: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.icon,
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
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
        const SizedBox(width: 12),
        Expanded(
          child: _ActionButton(
            icon: syncing ? null : Icons.sync_rounded,
            label: syncing ? strings.syncing : strings.syncSms,
            onPressed: onSync,
            busy: syncing,
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
            Icon(icon),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
    return filled
        ? FilledButton(onPressed: onPressed, child: child)
        : FilledButton.tonal(onPressed: onPressed, child: child);
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.account_balance_rounded,
                    size: 18, color: theme.colorScheme.onPrimaryContainer),
              ),
              const Spacer(),
              Icon(Icons.contactless_rounded,
                  color: theme.colorScheme.onSurfaceVariant, size: 18),
            ],
          ),
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
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
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
            MonthlyBarChart(bars: bars),
        ],
      ),
    );
  }
}

class _InsightsGrid extends StatelessWidget {
  const _InsightsGrid({required this.insights});

  final DashboardInsights insights;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _InsightData(
        title: 'Savings rate',
        value: '${insights.savingsRate.toStringAsFixed(0)}%',
        icon: Icons.savings_rounded,
        tint: const Color(0xFF2E9E6B),
        progress: (insights.savingsRate / 100).clamp(0.0, 1.0),
      ),
      _InsightData(
        title: 'Top category',
        value: insights.topExpenseCategory == 'No data'
            ? '—'
            : categoryInfoFor(insights.topExpenseCategory).label,
        icon: Icons.category_rounded,
        tint: const Color(0xFFE8833A),
        progress: (insights.topExpenseShare / 100).clamp(0.0, 1.0),
      ),
      _InsightData(
        title: 'Parser health',
        value: '${insights.parserHealthScore}%',
        icon: Icons.health_and_safety_rounded,
        tint: const Color(0xFF3B8DD6),
        progress: (insights.parserHealthScore / 100).clamp(0.0, 1.0),
      ),
      _InsightData(
        title: 'Month trend',
        value: '${insights.monthNetDeltaPercent.toStringAsFixed(0)}%',
        icon: Icons.trending_up_rounded,
        tint: const Color(0xFF8E63D8),
        progress: (insights.monthNetDeltaPercent.abs() / 100).clamp(0.0, 1.0),
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: cards.map((c) => _InsightCard(data: c)).toList(growable: false),
    );
  }
}

class _InsightData {
  const _InsightData({
    required this.title,
    required this.value,
    required this.icon,
    required this.tint,
    required this.progress,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color tint;
  final double progress;
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.data});

  final _InsightData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: data.tint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(data.icon, color: data.tint, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: data.progress,
              minHeight: 6,
              backgroundColor: data.tint.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(data.tint),
            ),
          ),
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
