import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/design_system/widgets.dart';
import 'package:genzeb/features/ai/application/ai_assistant_service.dart';
import 'package:genzeb/features/reports/application/report_service.dart';
import 'package:genzeb/features/transactions/domain/models/categories.dart';

enum _ReportPeriod {
  today,
  yesterday,
  thisWeek,
  thisMonth,
  quarter,
  semiAnnual,
  all,
  custom,
}

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _ReportPeriod _period = _ReportPeriod.thisMonth;
  DateTimeRange? _customRange;

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initial = _customRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 30)),
          end: now,
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: initial,
    );
    if (picked == null) return;
    setState(() {
      _customRange = picked;
      _period = _ReportPeriod.custom;
    });
  }

  (DateTime, DateTime) _rangeForPeriod() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case _ReportPeriod.today:
        return (today, today.add(const Duration(days: 1)));
      case _ReportPeriod.yesterday:
        final start = today.subtract(const Duration(days: 1));
        return (start, today);
      case _ReportPeriod.thisWeek:
        final start = today.subtract(Duration(days: today.weekday - 1));
        return (start, start.add(const Duration(days: 7)));
      case _ReportPeriod.thisMonth:
        final start = DateTime(today.year, today.month, 1);
        return (start, DateTime(today.year, today.month + 1, 1));
      case _ReportPeriod.quarter:
        final quarterStartMonth = ((today.month - 1) ~/ 3) * 3 + 1;
        final start = DateTime(today.year, quarterStartMonth, 1);
        return (start, DateTime(today.year, quarterStartMonth + 3, 1));
      case _ReportPeriod.semiAnnual:
        final halfStartMonth = today.month <= 6 ? 1 : 7;
        final start = DateTime(today.year, halfStartMonth, 1);
        return (start, DateTime(today.year, halfStartMonth + 6, 1));
      case _ReportPeriod.all:
        return (
          DateTime(now.year - 3, 1, 1),
          today.add(const Duration(days: 1)),
        );
      case _ReportPeriod.custom:
        final range = _customRange;
        if (range == null) {
          final fallbackStart = DateTime(today.year, today.month, 1);
          return (fallbackStart, DateTime(today.year, today.month + 1, 1));
        }
        final start = DateTime(range.start.year, range.start.month, range.start.day);
        final endExclusive =
            DateTime(range.end.year, range.end.month, range.end.day).add(
          const Duration(days: 1),
        );
        return (start, endExclusive);
    }
  }

  String _periodLabel(_ReportPeriod period) {
    switch (period) {
      case _ReportPeriod.today:
        return 'Today';
      case _ReportPeriod.yesterday:
        return 'Yesterday';
      case _ReportPeriod.thisWeek:
        return 'This week';
      case _ReportPeriod.thisMonth:
        return 'This month';
      case _ReportPeriod.quarter:
        return 'Quarterly';
      case _ReportPeriod.semiAnnual:
        return 'Semi-annual';
      case _ReportPeriod.all:
        return 'All time';
      case _ReportPeriod.custom:
        return 'Custom';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (start, endExclusive) = _rangeForPeriod();
    final selectedInstitutionCodes = ref.watch(selectedInstitutionCodesProvider);
    final institutionOptionsAsync = ref.watch(institutionFilterOptionsProvider);
    final reportFuture = ref.watch(reportServiceProvider).generateReportForRange(
          startInclusive: start,
          endExclusive: endExclusive,
          institutionCodes: selectedInstitutionCodes,
        );
    final insightsAsync = ref.watch(dashboardInsightsProvider);
    final seriesAsync = ref.watch(monthlySeriesProvider);

    return FutureBuilder<MonthlyReport>(
      future: reportFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final report = snapshot.data!;
        final insights = insightsAsync.valueOrNull;
        final series = seriesAsync.valueOrNull ?? const [];
        final safeBottom = MediaQuery.of(context).viewPadding.bottom;
        final categoryEntries = report.categoryTotalsMinor.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return RefreshIndicator(
          onRefresh: () async => refreshAppData(ref),
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 28 + safeBottom + 84),
            children: [
              Text(
                'Reports',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final period in _ReportPeriod.values)
                      if (period != _ReportPeriod.custom)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            selected: _period == period,
                            onSelected: (_) => setState(() => _period = period),
                            showCheckmark: false,
                            label: Text(_periodLabel(period)),
                          ),
                        ),
                    ActionChip(
                      label: Text(
                        _period == _ReportPeriod.custom && _customRange != null
                            ? '${formatDay(_customRange!.start)} - ${formatDay(_customRange!.end)}'
                            : 'Date range',
                      ),
                      onPressed: _pickDateRange,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              institutionOptionsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (options) {
                  if (options.isEmpty) return const SizedBox.shrink();
                  return SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            selected: selectedInstitutionCodes.isEmpty,
                            showCheckmark: false,
                            label: const Text('All institutions'),
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
              Text(
                '${formatDay(start)} - ${formatDay(endExclusive.subtract(const Duration(days: 1)))}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _SummaryRow(report: report),
              const SizedBox(height: 16),
              _AiReportCard(ref: ref),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Spending breakdown'),
              _BreakdownCard(categoryEntries: categoryEntries),
              const SizedBox(height: 20),
              const SectionHeader(title: '6-month trend'),
              _TrendCard(series: series),
              if (insights != null) ...[
                const SizedBox(height: 20),
                const SectionHeader(title: 'SMS automation'),
                _AutomationCard(insights: insights),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AiReportCard extends StatefulWidget {
  const _AiReportCard({required this.ref});
  final WidgetRef ref;

  @override
  State<_AiReportCard> createState() => _AiReportCardState();
}

class _AiReportCardState extends State<_AiReportCard> {
  bool _loading = false;
  String? _insight;

  Future<void> _run() async {
    setState(() => _loading = true);
    try {
      final selectedCodes =
          widget.ref.read(selectedInstitutionCodesProvider);
      final text = await widget.ref
          .read(aiAssistantServiceProvider)
          .generateInsight(
            AiInsightKind.reports,
            institutionCodes: selectedCodes,
          );
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
                  'AI report insights',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: _loading ? null : _run,
                child: Text(_loading ? 'Thinking…' : 'Generate'),
              ),
            ],
          ),
          if (_insight != null) ...[
            const SizedBox(height: 4),
            Text(
              _insight!,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ] else
            Text(
              'Let Genzeb AI summarise the biggest changes and suggest one action.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.report});

  final MonthlyReport report;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            label: 'Income',
            value: formatCompactEtb(report.incomeMinor),
            color: const Color(0xFF2E9E6B),
            icon: Icons.south_west_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryTile(
            label: 'Expense',
            value: formatCompactEtb(report.expenseMinor),
            color: const Color(0xFFEF6C5A),
            icon: Icons.north_east_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryTile(
            label: 'Net',
            value: formatCompactEtb(report.netMinor),
            color: const Color(0xFF4E5AE8),
            icon: Icons.account_balance_wallet_rounded,
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.categoryEntries});

  final List<MapEntry<String, int>> categoryEntries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (categoryEntries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            'No spending recorded this month.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final total =
        categoryEntries.fold<int>(0, (sum, entry) => sum + entry.value);
    final top = categoryEntries.take(6).toList(growable: false);
    final segments = top
        .map((entry) => DonutSegment(
              value: entry.value.toDouble(),
              color: categoryInfoFor(entry.key).color,
              label: categoryInfoFor(entry.key).label,
            ))
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Center(
            child: DonutChart(
              segments: segments,
              centerTop: 'Spent',
              centerBottom: formatCompactEtb(total),
            ),
          ),
          const SizedBox(height: 18),
          ...top.map((entry) {
            final info = categoryInfoFor(entry.key);
            final share = total == 0 ? 0.0 : entry.value / total;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: info.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(info.icon, color: info.color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                info.label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              formatMinorEtb(entry.value),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: share,
                            minHeight: 6,
                            backgroundColor: info.color.withValues(alpha: 0.15),
                            valueColor: AlwaysStoppedAnimation(info.color),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.series});

  final List<MonthBucket> series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: const [
              LegendDot(color: Color(0xFF2E9E6B), label: 'Income'),
              SizedBox(width: 16),
              LegendDot(color: Color(0xFFEF6C5A), label: 'Expense'),
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

class _AutomationCard extends StatelessWidget {
  const _AutomationCard({required this.insights});

  final DashboardInsights insights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          _MetricRow(
            label: 'Transactions from SMS',
            value: insights.smsTransactionCount.toString(),
          ),
          const Divider(height: 20),
          _MetricRow(
            label: 'Pending review',
            value: insights.pendingReviewCount.toString(),
          ),
          const Divider(height: 20),
          _MetricRow(
            label: 'Parser health',
            value: '${insights.parserHealthScore}%',
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
