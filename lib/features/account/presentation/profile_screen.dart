import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/features/account/domain/models/account_models.dart';
import 'package:genzeb/features/ai/presentation/ai_assistant_sheet.dart';
import 'package:genzeb/features/sms_ingestion/presentation/review_queue_screen.dart';

/// Profile tab: who you are, what plan you're on, and every app setting.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    final account = ref.watch(accountControllerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final aiAvailableAsync = ref.watch(aiAvailableProvider);
    final strings = ref.watch(stringsProvider);
    final language = ref.watch(appLanguageProvider);

    ref.listen<AccountState>(accountControllerProvider, (previous, next) {
      final error = next.error;
      if (error != null && error != previous?.error) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
        ref.read(accountControllerProvider.notifier).dismissError();
      }
    });

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 28 + safeBottom + 84),
      children: [
        Text(
          strings.profileTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        _AccountHeader(account: account),
        const SizedBox(height: 22),

        _SectionLabel(strings.yourPlan),
        _PlanSection(currentPlanCode: account.planCode),
        const SizedBox(height: 22),

        _SectionLabel(strings.appearance),
        _SettingsCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette_outlined,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      strings.theme,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(strings.themeSystem),
                      icon: const Icon(Icons.brightness_auto_rounded),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(strings.themeLight),
                      icon: const Icon(Icons.light_mode_rounded),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(strings.themeDark),
                      icon: const Icon(Icons.dark_mode_rounded),
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (selection) {
                    ref
                        .read(themeModeProvider.notifier)
                        .setMode(selection.first);
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.translate_rounded,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      strings.language,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'system',
                      label: Text(strings.themeSystem),
                    ),
                    const ButtonSegment(
                      value: 'en',
                      label: Text('English'),
                    ),
                    const ButtonSegment(
                      value: 'am',
                      label: Text('አማርኛ'),
                    ),
                  ],
                  selected: {language},
                  onSelectionChanged: (selection) {
                    ref
                        .read(appLanguageProvider.notifier)
                        .setLanguage(selection.first);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        const _SectionLabel('Genzeb AI'),
        _SettingsCard(
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.auto_awesome_rounded,
                title: 'AI assistant',
                subtitle: 'Ask about spending, budgets and plans',
                onTap: () => showAiAssistant(context),
              ),
              const Divider(height: 1),
              aiAvailableAsync.when(
                loading: () => const _SettingsTile(
                  icon: Icons.bolt_rounded,
                  title: 'AI status',
                  subtitle: 'Checking…',
                ),
                error: (_, __) => const _SettingsTile(
                  icon: Icons.bolt_rounded,
                  title: 'AI status',
                  subtitle: 'Unavailable right now',
                ),
                data: (available) => _SettingsTile(
                  icon: Icons.bolt_rounded,
                  title: 'AI status',
                  subtitle: available
                      ? 'Ready to use'
                      : 'Add a free Gemini key below to enable AI',
                  trailingWidget: available
                      ? Icon(Icons.check_circle_rounded,
                          color: theme.colorScheme.primary)
                      : null,
                ),
              ),
              const Divider(height: 1),
              _SettingsTile(
                icon: Icons.key_rounded,
                title: 'Gemini API key',
                subtitle:
                    'Get one free at aistudio.google.com — stored only on this device',
                onTap: () => _showGeminiKeyDialog(context, ref),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        _SectionLabel(strings.automation),
        _SettingsCard(
          child: _SettingsTile(
            icon: Icons.sms_outlined,
            title: 'SMS sync & review',
            subtitle: 'Import, mappings and the review queue',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SmsOpsPage(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),

        _SectionLabel(strings.dataPrivacy),
        _SettingsCard(
          child: Column(
            children: [
              const _SettingsTile(
                icon: Icons.storage_rounded,
                title: 'On-device database',
                subtitle: 'Transactions and budgets are stored locally',
              ),
              const Divider(height: 1),
              const _SettingsTile(
                icon: Icons.security_outlined,
                title: 'Privacy & permissions',
                subtitle:
                    'Your SMS never leaves this device. AI questions send '
                    'only an aggregated financial summary.',
              ),
              const Divider(height: 1),
              _SettingsTile(
                icon: Icons.auto_awesome_motion_rounded,
                title: 'Load demo data',
                subtitle: 'Fill the app with a realistic sample ledger',
                onTap: () async {
                  final seeded =
                      await ref.read(demoDataServiceProvider).seed();
                  refreshAppData(ref);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('Loaded $seeded demo transactions.'),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        if (account.status == AuthStatus.signedIn) ...[
          const SizedBox(height: 18),
          _SettingsCard(
            child: _SettingsTile(
              icon: Icons.logout_rounded,
              title: strings.signOut,
              subtitle: 'Your on-device data stays on this phone',
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Sign out?'),
                    content: const Text(
                      'Your transactions and budgets stay safely on this '
                      'device. You can sign back in anytime.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref.read(accountControllerProvider.notifier).signOut();
                }
              },
            ),
          ),
        ],
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Genzeb · v0.2.0',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountHeader extends ConsumerWidget {
  const _AccountHeader({required this.account});

  final AccountState account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = account.profile;

    if (account.status != AuthStatus.signedIn || profile == null) {
      return Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3D49D6), Color(0xFF6C3DD6)],
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Using Genzeb offline',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              account.backendConfigured
                  ? 'Sign in with Google to activate your free plan and '
                      'unlock account features as they arrive.'
                  : 'This build has no backend configured, so accounts are '
                      'unavailable. Everything on-device still works.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            if (account.backendConfigured) ...[
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1B2050),
                ),
                onPressed: account.busy
                    ? null
                    : () => ref
                        .read(accountControllerProvider.notifier)
                        .signInWithGoogle(),
                child: account.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Text(
                        'Continue with Google',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3D49D6), Color(0xFF6C3DD6)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          _Avatar(profile: profile),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName ?? profile.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  profile.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    account.backendConfigured
                        ? '${account.plan.name} plan'
                        : '${account.plan.name} plan · demo',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.verified_rounded,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final photo = profile.photoUrl;
    return CircleAvatar(
      radius: 28,
      backgroundColor: Colors.white,
      foregroundImage: photo == null ? null : NetworkImage(photo),
      child: Text(
        profile.initials,
        style: const TextStyle(
          color: Color(0xFF4E5AE8),
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _PlanSection extends StatelessWidget {
  const _PlanSection({required this.currentPlanCode});

  final String currentPlanCode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: PlanCatalog.plans.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final plan = PlanCatalog.plans[index];
          return _PlanCard(
            plan: plan,
            isCurrent: plan.code == currentPlanCode,
          );
        },
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.isCurrent});

  final PlanInfo plan;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: isCurrent
            ? Border.all(color: theme.colorScheme.primary, width: 1.6)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isCurrent ? 'Current' : plan.priceLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isCurrent
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            plan.tagline,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          for (final perk in plan.perks)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_rounded,
                    size: 15,
                    color: plan.available
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      perk,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.2),
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

Future<void> _showGeminiKeyDialog(BuildContext context, WidgetRef ref) async {
  final service = ref.read(aiAssistantServiceProvider);
  if (service.hasBundledKey) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This build already includes an AI key.')),
    );
    return;
  }
  final existing = await service.getApiKey();
  if (!context.mounted) return;

  final controller = TextEditingController(text: existing ?? '');
  final action = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Gemini API key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste a free key from aistudio.google.com. It is stored only '
              'on this device and used to answer your AI questions.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API key',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('clear'),
              child: const Text('Remove key'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('save'),
            child: const Text('Save'),
          ),
        ],
      );
    },
  );

  if (action == 'save' && controller.text.trim().isNotEmpty) {
    await service.saveApiKey(controller.text);
  } else if (action == 'clear') {
    await service.clearApiKey();
  } else {
    controller.dispose();
    return;
  }
  controller.dispose();
  refreshAppData(ref);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          action == 'save' ? 'AI key saved.' : 'AI key removed.',
        ),
      ),
    );
  }
}

/// Standalone page hosting the SMS sync & review experience.
class SmsOpsPage extends StatelessWidget {
  const SmsOpsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SMS sync & review')),
      body: const SafeArea(child: ReviewQueueScreen()),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailingWidget,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailingWidget;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: trailingWidget ??
          (onTap == null ? null : const Icon(Icons.chevron_right_rounded)),
    );
  }
}
