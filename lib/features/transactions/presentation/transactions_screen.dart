import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/features/reports/application/report_service.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:genzeb/features/transactions/presentation/add_transaction_sheet.dart';
import 'package:genzeb/features/transactions/presentation/category_picker.dart';
import 'package:genzeb/features/transactions/presentation/transaction_tile.dart';

enum _LedgerFilter { all, income, expense, sms, manual }
enum _LedgerPeriod {
  today,
  yesterday,
  thisWeek,
  thisMonth,
  quarter,
  semiAnnual,
  all,
  custom,
}

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  _LedgerFilter _filter = _LedgerFilter.all;
  _LedgerPeriod _period = _LedgerPeriod.thisMonth;
  DateTimeRange? _customRange;

  bool _matches(TransactionRecord record) {
    switch (_filter) {
      case _LedgerFilter.all:
        return true;
      case _LedgerFilter.income:
        return record.type != TransactionType.expense;
      case _LedgerFilter.expense:
        return record.type == TransactionType.expense;
      case _LedgerFilter.sms:
        return record.source == TransactionSource.sms;
      case _LedgerFilter.manual:
        return record.source == TransactionSource.manual;
    }
  }

  bool _matchesPeriod(TransactionRecord record) {
    final day = DateTime(
      record.occurredAt.year,
      record.occurredAt.month,
      record.occurredAt.day,
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case _LedgerPeriod.today:
        return day == today;
      case _LedgerPeriod.yesterday:
        return day == today.subtract(const Duration(days: 1));
      case _LedgerPeriod.thisWeek:
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        final weekEnd = weekStart.add(const Duration(days: 7));
        return !day.isBefore(weekStart) && day.isBefore(weekEnd);
      case _LedgerPeriod.thisMonth:
        return day.year == today.year && day.month == today.month;
      case _LedgerPeriod.quarter:
        final quarterStartMonth = ((today.month - 1) ~/ 3) * 3 + 1;
        final quarterStart = DateTime(today.year, quarterStartMonth, 1);
        final quarterEnd = DateTime(today.year, quarterStartMonth + 3, 1);
        return !day.isBefore(quarterStart) && day.isBefore(quarterEnd);
      case _LedgerPeriod.semiAnnual:
        final halfStartMonth = today.month <= 6 ? 1 : 7;
        final halfStart = DateTime(today.year, halfStartMonth, 1);
        final halfEnd = DateTime(today.year, halfStartMonth + 6, 1);
        return !day.isBefore(halfStart) && day.isBefore(halfEnd);
      case _LedgerPeriod.custom:
        final range = _customRange;
        if (range == null) return true;
        final start = DateTime(range.start.year, range.start.month, range.start.day);
        final end = DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
        ).add(const Duration(days: 1));
        return !day.isBefore(start) && day.isBefore(end);
      case _LedgerPeriod.all:
        return true;
    }
  }

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
      _period = _LedgerPeriod.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transactionsAsync = ref.watch(ledgerTransactionsProvider);
    final institutionOptionsAsync = ref.watch(institutionFilterOptionsProvider);
    final selectedInstitutionCodes = ref.watch(selectedInstitutionCodesProvider);
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddTransactionSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: transactionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (allRecords) {
          final records = allRecords
              .where(_matches)
              .where(_matchesPeriod)
              .toList()
            ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
          // Pending parses show in the list (badged) but never in the total,
          // matching how Reports counts.
          final net = records.fold<int>(0, (sum, record) {
            if (record.reviewStatus == TransactionReviewStatus.pendingReview) {
              return sum;
            }
            return sum + signedMinorForRecord(record);
          });
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'Ledger',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              // One compact filter bar — no horizontal scrolling. Each button
              // opens a bottom-sheet picker and shows the active value.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: _FilterButton(
                        icon: Icons.tune_rounded,
                        label: _filterLabel(_filter),
                        active: _filter != _LedgerFilter.all,
                        onTap: _pickTypeFilter,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FilterButton(
                        icon: Icons.account_balance_rounded,
                        label: _institutionSummary(
                          institutionOptionsAsync.valueOrNull ?? const [],
                          selectedInstitutionCodes,
                        ),
                        active: selectedInstitutionCodes.isNotEmpty,
                        onTap: () => _pickInstitutions(
                          institutionOptionsAsync.valueOrNull ?? const [],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FilterButton(
                        icon: Icons.calendar_month_rounded,
                        label: _period == _LedgerPeriod.custom &&
                                _customRange != null
                            ? '${formatDay(_customRange!.start)}–${formatDay(_customRange!.end)}'
                            : _periodLabel(_period),
                        active: _period != _LedgerPeriod.all,
                        onTap: _pickPeriod,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Text(
                      '${records.length} transaction(s)',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      formatSignedMinorEtb(net),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: records.isEmpty
                    ? _EmptyLedger(
                        onAdd: () => showAddTransactionSheet(context, ref),
                      )
                    : RefreshIndicator(
                        onRefresh: () async => refreshAppData(ref),
                        child: _GroupedList(
                          records: records,
                          bottomInset: safeBottom,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
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

  Future<void> _pickTypeFilter() async {
    final picked = await _showOptionsSheet<_LedgerFilter>(
      title: 'Show',
      options: [
        for (final filter in _LedgerFilter.values)
          _SheetOption(value: filter, label: _filterLabel(filter)),
      ],
      current: _filter,
    );
    if (picked != null) setState(() => _filter = picked);
  }

  Future<void> _pickPeriod() async {
    final picked = await _showOptionsSheet<_LedgerPeriod>(
      title: 'Period',
      options: [
        for (final period in _LedgerPeriod.values)
          if (period != _LedgerPeriod.custom)
            _SheetOption(value: period, label: _periodLabel(period)),
        const _SheetOption(
          value: _LedgerPeriod.custom,
          label: 'Custom range…',
        ),
      ],
      current: _period,
    );
    if (picked == null) return;
    if (picked == _LedgerPeriod.custom) {
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
            final selected = sheetRef.watch(selectedInstitutionCodesProvider);
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Institutions',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
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

  Future<T?> _showOptionsSheet<T>({
    required String title,
    required List<_SheetOption<T>> options,
    required T current,
  }) {
    return showModalBottomSheet<T>(
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
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                for (final option in options)
                  ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    title: Text(
                      option.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: option.value == current
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    trailing: option.value == current
                        ? Icon(Icons.check_circle_rounded,
                            color: theme.colorScheme.primary)
                        : null,
                    onTap: () =>
                        Navigator.of(sheetContext).pop(option.value),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _filterLabel(_LedgerFilter filter) {
    switch (filter) {
      case _LedgerFilter.all:
        return 'All';
      case _LedgerFilter.income:
        return 'Income';
      case _LedgerFilter.expense:
        return 'Expense';
      case _LedgerFilter.sms:
        return 'From SMS';
      case _LedgerFilter.manual:
        return 'Manual';
    }
  }

  String _periodLabel(_LedgerPeriod period) {
    switch (period) {
      case _LedgerPeriod.today:
        return 'Today';
      case _LedgerPeriod.yesterday:
        return 'Yesterday';
      case _LedgerPeriod.thisWeek:
        return 'Week';
      case _LedgerPeriod.thisMonth:
        return 'Month';
      case _LedgerPeriod.quarter:
        return 'Quarter';
      case _LedgerPeriod.semiAnnual:
        return '6 months';
      case _LedgerPeriod.all:
        return 'All time';
      case _LedgerPeriod.custom:
        return 'Custom';
    }
  }
}

class _SheetOption<T> {
  const _SheetOption({required this.value, required this.label});

  final T value;
  final String label;
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

class _GroupedList extends ConsumerWidget {
  const _GroupedList({
    required this.records,
    required this.bottomInset,
  });

  final List<TransactionRecord> records;
  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final groups = <String, List<TransactionRecord>>{};
    for (final record in records) {
      final key = relativeDayLabel(record.occurredAt);
      groups.putIfAbsent(key, () => []).add(record);
    }

    final children = <Widget>[];
    groups.forEach((label, items) {
      var dayTotal = 0;
      for (final item in items) {
        dayTotal += signedMinorForRecord(item);
      }
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                formatSignedMinorEtb(dayTotal),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
      for (final item in items) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TransactionTile(
              record: item,
              onTap: () => promptRecategorize(context, ref, item),
            ),
          ),
        );
      }
    });

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 104 + bottomInset),
      children: children,
    );
  }
}

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        const SizedBox(height: 100),
        Icon(Icons.swap_vert_rounded,
            size: 48, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Nothing here yet',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'Add a transaction or sync your SMS.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add transaction'),
          ),
        ),
      ],
    );
  }
}
