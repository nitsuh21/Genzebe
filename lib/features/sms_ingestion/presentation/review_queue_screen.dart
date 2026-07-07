import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/core/logging/app_logger.dart';
import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/features/ai/presentation/ai_cleanup_sheet.dart';
import 'package:genzeb/features/sms_ingestion/application/account_mapping_service.dart';
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

  Future<void> _runForceSync({
    String? payload,
    required bool syncAllMappings,
    required Set<String> selectedMappingSenderPatterns,
  }) async {
    setState(() => _syncing = true);
    final result = await ref.read(syncServiceProvider).forceSyncFromSms(
          importedRawPayload: payload,
          syncAllMappings: syncAllMappings,
          selectedMappingSenderPatterns: selectedMappingSenderPatterns,
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
          'Device ${result.deviceMatchedMappings}/${result.deviceFetched} '
          '(rules ${result.mappingRuleCount}) • imported ${result.importedCount} • '
          'processed ${result.processed} • parsed ${result.newlyParsed} • '
          'pending ${result.pendingReview} • dup ${result.duplicates} • failed ${result.failed}',
        ),
      ),
    );
  }

  Future<void> _openAndRunForceSync({String? payload}) async {
    final selection = await _openSyncSelectionDialog(context, ref);
    if (!mounted || selection == null) return;
    await _runForceSync(
      payload: payload,
      syncAllMappings: selection.syncAllMappings,
      selectedMappingSenderPatterns: selection.selectedMappingSenderPatterns,
    );
  }

  Future<void> _showPermissionDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('SMS permission required'),
          content: const Text(
            'Genzeb needs SMS permission to read your device inbox for '
            'mapping and force sync. Please allow SMS access in Settings.',
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
            'SMS Automation',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Turn bank & wallet SMS into clean transactions, automatically.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _SyncCard(
            syncing: _syncing,
            onForceSync: _syncing ? null : () => _openAndRunForceSync(),
            onImport: _syncing
                ? null
                : () async {
                    final payload = await _openManualImportDialog(context);
                    if (!mounted || payload == null || payload.trim().isEmpty) {
                      return;
                    }
                    await _openAndRunForceSync(payload: payload);
                  },
          ),
          const SizedBox(height: 14),
          _StatStrip(
            parsed: parsedCount,
            pending: reviewCount,
            total: stored.length,
          ),
          const SizedBox(height: 14),
          _AiCleanupCard(onTap: () => showAiCleanupSheet(context)),
          const SizedBox(height: 16),
          _CollapsibleCard(
            icon: Icons.account_tree_outlined,
            title: 'Institution mapping',
            subtitle: 'Link SMS senders to your accounts',
            initiallyExpanded: true,
            child: const _MappingManager(),
          ),
          const SizedBox(height: 12),
          _CollapsibleCard(
            icon: Icons.rule_rounded,
            title: 'Pending review',
            subtitle: 'Low-confidence messages to confirm',
            badge: reviewCount > 0 ? '$reviewCount' : null,
            child: reviewAsync.when(
              loading: () => const _LoadingCard(),
              error: (e, _) => _InfoCard(text: 'Error: $e'),
              data: (queue) {
                if (queue.isEmpty) {
                  return const _InfoCard(
                    text: 'Nothing waiting. Auto-parsed SMS post directly to '
                        'your ledger.',
                  );
                }
                return Column(
                  children: queue
                      .map((item) => _ReviewTile(
                            item: item,
                            onApprove: (categoryOverride) async {
                              await ref
                                  .read(smsIngestionServiceProvider)
                                  .approveReviewItem(
                                    item,
                                    categoryOverride: categoryOverride,
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
            icon: Icons.history_rounded,
            title: 'Recent activity',
            subtitle: 'Latest ingested messages',
            child: storedAsync.when(
              loading: () => const _LoadingCard(),
              error: (e, _) => _InfoCard(text: 'Error: $e'),
              data: (items) {
                if (items.isEmpty) {
                  return const _InfoCard(text: 'No SMS ingested yet.');
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
            title: 'Diagnostics',
            subtitle: 'Pipeline logs for troubleshooting',
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
            label: 'Parsed',
            value: '$parsed',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF2E9E6B),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Pending',
            value: '$pending',
            icon: Icons.rule_rounded,
            color: const Color(0xFFE8833A),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Ingested',
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
                'Force sync & re-parse',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Re-scan device SMS, re-run the parser, and backfill the ledger '
            'safely (no duplicates). Or paste SMS manually.',
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
                        : const Text('Force Sync'),
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
                    child: Text('Import SMS'),
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

class _AiCleanupCard extends StatelessWidget {
  const _AiCleanupCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
            color: theme.colorScheme.primary.withValues(alpha: 0.06),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.auto_fix_high_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI category cleanup',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Let Genzeb AI fix wrong categories and income/expense '
                      'mix-ups. You approve every change.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _MappingManager extends ConsumerStatefulWidget {
  const _MappingManager();

  @override
  ConsumerState<_MappingManager> createState() => _MappingManagerState();
}

class _MappingManagerState extends ConsumerState<_MappingManager> {
  final _senderController = TextEditingController();
  final _accountController = TextEditingController();
  EthiopianInstitution _institution = EthiopianInstitution.cbe;
  List<String> _availableSenders = const [];
  bool _loadingSenders = false;

  @override
  void initState() {
    super.initState();
    _loadSenderCandidates();
  }

  @override
  void dispose() {
    _senderController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final sender = _senderController.text.trim();
    final account = _accountController.text.trim();
    if (sender.isEmpty || account.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both sender and account.')),
      );
      return;
    }
    await ref.read(accountMappingServiceProvider).saveMapping(
          AccountMapping(
            senderPattern: sender,
            accountId: account.toLowerCase().replaceAll(' ', '-'),
            accountName: account,
            institution: _institution,
          ),
        );
    refreshAppData(ref);
    if (!mounted) return;
    _senderController.clear();
    _accountController.clear();
    setState(() {});
  }

  Future<void> _deleteMapping(String senderPattern) async {
    await ref.read(accountMappingServiceProvider).deleteMapping(senderPattern);
    refreshAppData(ref);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted mapping for "$senderPattern".')),
    );
  }

  Future<void> _showPermissionDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('SMS permission required'),
          content: const Text(
            'Genzeb needs SMS permission to read your device inbox for '
            'mapping and force sync. Please allow SMS access in Settings.',
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

  Future<void> _loadSenderCandidates() async {
    setState(() => _loadingSenders = true);
    final permission =
        await ref.read(deviceSmsSourceProvider).ensurePermission();
    if (!mounted) return;
    if (permission != SmsPermissionState.granted) {
      setState(() {
        _availableSenders = const [];
        _loadingSenders = false;
      });
      await _showPermissionDialog(context);
      return;
    }
    final twoYearsAgo = DateTime.now().subtract(const Duration(days: 365 * 2));
    final messages = await ref
        .read(deviceSmsSourceProvider)
        .fetchRecentMessages(since: twoYearsAgo);
    final counts = <String, int>{};
    for (final message in messages) {
      final sender = message.sender.trim();
      if (sender.isEmpty) continue;
      counts.update(sender, (value) => value + 1, ifAbsent: () => 1);
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });
    if (!mounted) return;
    setState(() {
      _availableSenders = sorted.map((entry) => entry.key).toList();
      _loadingSenders = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick sender from your real SMS inbox and map it to institution/account.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Autocomplete<String>(
                  optionsBuilder: (value) {
                    final query = value.text.trim().toLowerCase();
                    if (query.isEmpty) {
                      return _availableSenders.take(12);
                    }
                    return _availableSenders.where(
                      (sender) => sender.toLowerCase().contains(query),
                    );
                  },
                  onSelected: (selection) {
                    _senderController.text = selection;
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onEditingComplete) {
                    if (controller.text != _senderController.text) {
                      controller.value = _senderController.value;
                    }
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onEditingComplete: onEditingComplete,
                      onChanged: (value) {
                        _senderController.value = TextEditingValue(
                          text: value,
                          selection:
                              TextSelection.collapsed(offset: value.length),
                        );
                      },
                      decoration: const InputDecoration(
                        labelText: 'Sender pattern',
                        hintText: 'Search sender (e.g. CBE, AWASH)',
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _loadingSenders ? null : _loadSenderCandidates,
                tooltip: 'Refresh senders',
                icon: _loadingSenders
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (_availableSenders.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${_availableSenders.length} sender(s) found in last 2 years',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else if (!_loadingSenders) ...[
            const SizedBox(height: 6),
            Text(
              'No inbox senders found yet. Check SMS permission and refresh.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _accountController,
            decoration: const InputDecoration(
              labelText: 'Account name',
              hintText: 'e.g. CBE Main',
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<EthiopianInstitution>(
            initialValue: _institution,
            decoration: const InputDecoration(labelText: 'Institution'),
            items: EthiopianInstitution.values
                .where((i) => i != EthiopianInstitution.unknown)
                .map(
                  (i) => DropdownMenuItem(
                    value: i,
                    child: Text(_institutionLabel(i)),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _institution = value);
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.add_link_rounded),
              label: const Text('Save mapping'),
            ),
          ),
          FutureBuilder<List<AccountMapping>>(
            future: ref.read(accountMappingServiceProvider).getMappings(),
            builder: (context, snapshot) {
              final mappings = snapshot.data ?? const <AccountMapping>[];
              if (mappings.isEmpty) return const SizedBox.shrink();
              return Column(
                children: [
                  const Divider(height: 26),
                  ...mappings.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.link_rounded,
                              size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${m.senderPattern}  →  ${m.accountName}',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            _institutionLabel(m.institution),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete mapping',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => _deleteMapping(m.senderPattern),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String _institutionLabel(EthiopianInstitution i) {
  switch (i) {
    case EthiopianInstitution.cbe:
      return 'CBE';
    case EthiopianInstitution.awash:
      return 'Awash';
    case EthiopianInstitution.telebirr:
      return 'Telebirr';
    case EthiopianInstitution.boa:
      return 'Abyssinia';
    case EthiopianInstitution.hibret:
      return 'Hibret';
    case EthiopianInstitution.dashen:
      return 'Dashen';
    case EthiopianInstitution.unknown:
      return 'Unknown';
  }
}

class _ReviewTile extends StatefulWidget {
  const _ReviewTile({
    required this.item,
    required this.onApprove,
    required this.onReject,
  });

  final SmsReviewItem item;
  final ValueChanged<String?> onApprove;
  final VoidCallback onReject;

  @override
  State<_ReviewTile> createState() => _ReviewTileState();
}

class _ReviewTileState extends State<_ReviewTile> {
  String? _categoryOverride;

  SmsReviewItem get item => widget.item;

  Future<void> _pickCategory() async {
    final selected = await showCategoryPicker(
      context,
      isExpense: item.parsed.detectedAmountMinor < 0,
      current: _categoryOverride ?? item.parsed.categoryHint,
    );
    if (selected != null) {
      setState(() => _categoryOverride = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info =
        categoryInfoFor(_categoryOverride ?? item.parsed.categoryHint);
    final amount = item.parsed.detectedAmountMinor.abs();
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
          Row(
            children: [
              Text(
                item.smsMessage.sender,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              // Tappable: fix the category before approving; the correction
              // is remembered for this merchant on future syncs.
              InkWell(
                onTap: _pickCategory,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 3),
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
              const Spacer(),
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (item.parsed.detectedAmountMinor < 0
                          ? const Color(0xFFEF6C5A)
                          : const Color(0xFF2E9E6B))
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.parsed.detectedAmountMinor < 0 ? 'Expense' : 'Income',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: item.parsed.detectedAmountMinor < 0
                        ? const Color(0xFFEF6C5A)
                        : const Color(0xFF2E9E6B),
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
          const SizedBox(height: 8),
          Text(
            item.smsMessage.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Confidence ${(item.parsed.confidence * 100).toStringAsFixed(0)}%',
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
                onPressed: () => widget.onApprove(_categoryOverride),
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

class _SyncSelection {
  const _SyncSelection({
    required this.syncAllMappings,
    required this.selectedMappingSenderPatterns,
  });

  final bool syncAllMappings;
  final Set<String> selectedMappingSenderPatterns;
}

Future<_SyncSelection?> _openSyncSelectionDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final mappings = await ref.read(accountMappingServiceProvider).getMappings();
  if (!context.mounted) return null;
  var syncAllMappings = true;
  final selected = mappings.map((m) => m.senderPattern).toSet();

  return showDialog<_SyncSelection>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Select mappings to sync'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: syncAllMappings,
                  onChanged: (value) => setState(() => syncAllMappings = value),
                  title: const Text('Sync all mappings'),
                  subtitle: Text(
                    syncAllMappings
                        ? 'All mappings are selected'
                        : 'Choose specific mappings below',
                  ),
                ),
                if (mappings.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'No mappings found. Sync will include all device messages.',
                    ),
                  )
                else if (!syncAllMappings)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: SingleChildScrollView(
                      child: Column(
                        children: mappings
                            .map(
                              (mapping) => CheckboxListTile(
                                dense: true,
                                value: selected.contains(mapping.senderPattern),
                                contentPadding: EdgeInsets.zero,
                                title: Text(mapping.accountName),
                                subtitle: Text(
                                  '${mapping.senderPattern} • ${_institutionLabel(mapping.institution)}',
                                ),
                                onChanged: (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      selected.add(mapping.senderPattern);
                                    } else {
                                      selected.remove(mapping.senderPattern);
                                    }
                                  });
                                },
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(
                    _SyncSelection(
                      syncAllMappings: syncAllMappings,
                      selectedMappingSenderPatterns: selected,
                    ),
                  );
                },
                child: const Text('Sync now'),
              ),
            ],
          );
        },
      );
    },
  );
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
