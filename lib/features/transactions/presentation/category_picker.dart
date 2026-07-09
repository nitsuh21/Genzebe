import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/features/reports/application/report_service.dart'
    show isOutflowType;
import 'package:genzeb/features/transactions/domain/models/categories.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';

class CategoryPick {
  const CategoryPick({required this.categoryId, required this.isExpense});

  final String categoryId;
  final bool isExpense;
}

/// Bottom-sheet category picker. Returns the chosen category id, or null.
Future<String?> showCategoryPicker(
  BuildContext context, {
  required bool isExpense,
  String? current,
}) async {
  final pick = await showCategoryDirectionPicker(
    context,
    isExpense: isExpense,
    current: current,
    allowDirectionSwitch: false,
  );
  return pick?.categoryId;
}

/// Category picker with an Expense/Income toggle, so a transaction whose
/// direction the parser got wrong can be fixed by hand.
Future<CategoryPick?> showCategoryDirectionPicker(
  BuildContext context, {
  required bool isExpense,
  String? current,
  bool allowDirectionSwitch = true,
}) {
  return showModalBottomSheet<CategoryPick>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PickerSheet(
      initialExpense: isExpense,
      current: current,
      allowDirectionSwitch: allowDirectionSwitch,
    ),
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({
    required this.initialExpense,
    required this.current,
    required this.allowDirectionSwitch,
  });

  final bool initialExpense;
  final String? current;
  final bool allowDirectionSwitch;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  late bool _isExpense = widget.initialExpense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ids = _isExpense ? kExpenseCategoryIds : kIncomeCategoryIds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Category',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (widget.allowDirectionSwitch) ...[
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Expense'),
                  icon: Icon(Icons.north_east_rounded, size: 16),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Income'),
                  icon: Icon(Icons.south_west_rounded, size: 16),
                ),
              ],
              selected: {_isExpense},
              onSelectionChanged: (selection) {
                setState(() => _isExpense = selection.first);
              },
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in ids)
                _CategoryChip(
                  info: categoryInfoFor(id),
                  selected: id == widget.current &&
                      _isExpense == widget.initialExpense,
                  onTap: () => Navigator.of(context).pop(
                    CategoryPick(categoryId: id, isExpense: _isExpense),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.info,
    required this.selected,
    required this.onTap,
  });

  final CategoryInfo info;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? info.color.withValues(alpha: 0.2)
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? info.color : Colors.transparent,
              width: 1.4,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(info.icon, size: 16, color: info.color),
              const SizedBox(width: 6),
              Text(
                info.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tap-a-transaction flow: pick a new category (and direction, when the
/// parser read income/expense backwards), apply it, and for SMS transactions
/// teach Genzeb to always file that merchant correctly.
Future<void> promptRecategorize(
  BuildContext context,
  WidgetRef ref,
  TransactionRecord record,
) async {
  final wasExpense = isOutflowType(record.type);
  final pick = await showCategoryDirectionPicker(
    context,
    isExpense: wasExpense,
    current: record.categoryId,
  );
  if (pick == null) return;
  if (pick.categoryId == record.categoryId &&
      pick.isExpense == wasExpense) {
    return;
  }

  final learnedMerchant = await ref.read(transactionServiceProvider)
      .changeCategory(
        transactionId: record.id,
        categoryId: pick.categoryId,
        makeExpense: pick.isExpense,
      );
  refreshAppData(ref);
  if (!context.mounted) return;
  final label = categoryInfoFor(pick.categoryId).label;
  final flipped = pick.isExpense != wasExpense
      ? ' (now ${pick.isExpense ? 'expense' : 'income'})'
      : '';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        learnedMerchant == null
            ? 'Moved to $label$flipped.'
            : 'Moved to $label$flipped — "$learnedMerchant" will always go '
                'there now.',
      ),
    ),
  );
}
