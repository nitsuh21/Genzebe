import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/app/router.dart';
import 'package:genzeb/design_system/theme.dart';
import 'package:genzeb/features/account/domain/models/account_models.dart';
import 'package:genzeb/features/account/presentation/onboarding_screen.dart';
import 'package:genzeb/features/account/presentation/sms_setup_screen.dart';

class GenzebApp extends ConsumerWidget {
  const GenzebApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountControllerProvider);
    final smsSetupDone = ref.watch(smsSetupDoneProvider);

    final Widget home;
    if (account.status == AuthStatus.initializing || smsSetupDone == null) {
      home = const _SplashScreen();
    } else if (account.status == AuthStatus.signedOut) {
      home = const OnboardingScreen();
    } else if (!smsSetupDone) {
      home = const SmsSetupScreen();
    } else {
      home = const HomeShell();
    }

    return MaterialApp(
      title: 'Genzeb',
      debugShowCheckedModeBanner: false,
      themeMode: ref.watch(themeModeProvider),
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      // Pages without an AppBar don't set status-bar icon colours; do it
      // once here from the resolved theme so every tab reads correctly.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemOverlayStyleFor(Theme.of(context).brightness),
        child: child ?? const SizedBox.shrink(),
      ),
      home: home,
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
