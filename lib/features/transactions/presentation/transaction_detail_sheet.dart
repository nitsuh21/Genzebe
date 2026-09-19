import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/features/reports/application/report_service.dart';
import 'package:genzeb/features/transactions/domain/models/categories.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:genzeb/features/transactions/presentation/category_picker.dart';
import 'package:genzeb/features/transactions/presentation/transaction_tile.dart';

/// Everything about one transaction — including the SMS it came from — with
/// the two things a person actually does with it: fix the category /
/// direction, or remove it.
Future<void> showTransactionDetail(
  BuildContext context,
  WidgetRef ref,
  TransactionRecord record,
) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _DetailSheet(record: record, hostContext: context),
  );
}

class _DetailSheet extends ConsumerWidget {
  const _DetailSheet({required this.record, required this.hostContext});

  final TransactionRecord record;

  /// The screen that opened this sheet; follow-up sheets (category picker)
  /// are shown from it after this one closes.
  final BuildContext hostContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final info = categoryInfoFor(record.categoryId);
    final isExpense = isOutflowType(record.type);
    final amountColor =
        isExpense ? const Color(0xFFE25555) : const Color(0xFF2E9E6B);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final account = accounts.where((a) => a.id == record.accountId).firstOrNull;
    final pending =
        record.reviewStatus == TransactionReviewStatus.pendingReview;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: info.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(info.icon, color: info.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transactionTitle(record),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${formatDay(record.occurredAt)} · '
                        '${formatTime(record.occurredAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              formatSignedMinorEtb(signedMinorForRecord(record)),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: amountColor,
              ),
            ),
            if (pending)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Waiting for your review — not counted in totals yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFE8833A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            _Row(label: 'Category', value: info.label),
            _Row(label: 'Type', value: isExpense ? 'Expense' : 'Income'),
            _Row(label: 'Account', value: account?.name ?? record.accountId),
            _Row(
              label: 'Source',
              value: switch (record.source) {
                TransactionSource.sms =>
                  'SMS from ${record.smsSender ?? 'unknown sender'}',
                TransactionSource.manual => 'Added by you',
                TransactionSource.sync => 'Synced',
              },
            ),
            if (record.smsSnippet?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 14),
              Text(
                'Original message',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  record.smsSnippet!.trim(),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      if (!hostContext.mounted) return;
                      await promptRecategorize(hostContext, ref, record);
                    },
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Change category'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(context, ref),
                  icon: Icon(Icons.delete_outline_rounded,
                      color: theme.colorScheme.error),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: Text(
          record.source == TransactionSource.sms
              ? 'It will be removed from your ledger and this SMS will be '
                  'ignored on future syncs.'
              : 'It will be removed from your ledger.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(smsIngestionServiceProvider).removeTransaction(record.id);
    refreshAppData(ref);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    if (!hostContext.mounted) return;
    ScaffoldMessenger.of(hostContext).showSnackBar(
      const SnackBar(content: Text('Transaction deleted.')),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
