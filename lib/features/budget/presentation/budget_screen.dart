import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/features/ai/application/ai_assistant_service.dart';
import 'package:genzeb/features/budget/domain/models/budget.dart';
import 'package:genzeb/features/reports/application/report_service.dart';
import 'package:genzeb/features/transactions/domain/models/categories.dart';
import 'package:genzeb/features/transactions/presentation/add_transaction_sheet.dart';
import 'package:genzeb/features/transactions/presentation/transaction_tile.dart';

class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key});

  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    final overviewAsync = ref.watch(budgetOverviewProvider);
    // One app-wide privacy switch, shared with Home.
    final showAmounts = !ref.watch(amountsHiddenProvider);

    return Scaffold(
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: safeBottom),
        child: FloatingActionButton.extended(
          heroTag: 'budget-fab',
          onPressed: () => _openBudgetEditor(context, ref),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New budget'),
        ),
      ),
      body: overviewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load budgets: $error')),
        data: (overview) {
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 28 + safeBottom + 84),
            children: [
              Text(
                'Budget',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Create flexible budgets: general plans or one plan with multiple categories.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (overview.items.isEmpty)
                _EmptyBudgets(onCreate: () => _openBudgetEditor(context, ref))
              else ...[
                _OverallCard(
                  overview: overview,
                  showAmounts: showAmounts,
                  onToggleAmounts: () =>
                      ref.read(amountsHiddenProvider.notifier).toggle(),
                ),
                const SizedBox(height: 12),
                _AiBudgetCard(ref: ref),
                const SizedBox(height: 8),
                ...overview.items.map(
                  (item) => _BudgetTile(
                    progress: item,
                    showAmounts: showAmounts,
                    onEdit: () =>
                        _openBudgetEditor(context, ref, existing: item.budget),
                    onDelete: () => _deleteBudget(context, ref, item.budget),
                    onViewTransactions: () => _openBudgetTransactions(
                        context: context, budget: item.budget),
                  ),
                ),
                if (overview.unbudgetedSpendMinor > 0)
                  _UnbudgetedCard(
                    amountMinor: overview.unbudgetedSpendMinor,
                    showAmounts: showAmounts,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteBudget(
    BuildContext context,
    WidgetRef ref,
    Budget budget,
  ) async {
    await ref.read(budgetServiceProvider).deleteBudget(budget.id);
    refreshAppData(ref);
  }

  Future<void> _openBudgetEditor(
    BuildContext context,
    WidgetRef ref, {
    Budget? existing,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BudgetEditorSheet(existing: existing),
    );
  }

  Future<void> _openBudgetTransactions({
    required BuildContext context,
    required Budget budget,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _BudgetTransactionsPage(budget: budget),
      ),
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({
    required this.overview,
    required this.showAmounts,
    required this.onToggleAmounts,
  });
  final BudgetOverview overview;
  final bool showAmounts;
  final VoidCallback onToggleAmounts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = overview.ratio.clamp(0.0, 1.0).toDouble();
    final over = overview.totalSpentMinor > overview.totalLimitMinor;
    final barColor = over
        ? theme.colorScheme.error
        : ratio > 0.85
            ? Colors.orange
            : theme.colorScheme.primary;
    final accent = theme.brightness == Brightness.dark
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.22),
            theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.surfaceContainer,
          ],
        ),
        border: Border.all(
          color: accent.withValues(alpha: 0.28),
        ),
        borderRadius: BorderRadius.circular(22),
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
              Text(
                'Spent this month',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onToggleAmounts,
                icon: Icon(
                  showAmounts
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
                tooltip: showAmounts ? 'Hide amounts' : 'Show amounts',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            showAmounts
                ? formatMinorEtb(overview.totalSpentMinor)
                : 'ETB ••••••',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            showAmounts
                ? 'of ${formatMinorEtb(overview.totalLimitMinor)} budgeted'
                : 'of ETB •••••• budgeted',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            over
                ? (showAmounts
                    ? 'Over budget by ${formatMinorEtb(-overview.remainingMinor)}'
                    : 'Over budget by ETB ••••••')
                : (showAmounts
                    ? '${formatMinorEtb(overview.remainingMinor)} left to spend'
                    : 'ETB •••••• left to spend'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetTransactionsPage extends ConsumerStatefulWidget {
  const _BudgetTransactionsPage({required this.budget});

  final Budget budget;

  @override
  ConsumerState<_BudgetTransactionsPage> createState() =>
      _BudgetTransactionsPageState();
}

class _BudgetTransactionsPageState
    extends ConsumerState<_BudgetTransactionsPage> {
  late Budget _budget;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _budget = widget.budget;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transactionsAsync = ref.watch(allTransactionsProvider);
    final accountsAsync = ref.watch(accountsProvider);
    final showAmounts = !ref.watch(amountsHiddenProvider);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1);
    final categoryScopeLabel = _budget.isGeneral
        ? 'All spending categories'
        : _budget.categoryIds.map((id) => categoryInfoFor(id).label).join(', ');
    final institutionScopeLabel = _budget.institutionCodes.isEmpty
        ? 'All institutions'
        : _budget.institutionCodes.map((code) => code.toUpperCase()).join(', ');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _budget.name,
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
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showAddTransactionSheet(context, ref),
        tooltip: 'Add transaction',
        child: const Icon(Icons.add_rounded),
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (accounts) => transactionsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Error: $error')),
          data: (records) {
            final institutionByAccount = <String, String>{
              for (final account in accounts)
                account.id: account.institutionCode?.trim().toLowerCase() ?? '',
            };
            final scoped = records.where((record) {
              if (!isOutflowType(record.type)) return false;
              if (record.occurredAt.isBefore(start) ||
                  !record.occurredAt.isBefore(end)) {
                return false;
              }
              if (_budget.institutionCodes.isNotEmpty) {
                final code = institutionByAccount[record.accountId] ?? '';
                if (!_budget.institutionCodes.contains(code)) return false;
              }
              if (_budget.excludedTransactionIds.contains(record.id)) {
                return false;
              }
              if (_budget.isGeneral) return true;
              return _budget.categoryIds.contains(record.categoryId);
            }).toList(growable: false)
              ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

            final total =
                scoped.fold<int>(0, (sum, tx) => sum + tx.amount.minorUnits);
            final safeBottom = MediaQuery.of(context).viewPadding.bottom;
            return ListView(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 96 + safeBottom),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.cardTheme.color,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        categoryScopeLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        institutionScopeLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        showAmounts ? formatMinorEtb(total) : 'ETB ••••••',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${scoped.length} matching transaction(s) this month',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Transactions',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (scoped.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardTheme.color,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'No matching transactions this month yet.\n'
                      'Use + to add one; it will also appear in Ledger.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ...scoped.map(
                    (record) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        children: [
                          TransactionTile(record: record, showDate: true),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _updating
                                  ? null
                                  : () => _excludeFromBudget(record.id),
                              icon: const Icon(
                                  Icons.remove_circle_outline_rounded),
                              label: const Text('Remove from budget'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _excludeFromBudget(String transactionId) async {
    if (_budget.excludedTransactionIds.contains(transactionId)) return;
    setState(() => _updating = true);
    final updated = _budget.copyWith(
      excludedTransactionIds: [
        ..._budget.excludedTransactionIds,
        transactionId,
      ],
    );
    try {
      await ref.read(budgetServiceProvider).saveBudget(updated);
      if (!mounted) return;
      setState(() {
        _budget = updated;
      });
      refreshAppData(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Removed from this budget only.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _restoreToBudget(transactionId),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _restoreToBudget(String transactionId) async {
    final updated = _budget.copyWith(
      excludedTransactionIds: _budget.excludedTransactionIds
          .where((id) => id != transactionId)
          .toList(growable: false),
    );
    await ref.read(budgetServiceProvider).saveBudget(updated);
    if (!mounted) return;
    setState(() => _budget = updated);
    refreshAppData(ref);
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({
    required this.progress,
    required this.showAmounts,
    required this.onEdit,
    required this.onDelete,
    required this.onViewTransactions,
  });

  final BudgetProgress progress;
  final bool showAmounts;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewTransactions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = progress.ratio.clamp(0.0, 1.0).toDouble();
    final over = progress.isOverBudget;
    final accent = progress.budget.isGeneral
        ? theme.colorScheme.primary
        : categoryInfoFor(progress.budget.categoryIds.first).color;
    final barColor = over
        ? theme.colorScheme.error
        : ratio > 0.85
            ? Colors.orange
            : accent;
    final institutionLabel = progress.budget.institutionCodes.isEmpty
        ? 'All institutions'
        : progress.budget.institutionCodes
            .map((code) => code.toUpperCase())
            .join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
              CircleAvatar(
                radius: 20,
                backgroundColor: accent.withValues(alpha: 0.16),
                child: Icon(Icons.savings_rounded, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progress.budget.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      institutionLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit budget')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          const SizedBox(height: 8),
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
                    ? 'of ${formatMinorEtb(progress.budget.limitMinor)}'
                    : 'of ETB ••••••',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            over
                ? (showAmounts
                    ? 'Over by ${formatMinorEtb(-progress.remainingMinor)}'
                    : 'Over by ETB ••••••')
                : (showAmounts
                    ? '${formatMinorEtb(progress.remainingMinor)} left'
                    : 'ETB •••••• left'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: over
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onViewTransactions,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('View transactions'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnbudgetedCard extends StatelessWidget {
  const _UnbudgetedCard({
    required this.amountMinor,
    required this.showAmounts,
  });
  final int amountMinor;
  final bool showAmounts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'You spent ${showAmounts ? formatMinorEtb(amountMinor) : 'ETB ••••••'} this month in categories '
              'without a budget.',
              style: theme.textTheme.bodySmall,
            ),
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

class _EmptyBudgets extends StatelessWidget {
  const _EmptyBudgets({required this.onCreate});
  final VoidCallback onCreate;

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
            'Create a general budget or combine multiple categories in one plan.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create your first budget'),
          ),
        ],
      ),
    );
  }
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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController.text = existing?.name ?? '';
    _amountController.text =
        existing == null ? '' : (existing.limitMinor / 100).toStringAsFixed(0);
    _selectedCategories = {...?existing?.categoryIds};
    _selectedInstitutionCodes = {...?existing?.institutionCodes};
    _isGeneral = existing?.isGeneral ?? true;
    _allInstitutions = existing?.institutionCodes.isEmpty ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final rawName = _nameController.text.trim();
    final normalizedAmount = _amountController.text.replaceAll(',', '').trim();
    final major = double.tryParse(normalizedAmount);
    final name = rawName.isNotEmpty ? rawName : _defaultBudgetName();
    if (major == null || major <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid budget amount.')),
      );
      return;
    }
    if (!_isGeneral && _selectedCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one category.')),
      );
      return;
    }
    if (!_allInstitutions && _selectedInstitutionCodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one institution.')),
      );
      return;
    }
    final minor = (major * 100).round();
    final budget = Budget(
      id: widget.existing?.id ??
          'budget-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      categoryIds: _isGeneral
          ? const <String>[]
          : _selectedCategories.toList(growable: false),
      institutionCodes: _allInstitutions
          ? const <String>[]
          : _selectedInstitutionCodes.toList(growable: false),
      limitMinor: minor,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
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
    if (_isGeneral) return 'General budget';
    if (_selectedCategories.length == 1) {
      final id = _selectedCategories.first;
      return '${categoryInfoFor(id).label} budget';
    }
    return 'Custom budget';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;
    final institutionOptionsAsync = ref.watch(institutionFilterOptionsProvider);
    final mediaQuery = MediaQuery.of(context);
    final maxSheetHeight = mediaQuery.size.height * 0.85;
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
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Budget name',
                  hintText: 'e.g. Family essentials',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Monthly limit (ETB)',
                  prefixText: 'ETB ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('General budget'),
                subtitle:
                    const Text('Apply this budget to all spending categories'),
                value: _isGeneral,
                onChanged: (value) {
                  setState(() => _isGeneral = value);
                },
              ),
              if (!_isGeneral) ...[
                const SizedBox(height: 6),
                Text('Categories', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final id in kExpenseCategoryIds)
                      FilterChip(
                        label: Text(categoryInfoFor(id).label),
                        avatar: Icon(categoryInfoFor(id).icon, size: 18),
                        selected: _selectedCategories.contains(id),
                        onSelected: (_) {
                          setState(() {
                            if (_selectedCategories.contains(id)) {
                              _selectedCategories.remove(id);
                            } else {
                              _selectedCategories.add(id);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('All institutions'),
                subtitle:
                    const Text('Apply this budget across every institution'),
                value: _allInstitutions,
                onChanged: (value) {
                  setState(() => _allInstitutions = value);
                },
              ),
              if (!_allInstitutions) ...[
                const SizedBox(height: 6),
                Text('Institutions', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                institutionOptionsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => Text(
                    'Could not load institutions',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  data: (options) {
                    if (options.isEmpty) {
                      return Text(
                        'No mapped institutions yet. Map SMS senders first.',
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
                                if (_selectedInstitutionCodes
                                    .contains(option.code)) {
                                  _selectedInstitutionCodes.remove(option.code);
                                } else {
                                  _selectedInstitutionCodes.add(option.code);
                                }
                              });
                            },
                          ),
                      ],
                    );
                  },
                ),
              ],
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
