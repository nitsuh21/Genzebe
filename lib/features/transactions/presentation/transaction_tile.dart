import 'package:flutter/material.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/features/reports/application/report_service.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/transactions/domain/models/categories.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';

/// The name a person recognises a transaction by: the merchant or
/// counterparty from the SMS, else the manual note, else the category.
String transactionTitle(TransactionRecord record) {
  final note = record.note?.trim();
  if (note != null && note.isNotEmpty) return note;
  final snippet = record.smsSnippet;
  if (snippet != null && snippet.trim().isNotEmpty) {
    final merchant = extractMerchant(
      snippet,
      isExpense: isOutflowType(record.type),
    );
    if (merchant != null) return merchant;
  }
  return categoryInfoFor(record.categoryId).label;
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.record,
    this.onTap,
    this.dense = false,
    this.showDate = false,
  });

  final TransactionRecord record;
  final VoidCallback? onTap;
  final bool dense;

  /// Lists grouped by day already show the date in the header; standalone
  /// lists (Home, report drill-downs) turn this on.
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = categoryInfoFor(record.categoryId);
    final isExpense = isOutflowType(record.type);
    final signedMinor = signedMinorForRecord(record);
    final amountColor =
        isExpense ? const Color(0xFFE25555) : const Color(0xFF2E9E6B);

    final title = transactionTitle(record);
    // Don't repeat the category when it is already the title.
    final subtitleParts = <String>[
      if (title != info.label) info.label,
      _sourceLabel(record),
      if (showDate) relativeDayLabel(record.occurredAt),
    ];

    final tile = Container(
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

    if (onTap == null) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: tile,
      ),
    );
  }

  /// "telebirr" / "CBE" for SMS rows (the sender is the account the money
  /// moved through); "Manual" otherwise.
  String _sourceLabel(TransactionRecord record) {
    switch (record.source) {
      case TransactionSource.sms:
        final sender = record.smsSender?.trim();
        if (sender == null || sender.isEmpty) return 'SMS';
        final institution = institutionForSender(sender);
        return institution == EthiopianInstitution.unknown
            ? sender
            : institutionInfo(institution).shortName;
      case TransactionSource.manual:
        return 'Manual';
      case TransactionSource.sync:
        return 'Synced';
    }
  }
}
