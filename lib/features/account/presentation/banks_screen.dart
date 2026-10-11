import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/design_system/institution_avatar.dart';

/// Every bank and wallet found in the inbox, each with a switch.
class BanksScreen extends ConsumerWidget {
  const BanksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final strings = ref.watch(stringsProvider);
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    return Scaffold(
      appBar: AppBar(title: Text(strings.banksTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 28 + safeBottom),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
            child: Text(
              strings.banksSettingsBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const InstitutionSwitchList(),
        ],
      ),
    );
  }
}

/// One switch per bank or wallet. Off removes its transactions and skips
/// its messages on every sync from then on; on reads its history back from
/// the inbox.
class InstitutionSwitchList extends ConsumerStatefulWidget {
  const InstitutionSwitchList({super.key, this.framed = true});

  /// False when the host already draws a card around it.
  final bool framed;

  @override
  ConsumerState<InstitutionSwitchList> createState() =>
      _InstitutionSwitchListState();
}

class _InstitutionSwitchListState extends ConsumerState<InstitutionSwitchList> {
  /// Institutions whose transactions are being removed or read back.
  final _busy = <String>{};

  Future<void> _set(InstitutionSighting sighting, bool on) async {
    final strings = ref.read(stringsProvider);
    final info = sighting.info;
    if (!on && sighting.hasTransactions) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.banksTurnOffTitle(info.shortName)),
          content: Text(strings.banksTurnOffBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.banksTurnOff),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _busy.add(info.code));
    try {
      await ref.read(excludedInstitutionsProvider.notifier).setIncluded(
            info.id,
            on,
          );
    } finally {
      if (mounted) setState(() => _busy.remove(info.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = ref.watch(stringsProvider);
    final found = ref.watch(institutionsSeenProvider).valueOrNull;
    if (found == null) return const SizedBox.shrink();
    if (found.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Text(
          strings.banksNoneFound,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final rows = Column(
      children: [
        for (var i = 0; i < found.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: widget.framed ? 68 : 52),
          _row(found[i], theme),
        ],
      ],
    );
    if (!widget.framed) return rows;
    return Material(
      color: theme.cardTheme.color,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: rows,
    );
  }

  Widget _row(InstitutionSighting sighting, ThemeData theme) {
    final strings = ref.watch(stringsProvider);
    final on = !sighting.excluded;
    final busy = _busy.contains(sighting.info.code);
    final subtitle = !on
        ? strings.banksOff
        : sighting.hasTransactions
            ? strings.transactionCount(sighting.transactionCount)
            : strings.banksNoTransactions;
    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: widget.framed ? 16 : 0,
        vertical: 2,
      ),
      onTap: busy ? null : () => _set(sighting, !on),
      leading: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: on ? 1 : 0.4,
        child: InstitutionAvatar(info: sighting.info, size: 36),
      ),
      title: Text(
        sighting.info.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: on ? null : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: busy
          ? const SizedBox(
              width: 52,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Switch(
              value: on,
              onChanged: (value) => _set(sighting, value),
            ),
    );
  }
}

/// Up to three logos of the banks and wallets in use, overlapped, for the
/// Profile row.
class InstitutionLogoStack extends ConsumerWidget {
  const InstitutionLogoStack({super.key});

  static const _size = 26.0;
  static const _step = 18.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final found = ref.watch(institutionsSeenProvider).valueOrNull ?? const [];
    final shown = [
      for (final sighting in found)
        if (!sighting.excluded) sighting,
    ]..sort((a, b) => b.transactionCount.compareTo(a.transactionCount));
    final logos = shown.take(3).toList(growable: false);
    if (logos.isEmpty) return const SizedBox.shrink();
    final ring = Theme.of(context).cardTheme.color ??
        Theme.of(context).colorScheme.surface;
    return SizedBox(
      width: _size + _step * (logos.length - 1),
      height: _size,
      child: Stack(
        children: [
          for (var i = logos.length - 1; i >= 0; i--)
            Positioned(
              left: i * _step,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: ring,
                  borderRadius: BorderRadius.circular(_size * 0.36),
                ),
                child: InstitutionAvatar(
                  info: logos[i].info,
                  size: _size - 3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
