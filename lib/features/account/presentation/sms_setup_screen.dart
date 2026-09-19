import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/device_sms_source.dart';

/// One-time onboarding step: explain the SMS permission in plain language,
/// then run the first import so the dashboard isn't empty.
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
              'SMS permission not granted — you can add transactions '
              'manually, or enable it later from Profile.',
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${result.newlyParsed} transactions'
              '${result.pendingReview > 0 ? ' · ${result.pendingReview} waiting for your review' : ''}.',
            ),
          ),
        );
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
          content: Text('Loaded $seeded demo transactions. Enjoy the tour!'),
        ),
      );
      await ref.read(smsSetupDoneProvider.notifier).markDone();
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = ref.watch(stringsProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.sms_outlined,
                  color: theme.colorScheme.primary,
                  size: 30,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                strings.smsTitle,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                strings.smsBody,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              _PrivacyPoint(
                icon: Icons.account_balance_outlined,
                title: strings.smsPoint1Title,
                body: strings.smsPoint1Body,
              ),
              _PrivacyPoint(
                icon: Icons.phonelink_lock_outlined,
                title: strings.smsPoint2Title,
                body: strings.smsPoint2Body,
              ),
              _PrivacyPoint(
                icon: Icons.fact_check_outlined,
                title: strings.smsPoint3Title,
                body: strings.smsPoint3Body,
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: _importing ? null : _connectAndImport,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _importing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          strings.smsAllow,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _importing ? null : _loadDemoData,
                  icon: const Icon(Icons.auto_awesome_motion_rounded, size: 18),
                  label: Text(
                    strings.smsDemo,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: _importing
                      ? null
                      : () =>
                          ref.read(smsSetupDoneProvider.notifier).markDone(),
                  child: Text(strings.smsLater),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
