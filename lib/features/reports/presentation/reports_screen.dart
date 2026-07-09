import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/core/l10n/app_strings.dart';
import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/design_system/widgets.dart';
import 'package:genzeb/features/ai/application/ai_assistant_service.dart';
import 'package:genzeb/features/reports/application/report_service.dart';
import 'package:genzeb/features/transactions/domain/models/categories.dart';
import 'package:genzeb/features/transactions/presentation/category_picker.dart';
import 'package:genzeb/features/transactions/presentation/transaction_tile.dart';
import 'package:share_plus/share_plus.dart';

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
        final start =
            DateTime(range.start.year, range.start.month, range.start.day);
        final endExclusive =
            DateTime(range.end.year, range.end.month, range.end.day)
                .add(const Duration(days: 1));
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
        return 'Week';
      case _ReportPeriod.thisMonth:
        return 'Month';
      case _ReportPeriod.quarter:
        return 'Quarter';
      case _ReportPeriod.semiAnnual:
        return '6 months';
      case _ReportPeriod.all:
        return 'All time';
      case _ReportPeriod.custom:
        return 'Custom';
    }
  }

  Future<void> _pickPeriod() async {
    final picked = await showModalBottomSheet<_ReportPeriod>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Period',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final period in _ReportPeriod.values)
                  ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(
                      period == _ReportPeriod.custom
                          ? 'Custom range…'
                          : _periodLabel(period),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: period == _period
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    trailing: period == _period
                        ? Icon(Icons.check_circle_rounded,
                            color: theme.colorScheme.primary)
                        : null,
                    onTap: () => Navigator.of(sheetContext).pop(period),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null) return;
    if (picked == _ReportPeriod.custom) {
      await _pickDateRange();
    } else {
      setState(() => _period = picked);
    }
  }

  Future<void> _pickInstitutions(
    List<InstitutionFilterOption> options,
  ) async {
    if (options.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return Consumer(
          builder: (context, sheetRef, _) {
            final selected =
                sheetRef.watch(selectedInstitutionCodesProvider);
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Institutions',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: selected.isEmpty,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('All institutions'),
                      onChanged: (_) => clearInstitutionFilters(ref),
                    ),
                    for (final option in options)
                      CheckboxListTile(
                        value: selected.contains(option.code),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(option.label),
                        onChanged: (_) =>
                            toggleInstitutionFilter(ref, option.code),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _institutionSummary(
    List<InstitutionFilterOption> options,
    Set<String> selected,
  ) {
    if (selected.isEmpty) return 'All banks';
    if (selected.length == 1) {
      return options
          .firstWhere(
            (o) => o.code == selected.first,
            orElse: () => InstitutionFilterOption(
              code: selected.first,
              label: selected.first.toUpperCase(),
            ),
          )
          .label;
    }
    return '${selected.length} banks';
  }

  Future<void> _share(PeriodReport report, DateTime start, DateTime end) async {
    final t = report.totals;
    final summary = StringBuffer()
      ..writeln('Genzeb report '
          '${formatDay(start)} – ${formatDay(end.subtract(const Duration(days: 1)))}')
      ..writeln('Income: ${formatMinorEtb(t.incomeMinor)}')
      ..writeln('Spending: ${formatMinorEtb(t.expenseMinor)}')
      ..writeln('Net: ${formatMinorEtb(t.netMinor)}')
      ..writeln('Own transfers: ${formatMinorEtb(t.internalMovedMinor)}')
      ..writeln('Bank fees: ${formatMinorEtb(t.feesMinor)}');

    final csv = StringBuffer('date,type,category,amount_etb,account,internal\n');
    for (final tx in report.scopedTransactions) {
      final internal = report.internalIds.contains(tx.id);
      csv.writeln('${tx.occurredAt.toIso8601String().substring(0, 10)},'
          '${tx.type.name},${tx.categoryId},'
          '${(tx.amount.minorUnits / 100).toStringAsFixed(2)},'
          '${tx.accountId},$internal');
    }

    await SharePlus.instance.share(
      ShareParams(
        text: summary.toString(),
        files: [
          XFile.fromData(
            Uint8List.fromList(csv.toString().codeUnits),
            mimeType: 'text/csv',
            name: 'genzeb-report.csv',
          ),
        ],
        fileNameOverrides: ['genzeb-report.csv'],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = ref.watch(stringsProvider);
    final (start, endExclusive) = _rangeForPeriod();
    final selectedInstitutionCodes =
        ref.watch(selectedInstitutionCodesProvider);
    final institutionOptionsAsync =
        ref.watch(institutionFilterOptionsProvider);
    final institutionOptions =
        institutionOptionsAsync.valueOrNull ?? const <InstitutionFilterOption>[];
    ref.watch(dataVersionProvider);
    final reportFuture = ref.watch(reportServiceProvider).generatePeriodReport(
          startInclusive: start,
          endExclusive: endExclusive,
          institutionCodes: selectedInstitutionCodes,
        );
    final insightsAsync = ref.watch(dashboardInsightsProvider);
    final seriesAsync = ref.watch(monthlySeriesProvider);

    return FutureBuilder<PeriodReport>(
      future: reportFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final report = snapshot.data!;
        final totals = report.totals;
        final insights = insightsAsync.valueOrNull;
        final series = seriesAsync.valueOrNull ?? const <MonthBucket>[];
        final safeBottom = MediaQuery.of(context).viewPadding.bottom;
        final categoryEntries = totals.categoryTotalsMinor.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return RefreshIndicator(
          onRefresh: () async => refreshAppData(ref),
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 28 + safeBottom + 84),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.navReports,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: strings.share,
                    onPressed: () => _share(report, start, endExclusive),
                    icon: const Icon(Icons.ios_share_rounded, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _FilterButton(
                      icon: Icons.calendar_month_rounded,
                      label: _period == _ReportPeriod.custom &&
                              _customRange != null
                          ? '${formatDay(_customRange!.start)}–${formatDay(_customRange!.end)}'
                          : _periodLabel(_period),
                      active: _period != _ReportPeriod.thisMonth,
                      onTap: _pickPeriod,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _FilterButton(
                      icon: Icons.account_balance_rounded,
                      label: _institutionSummary(
                          institutionOptions, selectedInstitutionCodes),
                      active: selectedInstitutionCodes.isNotEmpty,
                      onTap: () => _pickInstitutions(institutionOptions),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${formatDay(start)} – ${formatDay(endExclusive.subtract(const Duration(days: 1)))}'
                '${totals.pendingCount > 0 ? '  ·  ${totals.pendingCount} ${strings.awaitingReview}' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              _SummaryRow(
                strings: strings,
                totals: totals,
                previous: report.previousTotals,
              ),
              const SizedBox(height: 10),
              _FlowStrip(strings: strings, totals: totals),
              if (_period == _ReportPeriod.thisMonth) ...[
                const SizedBox(height: 10),
                _RunRateCard(strings: strings, report: report),
              ],
              const SizedBox(height: 16),
              _AiReportCard(
                ref: ref,
                periodContext:
                    '${formatDay(start)} to ${formatDay(endExclusive.subtract(const Duration(days: 1)))}',
              ),
              if (report.balanceSeries.length >= 2) ...[
                const SizedBox(height: 20),
                SectionHeader(title: strings.balanceOverTime),
                _BalanceCard(series: report.balanceSeries),
              ],
              const SizedBox(height: 20),
              SectionHeader(title: strings.spendingBreakdown),
              _BreakdownCard(
                strings: strings,
                categoryEntries: categoryEntries,
                previous: report.previousTotals.categoryTotalsMinor,
                onCategoryTap: (categoryId) => _showCategorySheet(
                  context,
                  report,
                  categoryId,
                ),
              ),
              if (report.topMerchants.isNotEmpty) ...[
                const SizedBox(height: 20),
                SectionHeader(title: strings.topMerchants),
                _MerchantsCard(merchants: report.topMerchants),
              ],
              if (report.biggestSpends.isNotEmpty) ...[
                const SizedBox(height: 20),
                SectionHeader(title: strings.biggestTransactions),
                for (final tx in report.biggestSpends)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TransactionTile(
                      record: tx,
                      dense: true,
                      onTap: () => promptRecategorize(context, ref, tx),
                    ),
                  ),
              ],
              if (totals.incomeByCategoryMinor.isNotEmpty) ...[
                const SizedBox(height: 20),
                SectionHeader(title: strings.incomeBreakdown),
                _IncomeCard(byCategory: totals.incomeByCategoryMinor),
              ],
              const SizedBox(height: 20),
              SectionHeader(title: strings.sixMonthTrend),
              _TrendCard(
                strings: strings,
                series: series,
                onBarTap: (index) {
                  if (index < 0 || index >= series.length) return;
                  final month = series[index].month;
                  setState(() {
                    _period = _ReportPeriod.custom;
                    _customRange = DateTimeRange(
                      start: month,
                      end: DateTime(month.year, month.month + 1, 0),
                    );
                  });
                },
              ),
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

  void _showCategorySheet(
    BuildContext context,
    PeriodReport report,
    String categoryId,
  ) {
    final info = categoryInfoFor(categoryId);
    final rows = report.scopedTransactions
        .where((tx) =>
            tx.categoryId == categoryId &&
            isOutflowType(tx.type) &&
            !report.internalIds.contains(tx.id))
        .toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            final theme = Theme.of(context);
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Row(
                  children: [
                    Icon(info.icon, color: info.color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        info.label,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      formatMinorEtb(rows.fold<int>(
                          0, (sum, tx) => sum + tx.amount.minorUnits)),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                for (final tx in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TransactionTile(
                      record: tx,
                      dense: true,
                      onTap: () => promptRecategorize(context, ref, tx),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Cards
// ---------------------------------------------------------------------------

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.strings,
    required this.totals,
    required this.previous,
  });

  final AppStrings strings;
  final MonthlyReport totals;
  final MonthlyReport previous;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            label: strings.income,
            value: formatCompactEtb(totals.incomeMinor),
            color: const Color(0xFF2E9E6B),
            icon: Icons.south_west_rounded,
            deltaPct: _pct(totals.incomeMinor, previous.incomeMinor),
            deltaGoodWhenUp: true,
            vsLabel: strings.vsPrevious,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryTile(
            label: strings.expense,
            value: formatCompactEtb(totals.expenseMinor),
            color: const Color(0xFFEF6C5A),
            icon: Icons.north_east_rounded,
            deltaPct: _pct(totals.expenseMinor, previous.expenseMinor),
            deltaGoodWhenUp: false,
            vsLabel: strings.vsPrevious,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryTile(
            label: strings.net,
            value: formatCompactEtb(totals.netMinor),
            color: const Color(0xFF4E5AE8),
            icon: Icons.account_balance_wallet_rounded,
            deltaPct: null,
            deltaGoodWhenUp: true,
            vsLabel: strings.vsPrevious,
          ),
        ),
      ],
    );
  }

  double? _pct(int current, int previous) {
    if (previous == 0) return null;
    return (current - previous) / previous * 100;
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.deltaPct,
    required this.deltaGoodWhenUp,
    required this.vsLabel,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final double? deltaPct;
  final bool deltaGoodWhenUp;
  final String vsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = deltaPct;
    Color? deltaColor;
    if (pct != null) {
      final up = pct >= 0;
      final good = up == deltaGoodWhenUp;
      deltaColor = good ? const Color(0xFF2E9E6B) : const Color(0xFFE25555);
    }
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
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
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (pct != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  pct >= 0
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 11,
                  color: deltaColor,
                ),
                Flexible(
                  child: Text(
                    '${pct.abs().toStringAsFixed(0)}% $vsLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: deltaColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FlowStrip extends StatelessWidget {
  const _FlowStrip({required this.strings, required this.totals});

  final AppStrings strings;
  final MonthlyReport totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget item(IconData icon, Color color, String label, int minor) {
      return Expanded(
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatCompactEtb(minor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          item(Icons.swap_horiz_rounded, const Color(0xFF3B8DD6),
              strings.ownTransfers, totals.internalMovedMinor),
          Container(width: 1, height: 30, color: theme.dividerColor),
          const SizedBox(width: 12),
          item(Icons.account_balance_rounded, const Color(0xFFD08A3E),
              strings.bankFees, totals.feesMinor),
        ],
      ),
    );
  }
}

class _RunRateCard extends StatelessWidget {
  const _RunRateCard({required this.strings, required this.report});

  final AppStrings strings;
  final PeriodReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.speed_rounded,
              size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${strings.dailyAverage}: '
              '${formatCompactEtb(report.dailyAverageExpenseMinor)}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '${strings.projectedTotal}: '
            '${formatCompactEtb(report.projectedExpenseMinor)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.series});

  final List<BalancePoint> series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values =
        series.map((p) => p.balanceMinor / 100.0).toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatMinorEtb(series.last.balanceMinor),
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            formatDay(series.last.at),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SimpleLineChart(values: values),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDay(series.first.at),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                formatDay(series.last.at),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AiReportCard extends StatefulWidget {
  const _AiReportCard({required this.ref, required this.periodContext});

  final WidgetRef ref;
  final String periodContext;

  @override
  State<_AiReportCard> createState() => _AiReportCardState();
}

class _AiReportCardState extends State<_AiReportCard> {
  bool _loading = false;
  String? _insight;
  DateTime? _generatedAt;

  Future<void> _run() async {
    setState(() => _loading = true);
    try {
      final selectedCodes = widget.ref.read(selectedInstitutionCodesProvider);
      final text =
          await widget.ref.read(aiAssistantServiceProvider).generateInsight(
                AiInsightKind.reports,
                institutionCodes: selectedCodes,
                periodContext: widget.periodContext,
              );
      if (!mounted) return;
      setState(() {
        _insight = text;
        _generatedAt = DateTime.now();
      });
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
        border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.4)),
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
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
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
            if (_generatedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                formatTime(_generatedAt!),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ] else
            Text(
              'Let Genzeb AI summarise the biggest changes and suggest one '
              'action.',
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
  const _BreakdownCard({
    required this.strings,
    required this.categoryEntries,
    required this.previous,
    required this.onCategoryTap,
  });

  final AppStrings strings;
  final List<MapEntry<String, int>> categoryEntries;
  final Map<String, int> previous;
  final ValueChanged<String> onCategoryTap;

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
            strings.noSpendingPeriod,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final total =
        categoryEntries.fold<int>(0, (sum, entry) => sum + entry.value);
    final top = categoryEntries.take(5).toList(growable: false);
    final otherTotal = categoryEntries
        .skip(5)
        .fold<int>(0, (sum, entry) => sum + entry.value);
    final segments = [
      ...top.map((entry) => DonutSegment(
            value: entry.value.toDouble(),
            color: categoryInfoFor(entry.key).color,
            label: categoryInfoFor(entry.key).label,
          )),
      if (otherTotal > 0)
        DonutSegment(
          value: otherTotal.toDouble(),
          color: const Color(0xFF8A8FA3),
          label: strings.other,
        ),
    ];

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
              centerTop: strings.expense,
              centerBottom: formatCompactEtb(total),
            ),
          ),
          const SizedBox(height: 18),
          ...categoryEntries.take(8).map((entry) {
            final info = categoryInfoFor(entry.key);
            final share = total == 0 ? 0.0 : entry.value / total;
            final prev = previous[entry.key];
            double? deltaPct;
            if (prev != null && prev > 0) {
              deltaPct = (entry.value - prev) / prev * 100;
            }
            return InkWell(
              onTap: () => onCategoryTap(entry.key),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
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
                                  style:
                                      theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (deltaPct != null)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(right: 8),
                                  child: Text(
                                    '${deltaPct >= 0 ? '▲' : '▼'}'
                                    '${deltaPct.abs().toStringAsFixed(0)}%',
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(
                                      color: deltaPct >= 0
                                          ? const Color(0xFFE25555)
                                          : const Color(0xFF2E9E6B),
                                      fontWeight: FontWeight.w700,
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
                              backgroundColor:
                                  info.color.withValues(alpha: 0.15),
                              valueColor:
                                  AlwaysStoppedAnimation(info.color),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _MerchantsCard extends StatelessWidget {
  const _MerchantsCard({required this.merchants});

  final List<MerchantSpend> merchants;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = merchants.first.totalMinor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          for (final merchant in merchants)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          merchant.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: max == 0
                                ? 0
                                : merchant.totalMinor / max,
                            minHeight: 5,
                            backgroundColor: theme.colorScheme.primary
                                .withValues(alpha: 0.12),
                            valueColor: AlwaysStoppedAnimation(
                                theme.colorScheme.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatMinorEtb(merchant.totalMinor),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '×${merchant.count}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _IncomeCard extends StatelessWidget {
  const _IncomeCard({required this.byCategory});

  final Map<String, int> byCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(
                    categoryInfoFor(entry.key).icon,
                    size: 18,
                    color: categoryInfoFor(entry.key).color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      categoryInfoFor(entry.key).label,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${total == 0 ? 0 : (entry.value / total * 100).round()}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatMinorEtb(entry.value),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.strings,
    required this.series,
    required this.onBarTap,
  });

  final AppStrings strings;
  final List<MonthBucket> series;
  final ValueChanged<int> onBarTap;

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
            children: [
              LegendDot(color: const Color(0xFF2E9E6B), label: strings.income),
              const SizedBox(width: 16),
              LegendDot(
                  color: const Color(0xFFEF6C5A), label: strings.expense),
            ],
          ),
          const SizedBox(height: 16),
          if (bars.isEmpty)
            const SizedBox(
              height: 80,
              child: Center(child: Text('—')),
            )
          else
            MonthlyBarChart(bars: bars, onBarTap: onBarTap),
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

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: active
          ? theme.colorScheme.primary.withValues(alpha: 0.1)
          : theme.cardTheme.color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? theme.colorScheme.primary.withValues(alpha: 0.5)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.arrow_drop_down_rounded, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
