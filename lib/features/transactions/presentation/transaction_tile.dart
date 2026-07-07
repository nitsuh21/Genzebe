import 'package:flutter/material.dart';
import 'package:genzebet/core/utils/formatters.dart';
import 'package:genzebet/features/reports/application/report_service.dart';
import 'package:genzebet/features/transactions/domain/models/categories.dart';
import 'package:genzebet/features/transactions/domain/models/transaction_models.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.record,
    this.dense = false,
  });

  final TransactionRecord record;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = categoryInfoFor(record.categoryId);
    final isExpense = isOutflowType(record.type);
    final signedMinor = signedMinorForRecord(record);
    final amountColor =
        isExpense ? const Color(0xFFE25555) : const Color(0xFF2E9E6B);

    final title = record.note?.isNotEmpty == true ? record.note! : info.label;
    final subtitleParts = <String>[
      _sourceLabel(record.source),
      relativeDayLabel(record.occurredAt),
    ];
    if (record.smsSender != null && record.smsSender!.isNotEmpty) {
      subtitleParts.insert(1, record.smsSender!);
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: dense ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: info.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(info.icon, color: info.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleParts.join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatSignedMinorEtb(signedMinor),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: amountColor,
                ),
              ),
              if (record.reviewStatus == TransactionReviewStatus.pendingReview)
                Text(
                  'Pending',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFFE8833A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _sourceLabel(TransactionSource source) {
    switch (source) {
      case TransactionSource.sms:
        return 'SMS';
      case TransactionSource.manual:
        return 'Manual';
      case TransactionSource.sync:
        return 'Synced';
    }
  }
}
