import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzebet/app/providers.dart';
import 'package:genzebet/core/utils/formatters.dart';
import 'package:genzebet/features/reports/application/report_service.dart';
import 'package:genzebet/features/transactions/domain/models/transaction_models.dart';
import 'package:genzebet/features/transactions/presentation/add_transaction_sheet.dart';
import 'package:genzebet/features/transactions/presentation/transaction_tile.dart';

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
          final net = records.fold<int>(0, (sum, record) {
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
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final filter in _LedgerFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          selected: _filter == filter,
                          onSelected: (_) => setState(() => _filter = filter),
                          showCheckmark: false,
                          label: Text(_filterLabel(filter)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              institutionOptionsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (options) {
                  if (options.isEmpty) return const SizedBox.shrink();
                  return SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
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
              const SizedBox(height: 8),
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final period in _LedgerPeriod.values)
                      if (period != _LedgerPeriod.custom)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            selected: _period == period,
                            onSelected: (_) => setState(() => _period = period),
                            showCheckmark: false,
                            label: Text(_periodLabel(period)),
                          ),
                        ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(
                          _period == _LedgerPeriod.custom && _customRange != null
                              ? '${formatDay(_customRange!.start)} - ${formatDay(_customRange!.end)}'
                              : 'Date range',
                        ),
                        onPressed: _pickDateRange,
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
        return 'This week';
      case _LedgerPeriod.thisMonth:
        return 'This month';
      case _LedgerPeriod.quarter:
        return 'Quarterly';
      case _LedgerPeriod.semiAnnual:
        return 'Semi-annual';
      case _LedgerPeriod.all:
        return 'All time';
      case _LedgerPeriod.custom:
        return 'Custom';
    }
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({
    required this.records,
    required this.bottomInset,
  });

  final List<TransactionRecord> records;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
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
            child: TransactionTile(record: item),
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
