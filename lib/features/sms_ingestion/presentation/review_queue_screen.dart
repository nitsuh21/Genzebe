import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/core/logging/app_logger.dart';
import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/design_system/institution_avatar.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/device_sms_source.dart';
import 'package:genzeb/features/transactions/domain/models/categories.dart';
import 'package:genzeb/features/transactions/presentation/category_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class ReviewQueueScreen extends ConsumerStatefulWidget {
  const ReviewQueueScreen({super.key});

  @override
  ConsumerState<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends ConsumerState<ReviewQueueScreen> {
  bool _syncing = false;

  Future<void> _runForceSync({String? payload}) async {
    setState(() => _syncing = true);
    final result = await ref.read(syncServiceProvider).forceSyncFromSms(
          importedRawPayload: payload,
          incremental: payload == null,
        );
    refreshAppData(ref);
    if (!mounted) return;
    setState(() => _syncing = false);
    if (result.smsPermissionState != SmsPermissionState.granted) {
      await _showPermissionDialog(context);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.newTransactions.isEmpty
              ? 'Up to date — no new bank or wallet transactions.'
              : '${result.newTransactions.length} new transaction'
                  '${result.newTransactions.length == 1 ? '' : 's'} from '
                  '${result.institutionsFound.length} bank'
                  '${result.institutionsFound.length == 1 ? '' : 's'}/wallets'
                  '${result.pendingReview > 0 ? ' · ${result.pendingReview} to review' : ''}.',
        ),
      ),
    );
  }

  Future<void> _reparseHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Re-check history?'),
        content: const Text(
          'Every saved message is read again with the latest rules and '
          'your corrections — amounts, directions and categories are '
          'recalculated. Category edits you made without teaching a rule '
          'may be recomputed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Re-check'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _syncing = true);
    final changed =
        await ref.read(smsIngestionServiceProvider).reparseAllStoredMessages();
    refreshAppData(ref);
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          changed == 0
              ? 'History already matches the latest parser.'
              : 'Re-parsed history — $changed transaction'
                  '${changed == 1 ? '' : 's'} corrected.',
        ),
      ),
    );
  }

  Future<void> _showPermissionDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('SMS permission required'),
          content: const Text(
            'Genzeb needs SMS permission to read messages from your banks '
            'and wallets. Please allow SMS access in Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () async {
                await openAppSettings();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reviewAsync = ref.watch(reviewQueueProvider);
    final storedAsync = ref.watch(storedSmsProvider);
    final reviewCount = reviewAsync.valueOrNull?.length ?? 0;
    final stored = storedAsync.valueOrNull ?? const <StoredSmsMessage>[];
    final parsedCount =
        stored.where((s) => s.status == SmsIngestionStatus.parsed).length;
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;

    return RefreshIndicator(
      onRefresh: () async => refreshAppData(ref),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 28 + safeBottom + 84),
        children: [
          Text(
            'SMS sync',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Your bank and wallet messages become transactions here. '
            'Anything Genzeb is unsure about waits for you below.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _SyncCard(
            syncing: _syncing,
            onForceSync: _syncing ? null : () => _runForceSync(),
            onImport: _syncing
                ? null
                : () async {
                    final payload = await _openManualImportDialog(context);
                    if (!mounted || payload == null || payload.trim().isEmpty) {
                      return;
                    }
                    await _runForceSync(payload: payload);
                  },
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton.icon(
              onPressed: _syncing ? null : _reparseHistory,
              icon: const Icon(Icons.history_rounded, size: 16),
              label: const Text('Re-check history with the latest rules'),
            ),
          ),
          const SizedBox(height: 6),
          _StatStrip(
            parsed: parsedCount,
            pending: reviewCount,
            total: stored.length,
          ),
          const SizedBox(height: 16),
          _CollapsibleCard(
            icon: Icons.rule_rounded,
            title: 'Needs your review',
            subtitle: 'Confirm what Genzeb was not sure about',
            initiallyExpanded: true,
            badge: reviewCount > 0 ? '$reviewCount' : null,
            child: reviewAsync.when(
              loading: () => const _LoadingCard(),
              error: (e, _) => _InfoCard(text: 'Error: $e'),
              data: (queue) {
                if (queue.isEmpty) {
                  return const _InfoCard(
                    text: 'Nothing waiting. Messages Genzeb is sure about '
                        'go straight to your ledger.',
                  );
                }
                return Column(
                  children: queue
                      .map((item) => _ReviewTile(
                            item: item,
                            onApprove: (categoryOverride, makeExpense) async {
                              await ref
                                  .read(smsIngestionServiceProvider)
                                  .approveReviewItem(
                                    item,
                                    categoryOverride: categoryOverride,
                                    makeExpense: makeExpense,
                                  );
                              refreshAppData(ref);
                            },
                            onReject: () async {
                              await ref
                                  .read(smsIngestionServiceProvider)
                                  .rejectReviewItem(item);
                              refreshAppData(ref);
                            },
                          ))
                      .toList(growable: false),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _CollapsibleCard(
            icon: Icons.account_balance_outlined,
            title: 'Banks & wallets found',
            subtitle: 'Synced automatically from your inbox',
            initiallyExpanded: true,
            child: const _InstitutionsFound(),
          ),
          const SizedBox(height: 12),
          _CollapsibleCard(
            icon: Icons.history_rounded,
            title: 'Messages read',
            subtitle: 'The latest SMS Genzeb processed',
            child: storedAsync.when(
              loading: () => const _LoadingCard(),
              error: (e, _) => _InfoCard(text: 'Error: $e'),
              data: (items) {
                if (items.isEmpty) {
                  return const _InfoCard(text: 'No messages read yet.');
                }
                return Column(
                  children: items
                      .take(12)
                      .map((entry) => _LogTile(entry: entry))
                      .toList(growable: false),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _CollapsibleCard(
            icon: Icons.terminal_rounded,
            title: 'Advanced',
            subtitle: 'Logs for troubleshooting',
            child: const _DiagnosticsPanel(),
          ),
        ],
      ),
    );
  }
}

class _StatStrip extends StatelessWidget {
  const _StatStrip({
    required this.parsed,
    required this.pending,
    required this.total,
  });

  final int parsed;
  final int pending;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Booked',
            value: '$parsed',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF2E9E6B),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'To review',
            value: '$pending',
            icon: Icons.rule_rounded,
            color: const Color(0xFFE8833A),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Messages read',
            value: '$total',
            icon: Icons.sms_rounded,
            color: const Color(0xFF4E5AE8),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsibleCard extends StatelessWidget {
  const _CollapsibleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.badge,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final String? badge;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 20),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8833A),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          children: [child],
        ),
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({
    required this.syncing,
    required this.onForceSync,
    required this.onImport,
  });

  final bool syncing;
  final VoidCallback? onForceSync;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF4E5AE8), Color(0xFF7A5AE0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                'Refresh from SMS',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Read your inbox again and update the ledger — nothing is '
            'duplicated. You can also paste messages by hand.',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: onForceSync,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Refresh now'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: onImport,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('Paste SMS'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Every bank and wallet Genzeb has seen in the inbox. Nothing to set up:
/// a new institution appears here the first time one of its messages does.
class _InstitutionsFound extends ConsumerWidget {
  const _InstitutionsFound();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final found = ref.watch(institutionsSeenProvider).valueOrNull ?? const [];
    if (found.isEmpty) {
      return _InfoCard(
        text: 'No bank or wallet messages yet. Genzeb recognises '
            '${kInstitutions.length} Ethiopian banks and wallets — CBE, '
            'telebirr, Awash, Dashen, Abyssinia, M-PESA and more.',
      );
    }
    final quiet = found.where((f) => !f.hasTransactions).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final sighting in found)
              Opacity(
                opacity: sighting.hasTransactions ? 1 : 0.55,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InstitutionAvatar(info: sighting.info, size: 26),
                      const SizedBox(width: 8),
                      Text(
                        sighting.info.shortName,
                        style: theme.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (quiet > 0) ...[
          const SizedBox(height: 10),
          Text(
            'Faded: messages found, but only notices or promotions so far — '
            'their transactions will appear as soon as one arrives.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ReviewTile extends StatefulWidget {
  const _ReviewTile({
    required this.item,
    required this.onApprove,
    required this.onReject,
  });

  final SmsReviewItem item;

  /// (category override, direction override) — null means "as parsed".
  final void Function(String? categoryOverride, bool? makeExpense) onApprove;
  final VoidCallback onReject;

  @override
  State<_ReviewTile> createState() => _ReviewTileState();
}

class _ReviewTileState extends State<_ReviewTile> {
  String? _categoryOverride;
  bool? _expenseOverride;

  SmsReviewItem get item => widget.item;

  bool get _isExpense =>
      _expenseOverride ?? item.parsed.detectedAmountMinor < 0;

  /// Tapping the Expense/Income pill flips the direction; the category
  /// falls back to the bare bucket because category ids are per-direction.
  void _flipDirection() {
    setState(() {
      _expenseOverride = !_isExpense;
      _categoryOverride = _isExpense ? 'expense' : 'income';
    });
  }

  Future<void> _pickCategory() async {
    final selected = await showCategoryPicker(
      context,
      isExpense: _isExpense,
      current: _categoryOverride ?? item.parsed.categoryHint,
    );
    if (selected != null) {
      setState(() => _categoryOverride = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = categoryInfoFor(_categoryOverride ?? item.parsed.categoryHint);
    final amount = item.parsed.detectedAmountMinor.abs();
    final directionColor =
        _isExpense ? const Color(0xFFEF6C5A) : const Color(0xFF2E9E6B);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: sender + direction + amount. The category chip gets its
          // own line below so long sender IDs or labels can never push the
          // amount off-screen.
          Row(
            children: [
              Expanded(
                child: Text(
                  item.smsMessage.sender,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Tappable: flip income/expense when the parser read it wrong.
              InkWell(
                onTap: _flipDirection,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: directionColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isExpense ? 'Expense' : 'Income',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: directionColor,
                        ),
                      ),
                      Icon(Icons.swap_horiz_rounded,
                          size: 14, color: directionColor),
                    ],
                  ),
                ),
              ),
              Text(
                formatMinorEtb(amount),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Tappable: fix the category before approving; the correction
          // is remembered for this merchant on future syncs.
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: _pickCategory,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: info.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(info.icon, color: info.color, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      info.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: info.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_drop_down_rounded,
                        color: info.color, size: 16),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.smsMessage.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          // Why this landed here, so the user knows what to double-check.
          Text(
            [
              'Confidence ${(item.parsed.confidence * 100).toStringAsFixed(0)}%',
              ...?item.parsed.evidence?.reviewReasons,
            ].join(' • '),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.onReject,
                child: const Text('Reject'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () =>
                    widget.onApprove(_categoryOverride, _expenseOverride),
                child: const Text('Approve'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final StoredSmsMessage entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon, label) = _statusStyle(entry.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.sms.sender} • $label',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.sms.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (entry.ingestedAt != null)
            Text(
              formatTime(entry.ingestedAt!),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  (Color, IconData, String) _statusStyle(SmsIngestionStatus status) {
    switch (status) {
      case SmsIngestionStatus.parsed:
        return (const Color(0xFF2E9E6B), Icons.check_circle_rounded, 'Parsed');
      case SmsIngestionStatus.pendingReview:
        return (const Color(0xFFE8833A), Icons.rule_rounded, 'Pending review');
      case SmsIngestionStatus.rejected:
        return (const Color(0xFFE25555), Icons.block_rounded, 'Rejected');
      case SmsIngestionStatus.failed:
        return (const Color(0xFFE25555), Icons.error_rounded, 'Failed');
      case SmsIngestionStatus.duplicate:
        return (const Color(0xFF8A8FA3), Icons.copy_rounded, 'Duplicate');
      case SmsIngestionStatus.pending:
        return (const Color(0xFF8A8FA3), Icons.schedule_rounded, 'Pending');
    }
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _DiagnosticsPanel extends StatelessWidget {
  const _DiagnosticsPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ValueListenableBuilder<List<AppLogEntry>>(
        valueListenable: AppLogger.logs,
        builder: (context, logs, _) {
          if (logs.isEmpty) {
            return Text(
              'No diagnostics yet. Run Force Sync to see pipeline logs.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            );
          }

          final recent = logs.reversed.take(20).toList(growable: false);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${recent.length} recent log(s)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: AppLogger.clear,
                    icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                    label: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...recent.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '[${formatTime(entry.at)}] ${entry.tag}: ${entry.message}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

Future<String?> _openManualImportDialog(BuildContext context) async {
  final controller = TextEditingController();
  final output = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Manual SMS Import'),
        content: TextField(
          controller: controller,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'One line per SMS.\nFormat: SENDER|message body',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Run'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return output;
}
