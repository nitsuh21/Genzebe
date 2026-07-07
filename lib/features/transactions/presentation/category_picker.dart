import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/features/reports/application/report_service.dart'
    show isOutflowType;
import 'package:genzeb/features/transactions/domain/models/categories.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';

/// Bottom-sheet category picker. Returns the chosen category id, or null.
Future<String?> showCategoryPicker(
  BuildContext context, {
  required bool isExpense,
  String? current,
}) {
  final ids = isExpense ? kExpenseCategoryIds : kIncomeCategoryIds;
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
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
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in ids)
                  _CategoryChip(
                    info: categoryInfoFor(id),
                    selected: id == current,
                    onTap: () => Navigator.of(sheetContext).pop(id),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
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

/// Tap-a-transaction flow: pick a new category, apply it, and (for SMS
/// transactions) teach Genzeb to always file that merchant correctly.
Future<void> promptRecategorize(
  BuildContext context,
  WidgetRef ref,
  TransactionRecord record,
) async {
  final selected = await showCategoryPicker(
    context,
    isExpense: isOutflowType(record.type),
    current: record.categoryId,
  );
  if (selected == null || selected == record.categoryId) return;

  final learnedMerchant = await ref
      .read(transactionServiceProvider)
      .changeCategory(transactionId: record.id, categoryId: selected);
  refreshAppData(ref);
  if (!context.mounted) return;
  final label = categoryInfoFor(selected).label;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        learnedMerchant == null
            ? 'Moved to $label.'
            : 'Moved to $label — "$learnedMerchant" will always go there now.',
      ),
    ),
  );
}
