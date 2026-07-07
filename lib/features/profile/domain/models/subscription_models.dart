enum EntitlementType { free, trial, premium }

enum EntitlementStatus { active, expired, suspended }

class Entitlement {
  const Entitlement({
    required this.userId,
    required this.type,
    required this.status,
    required this.startAt,
    required this.expiresAt,
    required this.aiAccessAllowed,
  });

  final String userId;
  final EntitlementType type;
  final EntitlementStatus status;
  final DateTime startAt;
  final DateTime expiresAt;
  final bool aiAccessAllowed;

  bool isActive(DateTime now) {
    return status == EntitlementStatus.active && now.isBefore(expiresAt);
  }
}

enum PaymentMethod { chapa, telebirr }

enum PaymentClaimStatus {
  submitted,
  autoMatched,
  needsManualReview,
  approved,
  rejected
}

class PaymentClaim {
  const PaymentClaim({
    required this.id,
    required this.userId,
    required this.method,
    required this.reference,
    required this.amountMinor,
    required this.submittedAt,
    required this.status,
    this.proofUri,
  });

  final String id;
  final String userId;
  final PaymentMethod method;
  final String reference;
  final int amountMinor;
  final DateTime submittedAt;
  final PaymentClaimStatus status;
  final String? proofUri;
}

class TrialPolicyConfig {
  const TrialPolicyConfig({
    required this.enabled,
    required this.durationDays,
    required this.allowAiInTrial,
    required this.startPolicy,
  });

  final bool enabled;
  final int durationDays;
  final bool allowAiInTrial;
  final String startPolicy;
}
