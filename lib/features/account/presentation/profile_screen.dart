import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/core/l10n/app_strings.dart';
import 'package:genzeb/features/account/domain/models/account_models.dart';
import 'package:genzeb/features/ai/presentation/ai_assistant_sheet.dart';
import 'package:genzeb/features/sms_ingestion/presentation/review_queue_screen.dart';

/// Profile tab. Layout follows the modern fintech pattern: identity hero,
/// personal stats, compact plan row (full comparison behind a sheet), then
/// grouped settings tiles whose pickers open as bottom sheets — no inline
/// segmented controls. Destructive actions live at the very bottom.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    final account = ref.watch(accountControllerProvider);
    final strings = ref.watch(stringsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final language = ref.watch(appLanguageProvider);
    final aiAvailable = ref.watch(aiAvailableProvider).valueOrNull;
    final pendingReview = ref.watch(reviewQueueProvider).valueOrNull?.length;

    ref.listen<AccountState>(accountControllerProvider, (previous, next) {
      final error = next.error;
      if (error != null && error != previous?.error) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
        ref.read(accountControllerProvider.notifier).dismissError();
      }
    });

    final themeValue = switch (themeMode) {
      ThemeMode.system => strings.themeSystem,
      ThemeMode.light => strings.themeLight,
      ThemeMode.dark => strings.themeDark,
    };
    final languageValue = switch (language) {
      'en' => 'English',
      'am' => 'አማርኛ',
      _ => strings.themeSystem,
    };

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 28 + safeBottom + 84),
      children: [
        _ProfileHero(account: account, strings: strings),
        const SizedBox(height: 14),
        _StatsStrip(strings: strings),
        const SizedBox(height: 22),

        _SectionLabel(strings.yourPlan),
        _PlanRow(
          account: account,
          strings: strings,
          onTap: () => _showPlansSheet(context, account.planCode, strings),
        ),
        const SizedBox(height: 20),

        _SectionLabel(strings.preferences),
        _SettingsCard(
          children: [
            _SettingsTile(
              icon: Icons.palette_outlined,
              iconColor: const Color(0xFF6C6CE5),
              title: strings.theme,
              trailingValue: themeValue,
              onTap: () => _showThemeSheet(context, ref, strings),
            ),
            _SettingsTile(
              icon: Icons.translate_rounded,
              iconColor: const Color(0xFF3B8DD6),
              title: strings.language,
              trailingValue: languageValue,
              onTap: () => _showLanguageSheet(context, ref, strings),
            ),
          ],
        ),
        const SizedBox(height: 20),

        const _SectionLabel('Genzeb AI'),
        _SettingsCard(
          children: [
            _SettingsTile(
              icon: Icons.auto_awesome_rounded,
              iconColor: const Color(0xFF8E63D8),
              title: 'AI assistant',
              subtitle: 'Ask about spending, budgets and plans',
              trailingWidget: _StatusDot(ready: aiAvailable ?? false),
              onTap: () => showAiAssistant(context),
            ),
          ],
        ),
        const SizedBox(height: 20),

        _SectionLabel(strings.automation),
        _SettingsCard(
          children: [
            _SettingsTile(
              icon: Icons.sms_outlined,
              iconColor: const Color(0xFF2E9E6B),
              title: 'SMS sync & review',
              subtitle: 'Import, mappings and the review queue',
              trailingWidget: (pendingReview ?? 0) > 0
                  ? _CountBadge(count: pendingReview!)
                  : null,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SmsOpsPage()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        _SectionLabel(strings.dataPrivacy),
        _SettingsCard(
          children: [
            const _SettingsTile(
              icon: Icons.phonelink_lock_outlined,
              iconColor: Color(0xFF4AA3B5),
              title: 'Private by design',
              subtitle: 'Your SMS and ledger never leave this device. AI '
                  'receives only an aggregated summary.',
            ),
            _SettingsTile(
              icon: Icons.auto_awesome_motion_rounded,
              iconColor: const Color(0xFFD8589E),
              title: 'Load demo data',
              subtitle: 'Fill the app with a realistic sample ledger',
              onTap: () async {
                final seeded = await ref.read(demoDataServiceProvider).seed();
                refreshAppData(ref);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Loaded $seeded demo transactions.')),
                  );
                }
              },
            ),
          ],
        ),

        if (account.status == AuthStatus.signedIn) ...[
          const SizedBox(height: 20),
          _SignOutTile(strings: strings),
        ],

        const SizedBox(height: 28),
        Center(
          child: Column(
            children: [
              Text(
                'Genzeb · v0.2.0',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                strings.madeFor,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Identity hero
// ---------------------------------------------------------------------------

class _ProfileHero extends ConsumerWidget {
  const _ProfileHero({required this.account, required this.strings});

  final AccountState account;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = account.profile;
    final signedIn = account.status == AuthStatus.signedIn && profile != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3D49D6), Color(0xFF6C3DD6)],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4E5AE8).withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          _RingedAvatar(profile: profile),
          const SizedBox(height: 14),
          Text(
            signedIn ? (profile.displayName ?? profile.email) : 'Genzeb',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            signedIn
                ? profile.email
                : (account.backendConfigured
                    ? 'Sign in to activate your free plan'
                    : 'Using Genzeb offline — everything still works'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 14),
          if (signedIn)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.workspace_premium_rounded,
                      color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    account.backendConfigured
                        ? account.plan.name
                        : '${account.plan.name} · demo',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1B2050),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
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
                  : Text(
                      strings.authGoogle,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
        ],
      ),
    );
  }
}

class _RingedAvatar extends StatelessWidget {
  const _RingedAvatar({required this.profile});

  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final photo = profile?.photoUrl;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.55),
          width: 2,
        ),
      ),
      child: CircleAvatar(
        radius: 34,
        backgroundColor: Colors.white,
        foregroundImage: photo == null ? null : NetworkImage(photo),
        child: profile == null
            ? const Icon(Icons.person_rounded,
                color: Color(0xFF4E5AE8), size: 34)
            : Text(
                profile!.initials,
                style: const TextStyle(
                  color: Color(0xFF4E5AE8),
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Personal stats
// ---------------------------------------------------------------------------

class _StatsStrip extends ConsumerWidget {
  const _StatsStrip({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions =
        ref.watch(allTransactionsProvider).valueOrNull?.length;
    final accounts = ref.watch(accountsProvider).valueOrNull?.length;
    final budgets =
        ref.watch(budgetOverviewProvider).valueOrNull?.items.length;

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            value: transactions,
            label: strings.transactions,
            icon: Icons.receipt_long_rounded,
            color: const Color(0xFF4E5AE8),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            value: accounts,
            label: strings.accounts,
            icon: Icons.account_balance_rounded,
            color: const Color(0xFF2E9E6B),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            value: budgets,
            label: strings.budgets,
            icon: Icons.savings_rounded,
            color: const Color(0xFFD08A3E),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final int? value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(height: 6),
          Text(
            value?.toString() ?? '—',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plan row + plans sheet
// ---------------------------------------------------------------------------

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.account,
    required this.strings,
    required this.onTap,
  });

  final AccountState account;
  final AppStrings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = account.plan;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4E5AE8), Color(0xFF8E63D8)],
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.workspace_premium_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          plan.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            strings.currentPlan,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      plan.tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                strings.seePlans,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

void _showPlansSheet(
  BuildContext context,
  String currentPlanCode,
  AppStrings strings,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(
                strings.yourPlan,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              for (final plan in PlanCatalog.plans) ...[
                _PlanSheetCard(
                  plan: plan,
                  isCurrent: plan.code == currentPlanCode,
                  strings: strings,
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      );
    },
  );
}

class _PlanSheetCard extends StatelessWidget {
  const _PlanSheetCard({
    required this.plan,
    required this.isCurrent,
    required this.strings,
  });

  final PlanInfo plan;
  final bool isCurrent;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCurrent
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: isCurrent ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isCurrent ? strings.currentPlan : plan.priceLabel,
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
          const SizedBox(height: 12),
          for (final perk in plan.perks)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 17,
                    color: plan.available
                        ? const Color(0xFF2E9E6B)
                        : theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(perk, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pickers (bottom sheets instead of inline segmented controls)
// ---------------------------------------------------------------------------

void _showThemeSheet(BuildContext context, WidgetRef ref, AppStrings strings) {
  final current = ref.read(themeModeProvider);
  _showPickerSheet<ThemeMode>(
    context: context,
    title: strings.theme,
    current: current,
    options: [
      _PickerOption(
        value: ThemeMode.system,
        label: strings.themeSystem,
        icon: Icons.brightness_auto_rounded,
      ),
      _PickerOption(
        value: ThemeMode.light,
        label: strings.themeLight,
        icon: Icons.light_mode_rounded,
      ),
      _PickerOption(
        value: ThemeMode.dark,
        label: strings.themeDark,
        icon: Icons.dark_mode_rounded,
      ),
    ],
    onSelected: (mode) => ref.read(themeModeProvider.notifier).setMode(mode),
  );
}

void _showLanguageSheet(
    BuildContext context, WidgetRef ref, AppStrings strings) {
  final current = ref.read(appLanguageProvider);
  _showPickerSheet<String>(
    context: context,
    title: strings.language,
    current: current,
    options: [
      _PickerOption(
        value: 'system',
        label: strings.themeSystem,
        icon: Icons.smartphone_rounded,
      ),
      const _PickerOption(
        value: 'en',
        label: 'English',
        icon: Icons.language_rounded,
      ),
      const _PickerOption(
        value: 'am',
        label: 'አማርኛ',
        icon: Icons.language_rounded,
      ),
    ],
    onSelected: (value) =>
        ref.read(appLanguageProvider.notifier).setLanguage(value),
  );
}

class _PickerOption<T> {
  const _PickerOption({
    required this.value,
    required this.label,
    required this.icon,
  });

  final T value;
  final String label;
  final IconData icon;
}

void _showPickerSheet<T>({
  required BuildContext context,
  required String title,
  required T current,
  required List<_PickerOption<T>> options,
  required ValueChanged<T> onSelected,
}) {
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            for (final option in options)
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Icon(
                  option.icon,
                  color: option.value == current
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  option.label,
                  style: TextStyle(
                    fontWeight: option.value == current
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                trailing: option.value == current
                    ? Icon(Icons.check_circle_rounded,
                        color: theme.colorScheme.primary)
                    : null,
                onTap: () {
                  onSelected(option.value);
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Settings tiles
// ---------------------------------------------------------------------------

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 66),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailingValue,
    this.trailingWidget,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? trailingValue;
  final Widget? trailingWidget;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: destructive ? const Color(0xFFE25555) : null,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingValue != null)
            Text(
              trailingValue!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (trailingWidget != null) trailingWidget!,
          if (onTap != null && !destructive) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    final color = ready ? const Color(0xFF2E9E6B) : const Color(0xFFE8833A);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE8833A),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SignOutTile extends ConsumerWidget {
  const _SignOutTile({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SettingsCard(
      children: [
        _SettingsTile(
          icon: Icons.logout_rounded,
          iconColor: const Color(0xFFE25555),
          title: strings.signOut,
          subtitle: 'Your on-device data stays on this phone',
          destructive: true,
          onTap: () async {
            final confirmed = await _showSignOutSheet(context, strings);
            if (confirmed == true) {
              await ref.read(accountControllerProvider.notifier).signOut();
            }
          },
        ),
      ],
    );
  }
}

/// Branded sign-out confirmation: a bottom sheet in the app's own design
/// language instead of the stock Android dialog.
Future<bool?> _showSignOutSheet(BuildContext context, AppStrings strings) {
  return showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFE25555).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFE25555),
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${strings.signOut}?',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your transactions and budgets stay safely on this device. '
              'You can sign back in anytime.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE25555),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => Navigator.of(sheetContext).pop(true),
                child: Text(
                  strings.signOut,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    },
  );
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

// ---------------------------------------------------------------------------
// Gemini key dialog + SMS ops host page
// ---------------------------------------------------------------------------

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
