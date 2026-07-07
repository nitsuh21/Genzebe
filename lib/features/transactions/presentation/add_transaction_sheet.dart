import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzebet/app/providers.dart';
import 'package:genzebet/features/transactions/domain/models/categories.dart';
import 'package:genzebet/features/transactions/domain/models/transaction_models.dart';

Future<void> showAddTransactionSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => const _AddTransactionForm(),
  );
}

class _AddTransactionForm extends ConsumerStatefulWidget {
  const _AddTransactionForm();

  @override
  ConsumerState<_AddTransactionForm> createState() =>
      _AddTransactionFormState();
}

class _AddTransactionFormState extends ConsumerState<_AddTransactionForm> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  TransactionType _type = TransactionType.expense;
  String _categoryId = 'groceries';
  String _accountId = 'main-wallet';
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<String> get _categoryIds => _type == TransactionType.expense
      ? kExpenseCategoryIds
      : kIncomeCategoryIds;

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount.')),
      );
      return;
    }
    setState(() => _saving = true);
    final accounts = ref.read(accountsProvider).valueOrNull ?? const [];
    String accountName = 'Primary Wallet';
    for (final a in accounts) {
      if (a.id == _accountId) {
        accountName = a.name;
        break;
      }
    }
    await ref.read(transactionServiceProvider).addManualTransaction(
          transactionId: 'manual-${DateTime.now().microsecondsSinceEpoch}',
          accountId: _accountId,
          accountName: accountName,
          type: _type,
          amountMinor: (amount * 100).round(),
          categoryId: _categoryId,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        );
    refreshAppData(ref);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transaction added.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final accountOptions = <Account>[
      if (!accounts.any((a) => a.id == 'main-wallet'))
        Account(
          id: 'main-wallet',
          name: 'Primary Wallet',
          kind: 'wallet',
          createdAt: DateTime.now(),
        ),
      ...accounts,
    ];
    if (!accountOptions.any((a) => a.id == _accountId)) {
      _accountId = accountOptions.first.id;
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add transaction',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            SegmentedButton<TransactionType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Expense'),
                  icon: Icon(Icons.north_east_rounded),
                ),
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Income'),
                  icon: Icon(Icons.south_west_rounded),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (selection) {
                setState(() {
                  _type = selection.first;
                  _categoryId = _categoryIds.first;
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              autofocus: true,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: 'ETB ',
              ),
            ),
            const SizedBox(height: 16),
            Text('Category', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categoryIds.map((id) {
                final info = categoryInfoFor(id);
                final selected = id == _categoryId;
                return ChoiceChip(
                  selected: selected,
                  onSelected: (_) => setState(() => _categoryId = id),
                  avatar: Icon(
                    info.icon,
                    size: 18,
                    color: selected ? Colors.white : info.color,
                  ),
                  label: Text(info.label),
                  showCheckmark: false,
                  selectedColor: info.color,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : null,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              decoration: const InputDecoration(labelText: 'Account'),
              items: accountOptions
                  .map(
                    (account) => DropdownMenuItem(
                      value: account.id,
                      child: Text(account.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _accountId = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save transaction'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
