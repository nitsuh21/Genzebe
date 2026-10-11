import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/core/l10n/app_strings.dart';
import 'package:genzeb/design_system/institution_avatar.dart';
import 'package:genzeb/features/account/presentation/onboarding_widgets.dart';

/// First-launch welcome: the banks and wallets people already use, gathered
/// around the Genzeb coin. SMS setup follows; no account is needed.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final isAmharic = identical(strings, amStrings);

    return OnboardingPage(
      // Each language is offered in its own script, so someone who can't
      // read the current one still finds theirs.
      topBar: Row(
        children: [
          Text(
            'Genzeb',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
          ),
          const Spacer(),
          OnboardingTextButton(
            label: isAmharic ? 'English' : 'አማርኛ',
            onPressed: () => ref
                .read(appLanguageProvider.notifier)
                .setLanguage(isAmharic ? 'en' : 'am'),
          ),
        ],
      ),
      picture: const _BankRing(),
      title: strings.onbTitle,
      body: strings.onbBody,
      actions: OnboardingButton(
        label: strings.onbGetStarted,
        onPressed: () => ref.read(introSeenProvider.notifier).markDone(),
      ),
    );
  }
}

/// Well-known banks and wallets, in the order they sit around the coin.
const _ringCodes = [
  'cbe',
  'telebirr',
  'awash',
  'dashen',
  'boa',
  'coop',
  'hibret',
  'wegagen',
  'zemen',
  'mpesa',
];

class _BankRing extends StatefulWidget {
  const _BankRing();

  @override
  State<_BankRing> createState() => _BankRingState();
}

class _BankRingState extends State<_BankRing>
    with SingleTickerProviderStateMixin, OnboardingEntrance {
  @override
  Duration get entranceDuration => const Duration(milliseconds: 1500);

  late final _coin = phase(0, 0.45, curve: Curves.easeOutBack);
  late final _coinFade = phase(0, 0.25);
  late final _orbit = phase(0.55, 1);
  // The logos close in from outside, one after another, and settle in a
  // ring: many accounts, one place.
  late final _logos = [
    for (var i = 0; i < _ringCodes.length; i++)
      phase(0.2 + i * 0.04, 0.62 + i * 0.04),
  ];

  static const _side = 356.0;
  static const _tile = _side * 0.15;
  static const _ring = _side / 2 - _tile / 2;
  static const _coinSize = _side * 0.44;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: entrance,
      builder: (context, _) => SizedBox.square(
        dimension: _side,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The orbit the logos settle on.
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(_tile / 2),
                child: Opacity(
                  opacity: _orbit.value,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(
                        BorderSide(color: Color(0x24FFFFFF)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            for (var i = 0; i < _ringCodes.length; i++)
              _placed(
                angle: -math.pi / 2 + i * 2 * math.pi / _ringCodes.length,
                radius: _ring * (1.45 - 0.45 * _logos[i].value),
                child: Opacity(
                  opacity: _logos[i].value.clamp(0.0, 1.0),
                  child: InstitutionAvatar.forCode(_ringCodes[i], size: _tile),
                ),
              ),
            Center(
              child: Opacity(
                opacity: _coinFade.value,
                child: Transform.scale(
                  scale: 0.7 + 0.3 * _coin.value,
                  child: ClipOval(
                    child: Image.asset(
                      'assets/brand/coin.png',
                      width: _coinSize,
                      height: _coinSize,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placed({
    required double angle,
    required double radius,
    required Widget child,
  }) {
    const center = _side / 2;
    return Positioned(
      left: center + radius * math.cos(angle) - _tile / 2,
      top: center + radius * math.sin(angle) - _tile / 2,
      width: _tile,
      height: _tile,
      child: child,
    );
  }
}
