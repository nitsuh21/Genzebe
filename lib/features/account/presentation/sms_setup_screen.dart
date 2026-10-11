import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/design_system/institution_avatar.dart';
import 'package:genzeb/design_system/theme.dart';
import 'package:genzeb/features/account/presentation/onboarding_widgets.dart';
import 'package:genzeb/features/alerts/presentation/notification_permission.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/device_sms_source.dart';
import 'package:genzeb/features/sync/application/sync_service.dart';

/// One-time onboarding step and the SMS permission's prominent disclosure:
/// say what is read and what is skipped, show the banks and wallets found
/// so the user can leave some out, then run the first import so the
/// dashboard isn't empty. Nothing is stored before that choice.
class SmsSetupScreen extends ConsumerStatefulWidget {
  const SmsSetupScreen({super.key});

  @override
  ConsumerState<SmsSetupScreen> createState() => _SmsSetupScreenState();
}

class _SmsSetupScreenState extends ConsumerState<SmsSetupScreen> {
  bool _importing = false;

  /// The inbox as read before importing; null until SMS access is given.
  InboxScan? _scan;
  Set<EthiopianInstitution> _included = const {};

  Future<void> _allowAndScan() async {
    setState(() => _importing = true);
    try {
      final scan = await ref.read(syncServiceProvider).scanInbox();
      if (!mounted) return;
      if (scan.permission != SmsPermissionState.granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'SMS access is off. You can add transactions yourself, or '
              'turn it on later in Profile.',
            ),
          ),
        );
        await ref.read(smsSetupDoneProvider.notifier).markDone();
        return;
      }
      final found = scan.institutions;
      if (found.isEmpty) {
        // Nothing to choose from; the import just records the first sync.
        await _import(scan);
        return;
      }
      setState(() {
        _scan = scan;
        _included = {for (final (id, _) in found) id};
      });
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _toggle(EthiopianInstitution id) {
    setState(() {
      _included = _included.contains(id)
          ? ({..._included}..remove(id))
          : {..._included, id};
    });
  }

  Future<void> _import(InboxScan scan) async {
    setState(() => _importing = true);
    try {
      await ref.read(excludedInstitutionsProvider.notifier).replaceAll({
        for (final (id, _) in scan.institutions)
          if (!_included.contains(id)) id,
      });
      final result = await ref
          .read(syncServiceProvider)
          .forceSyncFromSms(requestPermission: false, scan: scan);
      refreshAppData(ref);
      if (!mounted) return;
      final banks = result.institutionsFound.length;
      final found = result.newTransactions.length;
      final pending = result.pendingReview;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            banks == 0
                ? 'No bank or wallet messages yet. New ones will show up '
                    'here automatically.'
                : 'Found $found transaction${found == 1 ? '' : 's'} from '
                    '${banks == 1 ? '1 bank or wallet' : '$banks banks and wallets'}.'
                    '${pending > 0 ? ' $pending need${pending == 1 ? 's' : ''} your review.' : ''}',
          ),
        ),
      );
      await askForNotificationPermissionOnce();
      await ref.read(smsSetupDoneProvider.notifier).markDone();
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _loadDemoData() async {
    setState(() => _importing = true);
    try {
      final seeded = await ref.read(demoDataServiceProvider).seed();
      refreshAppData(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loaded $seeded sample transactions.'),
        ),
      );
      await ref.read(smsSetupDoneProvider.notifier).markDone();
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final scan = _scan;
    if (scan != null) {
      return OnboardingPage(
        fitPicture: false,
        picture: _BankPicker(
          found: scan.institutions,
          included: _included,
          onToggle: _importing ? null : _toggle,
          messageCount: strings.messageCount,
        ),
        title: strings.banksFoundTitle,
        body: strings.banksFoundBody,
        actions: OnboardingButton(
          label:
              _included.isEmpty ? strings.banksContinue : strings.banksImport,
          busy: _importing,
          onPressed: () => _import(scan),
        ),
      );
    }
    return OnboardingPage(
      picture: _InboxSketch(skippedLabel: strings.smsSkipped),
      title: strings.smsTitle,
      body: strings.smsBody,
      actions: Column(
        children: [
          OnboardingButton(
            label: strings.smsAllow,
            busy: _importing,
            onPressed: _allowAndScan,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OnboardingTextButton(
                label: strings.smsDemo,
                onPressed: _importing ? null : _loadDemoData,
              ),
              const SizedBox(width: 12),
              OnboardingTextButton(
                label: strings.smsLater,
                onPressed: _importing
                    ? null
                    : () => ref.read(smsSetupDoneProvider.notifier).markDone(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _Sender { bank, person, code }

/// An inbox drawn without words: bank and wallet texts get the gold check,
/// a friend's message and a login code are passed over.
class _InboxSketch extends StatefulWidget {
  const _InboxSketch({required this.skippedLabel});

  final String skippedLabel;

  @override
  State<_InboxSketch> createState() => _InboxSketchState();
}

class _InboxSketchState extends State<_InboxSketch>
    with SingleTickerProviderStateMixin, OnboardingEntrance {
  static const _rows = [
    (_Sender.bank, 'cbe', 0.78, 0.46),
    (_Sender.person, null, 0.52, 0.0),
    (_Sender.bank, 'telebirr', 0.66, 0.4),
    (_Sender.code, null, 0.6, 0.0),
  ];

  @override
  Duration get entranceDuration => const Duration(milliseconds: 1300);

  late final _arrive = [
    for (var i = 0; i < _rows.length; i++) phase(i * 0.12, 0.4 + i * 0.12),
  ];
  late final _verdict = [
    for (var i = 0; i < _rows.length; i++)
      phase(0.42 + i * 0.12, 0.62 + i * 0.12, curve: Curves.easeOutBack),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 340,
      child: AnimatedBuilder(
        animation: entrance,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _rows.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Opacity(
                  opacity: _arrive[i].value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, 16 * (1 - _arrive[i].value)),
                    child: _row(i),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(int i) {
    final (sender, code, line1, line2) = _rows[i];
    final isBank = sender == _Sender.bank;
    final ink =
        isBank ? const Color(0xFFDDE0F3) : Colors.white.withValues(alpha: 0.16);
    final verdict = _verdict[i].value;

    final Widget avatar = isBank
        ? InstitutionAvatar.forCode(code, size: 36)
        : Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(36 * 0.3),
            ),
            child: Icon(
              sender == _Sender.person
                  ? Icons.person_rounded
                  : Icons.password_rounded,
              size: 20,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          );

    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: isBank ? Colors.white : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(line1, ink),
                if (line2 > 0) ...[
                  const SizedBox(height: 7),
                  _bar(line2, ink),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (isBank)
            Transform.scale(
              scale: verdict.clamp(0.0, 1.2),
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: kBrandGold,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: kBrandIndigoDeep,
                ),
              ),
            )
          else
            Opacity(
              opacity: verdict.clamp(0.0, 1.0),
              child: Text(
                widget.skippedLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bar(double widthFactor, Color color) => FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
}

/// The banks and wallets found in the inbox, busiest first. Each row reads
/// like the inbox sketch before it: kept ones are white with the gold
/// check, left-out ones fade back.
class _BankPicker extends StatefulWidget {
  const _BankPicker({
    required this.found,
    required this.included,
    required this.onToggle,
    required this.messageCount,
  });

  final List<(EthiopianInstitution, int)> found;
  final Set<EthiopianInstitution> included;
  final ValueChanged<EthiopianInstitution>? onToggle;
  final String Function(int) messageCount;

  @override
  State<_BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends State<_BankPicker>
    with SingleTickerProviderStateMixin, OnboardingEntrance {
  @override
  Duration get entranceDuration => const Duration(milliseconds: 900);

  // Only the first screenful staggers in; the rest are already there.
  late final _arrive = [
    for (var i = 0; i < widget.found.length; i++)
      phase(math.min(i, 6) * 0.08, 0.4 + math.min(i, 6) * 0.08),
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AnimatedBuilder(
          animation: entrance,
          builder: (context, _) => ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: widget.found.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Opacity(
                opacity: _arrive[i].value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, 16 * (1 - _arrive[i].value)),
                  child: _row(widget.found[i]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row((EthiopianInstitution, int) entry) {
    final (id, count) = entry;
    final info = institutionInfo(id);
    final on = widget.included.contains(id);
    final theme = Theme.of(context);
    final onToggle = widget.onToggle;
    return Semantics(
      checked: on,
      label: info.name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle == null ? null : () => onToggle(id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: on ? Colors.white : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: on ? 1 : 0.45,
                child: InstitutionAvatar(info: info, size: 36),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: on
                            ? kBrandIndigoDeep
                            : Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.messageCount(count),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: on
                            ? kBrandIndigoDeep.withValues(alpha: 0.55)
                            : Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: on ? kBrandGold : Colors.transparent,
                  shape: BoxShape.circle,
                  border: on
                      ? null
                      : Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                ),
                child: on
                    ? const Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: kBrandIndigoDeep,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
