import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzebet/app/providers.dart';
import 'package:genzebet/features/profile/domain/models/auth_models.dart';
import 'package:genzebet/features/profile/domain/models/subscription_models.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  Entitlement? _entitlement;
  String _aiSummary = 'No AI summary requested yet.';
  String _snapshotPreview = 'No snapshot generated yet.';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(authControllerProvider);
    final userId = session.userId;
    if (userId == null) return;
    final service = ref.read(entitlementServiceProvider);
    final entitlement = await service.ensureInitialEntitlement(userId);
    if (!mounted) return;
    setState(() => _entitlement = entitlement);
  }

  Future<void> _submitPremiumClaim() async {
    final userId = ref.read(authControllerProvider).userId;
    if (userId == null) return;
    final claim = PaymentClaim(
      id: 'claim-${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      method: PaymentMethod.telebirr,
      reference: 'TEL-${DateTime.now().millisecondsSinceEpoch}',
      amountMinor: 299900,
      submittedAt: DateTime.now(),
      status: PaymentClaimStatus.submitted,
      proofUri: 'proof://telebirr/screenshot',
    );

    final service = ref.read(paymentClaimServiceProvider);
    await service.submitClaim(claim);
    await service.autoMatchAndResolve(
        claim: claim, expectedAmountMinor: 299900);
    final latest =
        await ref.read(subscriptionRepositoryProvider).getEntitlement(userId);
    if (!mounted) return;
    setState(() => _entitlement = latest);
  }

  Future<void> _generateAiSummary() async {
    final userId = ref.read(authControllerProvider).userId;
    if (userId == null) return;
    final snapshot =
        await ref.read(summaryBoundaryProvider).buildSnapshot(userId);
    final text =
        await ref.read(aiSummaryServiceProvider).generateMonthlySummary(userId);
    if (!mounted) return;
    setState(() {
      _aiSummary = text;
      _snapshotPreview =
          'Snapshot ${snapshot.month}/${snapshot.year}: net ${snapshot.netMinor / 100.0} ETB, '
          'top category ${snapshot.topCategory}.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final entitlement = _entitlement;
    final session = ref.watch(authControllerProvider);
    final reminders = entitlement == null
        ? const <DateTime>[]
        : entitlement.type == EntitlementType.trial
            ? ref
                .read(reminderServiceProvider)
                .buildTrialReminderSchedule(entitlement)
            : ref
                .read(reminderServiceProvider)
                .buildPremiumReminderSchedule(entitlement);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          const Text(
            'Premium & Trial',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (session.status == AuthStatus.guest)
            FilledButton(
              onPressed: () {
                ref
                    .read(authControllerProvider.notifier)
                    .signInWithPhone('+251900000000');
                _load();
              },
              child: const Text('Sign in (Phone OTP demo)'),
            ),
          if (session.status == AuthStatus.authenticated)
            OutlinedButton(
              onPressed: () {
                ref.read(authControllerProvider.notifier).signOut();
                setState(() => _entitlement = null);
              },
              child: const Text('Sign out'),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: entitlement == null
                  ? const Text('Sign in to load trial/premium entitlement.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Plan: ${entitlement.type.name}'),
                        Text('Status: ${entitlement.status.name}'),
                        Text('Expires: ${entitlement.expiresAt}'),
                        Text(
                            'AI access: ${entitlement.aiAccessAllowed ? 'Yes' : 'No'}'),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _submitPremiumClaim,
            child: const Text('Activate 6-Month Premium (Telebirr sample)'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _generateAiSummary,
            child: const Text('Run AI Monthly Summary'),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_aiSummary),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_snapshotPreview),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Renewal reminder schedule',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  if (reminders.isEmpty)
                    const Text('No reminders generated yet.'),
                  ...reminders.map((date) => Text('- $date')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
