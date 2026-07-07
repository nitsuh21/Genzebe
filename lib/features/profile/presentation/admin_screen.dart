import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzebet/app/providers.dart';
import 'package:genzebet/features/profile/domain/models/admin_models.dart';
import 'package:genzebet/features/profile/domain/models/subscription_models.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  TrialPolicyConfig? _policy;
  Entitlement? _demoUserEntitlement;
  List<AdminActionAudit> _audits = const [];
  List<RiskSignal> _risks = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final policy =
        await ref.read(subscriptionRepositoryProvider).getTrialPolicy();
    final entitlement = await ref
        .read(subscriptionRepositoryProvider)
        .getEntitlement('demo-user');
    final audits = await ref.read(adminRepositoryProvider).getAuditLogs();
    final risks = await ref.read(adminRepositoryProvider).getOpenRiskSignals();
    if (!mounted) return;
    setState(() {
      _policy = policy;
      _demoUserEntitlement = entitlement;
      _audits = audits;
      _risks = risks;
    });
  }

  Future<void> _toggleTrial() async {
    final current = _policy;
    if (current == null) return;
    final next = TrialPolicyConfig(
      enabled: !current.enabled,
      durationDays: current.durationDays,
      allowAiInTrial: current.allowAiInTrial,
      startPolicy: current.startPolicy,
    );
    await ref.read(subscriptionRepositoryProvider).updateTrialPolicy(next);
    await ref.read(adminAuditServiceProvider).logAction(
          adminUserId: 'admin-1',
          role: AdminRole.superAdmin,
          action: 'trial_policy_toggled',
          targetUserId: 'global',
        );
    await _load();
  }

  Future<void> _setNinetyDayTrial() async {
    final current = _policy;
    if (current == null) return;
    final next = TrialPolicyConfig(
      enabled: current.enabled,
      durationDays: 90,
      allowAiInTrial: current.allowAiInTrial,
      startPolicy: current.startPolicy,
    );
    await ref.read(subscriptionRepositoryProvider).updateTrialPolicy(next);
    await ref.read(adminAuditServiceProvider).logAction(
          adminUserId: 'admin-1',
          role: AdminRole.opsAdmin,
          action: 'trial_duration_set_90',
          targetUserId: 'global',
        );
    await _load();
  }

  Future<void> _simulateRisk() async {
    await ref.read(riskServiceProvider).checkTrialAbuse('demo-user');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final policy = _policy;
    final reminderDates = _demoUserEntitlement == null
        ? const <DateTime>[]
        : _demoUserEntitlement!.type == EntitlementType.trial
            ? ref
                .read(reminderServiceProvider)
                .buildTrialReminderSchedule(_demoUserEntitlement!)
            : ref
                .read(reminderServiceProvider)
                .buildPremiumReminderSchedule(_demoUserEntitlement!);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          const Text(
            'Admin Console',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: policy == null
                  ? const Text('Loading trial policy...')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Trial enabled: ${policy.enabled}'),
                        Text('Default trial days: ${policy.durationDays}'),
                        Text('AI allowed in trial: ${policy.allowAiInTrial}'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              onPressed: _toggleTrial,
                              child: const Text('Toggle Trial'),
                            ),
                            OutlinedButton(
                              onPressed: _setNinetyDayTrial,
                              child: const Text('Set 90 Days'),
                            ),
                            OutlinedButton(
                              onPressed: _simulateRisk,
                              child: const Text('Run Risk Check'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Renewal reminder dashboard',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (reminderDates.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No scheduled reminders yet for demo-user.'),
              ),
            ),
          ...reminderDates.map(
            (date) => Card(
              child: ListTile(
                title: const Text('Scheduled reminder'),
                subtitle: Text('demo-user • $date'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Open risk signals',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_risks.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No open risk signals.'),
              ),
            ),
          ..._risks.map(
            (risk) => Card(
              child: ListTile(
                title: Text(risk.summary),
                subtitle: Text('User ${risk.userId} • ${risk.level}'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Audit log',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_audits.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No audit events yet.'),
              ),
            ),
          ..._audits.map(
            (audit) => Card(
              child: ListTile(
                title: Text(audit.action),
                subtitle: Text('${audit.role.name} • ${audit.timestamp}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
