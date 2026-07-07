enum AuthStatus {
  /// Restoring session / waiting on first auth check.
  initializing,

  /// No session and the user hasn't opted into offline mode yet.
  signedOut,

  /// Using the app without an account (chosen explicitly, or the build has
  /// no backend configured). Everything on-device works normally.
  localOnly,

  signedIn,
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;

  /// "Abebe Kebede" -> "AK"; falls back to the first letter of the email.
  String get initials {
    final name = displayName?.trim() ?? '';
    if (name.isNotEmpty) {
      final parts =
          name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      final first = parts.first[0];
      final last = parts.length > 1 ? parts.last[0] : '';
      return '$first$last'.toUpperCase();
    }
    return email.isEmpty ? '?' : email[0].toUpperCase();
  }
}

class AccountState {
  const AccountState({
    required this.status,
    required this.backendConfigured,
    this.profile,
    this.planCode = PlanCatalog.freemiumCode,
    this.error,
    this.busy = false,
  });

  final AuthStatus status;
  final bool backendConfigured;
  final UserProfile? profile;
  final String planCode;
  final String? error;
  final bool busy;

  PlanInfo get plan => PlanCatalog.byCode(planCode);

  AccountState copyWith({
    AuthStatus? status,
    UserProfile? profile,
    bool clearProfile = false,
    String? planCode,
    String? error,
    bool clearError = false,
    bool? busy,
  }) {
    return AccountState(
      status: status ?? this.status,
      backendConfigured: backendConfigured,
      profile: clearProfile ? null : (profile ?? this.profile),
      planCode: planCode ?? this.planCode,
      error: clearError ? null : (error ?? this.error),
      busy: busy ?? this.busy,
    );
  }
}

class PlanInfo {
  const PlanInfo({
    required this.code,
    required this.name,
    required this.tagline,
    required this.priceLabel,
    required this.available,
    required this.perks,
  });

  final String code;
  final String name;
  final String tagline;
  final String priceLabel;
  final bool available;
  final List<String> perks;
}

/// Plan catalog shown in the app. The authoritative subscription row lives in
/// Supabase (`subscriptions` table); this is display metadata, so new tiers
/// can be announced here and activated server-side later.
class PlanCatalog {
  PlanCatalog._();

  static const freemiumCode = 'freemium';

  static const plans = <PlanInfo>[
    PlanInfo(
      code: freemiumCode,
      name: 'Freemium',
      tagline: 'Everything you need to track your money',
      priceLabel: 'Free',
      available: true,
      perks: [
        'Automatic SMS transaction tracking',
        'Budgets, reports and insights',
        'All data stored on your device',
      ],
    ),
    PlanInfo(
      code: 'plus',
      name: 'Genzeb Plus',
      tagline: 'AI insights and cloud backup',
      priceLabel: 'Coming soon',
      available: false,
      perks: [
        'Built-in AI assistant, no key needed',
        'Encrypted cloud backup and restore',
        'Multi-device sync',
      ],
    ),
    PlanInfo(
      code: 'circle',
      name: 'Genzeb Circle',
      tagline: 'Budgets for your household and equb',
      priceLabel: 'Coming soon',
      available: false,
      perks: [
        'Shared budgets with family',
        'Equb / iqub group tracking',
        'Spending roles and limits',
      ],
    ),
  ];

  static PlanInfo byCode(String code) {
    return plans.firstWhere(
      (plan) => plan.code == code,
      orElse: () => plans.first,
    );
  }
}
