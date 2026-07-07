import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzebet/app/providers.dart';
import 'package:genzebet/features/ai/presentation/ai_assistant_sheet.dart';
import 'package:genzebet/features/sms_ingestion/presentation/review_queue_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    final themeMode = ref.watch(themeModeProvider);
    final aiAvailableAsync = ref.watch(aiAvailableProvider);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 28 + safeBottom + 84),
      children: [
        Text(
          'Settings',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Personalise GenzeBet, automation and your AI assistant.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),

        _SectionLabel('Appearance'),
        _SettingsCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette_outlined, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      'Theme',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto_rounded),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_rounded),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_rounded),
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (selection) {
                    ref.read(themeModeProvider.notifier).state =
                        selection.first;
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        _SectionLabel('Genze AI'),
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
                      ? 'Powered by Genze · ready to use'
                      : 'Warming up · check your connection',
                  trailingWidget: available
                      ? Icon(Icons.check_circle_rounded,
                          color: theme.colorScheme.primary)
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        _SectionLabel('Automation'),
        _SettingsCard(
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.sms_outlined,
                title: 'SMS automation',
                subtitle: 'Mappings, force sync and diagnostics',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _SmsOpsStandalonePage(),
                  ),
                ),
              ),
              const Divider(height: 1),
              const _SettingsTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: 'Coming soon',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        _SectionLabel('Data & privacy'),
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
                subtitle: 'SMS data never leaves your device except for AI',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            'GenzeBet · v0.1.0',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _SmsOpsStandalonePage extends StatelessWidget {
  const _SmsOpsStandalonePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SMS Automation')),
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
