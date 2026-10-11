import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/design_system/institution_avatar.dart';
import 'package:genzeb/design_system/theme.dart';
import 'package:genzeb/features/account/presentation/onboarding_widgets.dart';
import 'package:genzeb/features/alerts/presentation/notification_permission.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/device_sms_source.dart';

/// One-time onboarding step and the SMS permission's prominent disclosure:
/// say what is read and what is skipped, then run the first import so the
/// dashboard isn't empty.
class SmsSetupScreen extends ConsumerStatefulWidget {
  const SmsSetupScreen({super.key});

  @override
  ConsumerState<SmsSetupScreen> createState() => _SmsSetupScreenState();
}

class _SmsSetupScreenState extends ConsumerState<SmsSetupScreen> {
  bool _importing = false;

  Future<void> _connectAndImport() async {
    setState(() => _importing = true);
    try {
      final result = await ref.read(syncServiceProvider).forceSyncFromSms();
      refreshAppData(ref);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (result.smsPermissionState != SmsPermissionState.granted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'SMS access is off. You can add transactions yourself, or '
              'turn it on later in Profile.',
            ),
          ),
        );
      } else {
        final banks = result.institutionsFound.length;
        final found = result.newTransactions.length;
        final pending = result.pendingReview;
        messenger.showSnackBar(
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
      }
      if (result.smsPermissionState == SmsPermissionState.granted) {
        await askForNotificationPermissionOnce();
      }
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
    return OnboardingPage(
      picture: _InboxSketch(skippedLabel: strings.smsSkipped),
      title: strings.smsTitle,
      body: strings.smsBody,
      actions: Column(
        children: [
          OnboardingButton(
            label: strings.smsAllow,
            busy: _importing,
            onPressed: _connectAndImport,
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

