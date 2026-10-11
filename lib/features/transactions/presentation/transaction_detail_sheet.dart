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
    final isOwnTransfer = ref
            .watch(flowAnalysisProvider)
            .valueOrNull
            ?.internalIds
            .contains(record.id) ??
        false;

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
                  'Waiting for your review. Not counted in totals yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFE8833A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            _Row(label: 'Category', value: info.label),
            _Row(
              label: 'Type',
              value: isOwnTransfer
                  ? 'Own transfer (money ${isExpense ? 'out' : 'in'})'
                  : isExpense
                      ? 'Expense'
                      : 'Income',
            ),
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
            if (!pending) ...[
              const SizedBox(height: 16),
              _OwnTransferPanel(record: record, hostContext: hostContext),
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

/// Whether this transaction counts as money moving between the user's own
/// accounts, why, and the one tap that corrects it.
class _OwnTransferPanel extends ConsumerWidget {
  const _OwnTransferPanel({required this.record, required this.hostContext});

  final TransactionRecord record;
  final BuildContext hostContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flows = ref.watch(flowAnalysisProvider).valueOrNull;
    if (flows == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isOwn = flows.internalIds.contains(record.id);
    final maybeOwn = flows.suggestedIds.contains(record.id);

    if (isOwn) {
      return _Panel(
        color: kOwnTransferColor,
        icon: Icons.swap_horiz_rounded,
        title: 'Own transfer, not counted as income or spending',
        body: _reasonText(ref, flows),
        actions: [
          TextButton(
            onPressed: () => _answer(
              context,
              ref,
              OwnTransferOverride.notOwn,
              isExpense(record)
                  ? 'Counted as spending again.'
                  : 'Counted as '
                      'income again.',
            ),
            child: const Text('Not my own transfer'),
          ),
        ],
      );
    }
    if (maybeOwn) {
      return _Panel(
        color: const Color(0xFFE8833A),
        icon: Icons.help_outline_rounded,
        title: 'Is this a transfer between your own accounts?',
        body: 'It went ${isExpense(record) ? 'to' : 'from'} a bank or wallet '
            'you also use, but no matching '
            '${isExpense(record) ? 'deposit' : 'withdrawal'} was found. It '
            'counts as ${isExpense(record) ? 'spending' : 'income'} until you '
            'say otherwise.',
        actions: [
          TextButton(
            onPressed: () => _answer(context, ref, OwnTransferOverride.notOwn,
                'Got it. It stays counted.'),
            child: const Text('No'),
          ),
          FilledButton.tonal(
            onPressed: () => _answer(context, ref, OwnTransferOverride.own,
                'Marked as an own transfer.'),
            child: const Text('Yes, my own'),
          ),
        ],
      );
    }
    if (record.ownTransfer == OwnTransferOverride.notOwn) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'You said this isn\'t a transfer between your own accounts.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _answer(
                context, ref, OwnTransferOverride.none, 'Answer cleared.'),
            child: const Text('Undo'),
          ),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _answer(context, ref, OwnTransferOverride.own,
            'Marked as an own transfer.'),
        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
        label: const Text('Mark as transfer between my accounts'),
      ),
    );
  }

  static bool isExpense(TransactionRecord record) => isOutflowType(record.type);

  String _reasonText(WidgetRef ref, FlowAnalysis flows) {
    final out = isExpense(record);
    switch (flows.reasonById[record.id]) {
      case OwnTransferReason.paired:
        final partnerId = flows.partnerById[record.id];
        final partner = partnerId == null
            ? null
            : ref.watch(transactionByIdProvider(partnerId)).valueOrNull;
        if (partner == null) return 'Matched with the other side of the move.';
        final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
        final account = accounts
                .where((a) => a.id == partner.accountId)
                .firstOrNull
                ?.name ??
            partner.accountId;
        final gap = partner.occurredAt.difference(record.occurredAt);
        final fee = flows.pairFeeByOutflowId[out ? record.id : partner.id];
        return 'Matched with '
            '${formatSignedMinorEtb(signedMinorForRecord(partner))} '
            '${out ? 'into' : 'out of'} $account, ${_gapLabel(gap)}.'
            '${fee != null && fee > 0 ? ' The ${formatMinorEtb(fee)} it cost '
                'counts as a bank fee.' : ''}';
      case OwnTransferReason.markedByUser:
        return 'You marked this as a transfer between your own accounts.';
      case OwnTransferReason.ownAccount:
        return out
            ? 'Sent to an account number your bank calls yours.'
            : 'Came from an account number your bank calls yours.';
      case OwnTransferReason.ownName:
        return out
            ? 'Sent to an account in your own name.'
            : 'Came from an account in your own name.';
      case OwnTransferReason.learned:
        return out
            ? 'Same recipient as a transfer you marked as your own.'
            : 'Same sender as a transfer you marked as your own.';
      case OwnTransferReason.savings:
        return 'Categorized as savings: money you keep.';
      case null:
        return '';
    }
  }

  static String _gapLabel(Duration gap) {
    final abs = gap.abs();
    final when = gap.isNegative ? 'earlier' : 'later';
    if (abs.inMinutes < 1) return 'at the same time';
    if (abs.inMinutes < 60) return '${abs.inMinutes} min $when';
    if (abs.inHours < 48) return '${abs.inHours} h $when';
    return '${abs.inDays} days $when';
  }

  Future<void> _answer(
    BuildContext context,
    WidgetRef ref,
    OwnTransferOverride answer,
    String confirmation,
  ) async {
    await ref
        .read(transactionServiceProvider)
        .setOwnTransfer(transactionId: record.id, answer: answer);
    refreshAppData(ref);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    if (!hostContext.mounted) return;
    ScaffoldMessenger.of(hostContext).showSnackBar(
      SnackBar(content: Text(confirmation)),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
    required this.actions,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(body, style: theme.textTheme.bodySmall),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(spacing: 8, children: actions),
          ),
        ],
      ),
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
