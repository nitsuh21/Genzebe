import 'package:genzebet/features/profile/domain/models/subscription_models.dart';
import 'package:genzebet/features/profile/domain/repositories/subscription_repository.dart';

class InMemorySubscriptionRepository implements SubscriptionRepository {
  TrialPolicyConfig _policy = const TrialPolicyConfig(
    enabled: true,
    durationDays: 90,
    allowAiInTrial: true,
    startPolicy: 'on_signup',
  );
  final Map<String, Entitlement> _entitlements = {};
  final List<PaymentClaim> _claims = [];

  @override
  Future<Entitlement?> getEntitlement(String userId) async {
    return _entitlements[userId];
  }

  @override
  Future<List<PaymentClaim>> getPendingClaims() async {
    return _claims
        .where(
          (c) =>
              c.status == PaymentClaimStatus.submitted ||
              c.status == PaymentClaimStatus.needsManualReview,
        )
        .toList(growable: false);
  }

  @override
  Future<TrialPolicyConfig> getTrialPolicy() async {
    return _policy;
  }

  @override
  Future<void> saveEntitlement(Entitlement entitlement) async {
    _entitlements[entitlement.userId] = entitlement;
  }

  @override
  Future<void> savePaymentClaim(PaymentClaim claim) async {
    _claims.removeWhere((existing) => existing.id == claim.id);
    _claims.add(claim);
  }

  @override
  Future<void> updateTrialPolicy(TrialPolicyConfig config) async {
    _policy = config;
  }
}
