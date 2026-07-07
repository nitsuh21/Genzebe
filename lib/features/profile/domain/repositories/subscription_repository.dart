import 'package:genzebet/features/profile/domain/models/subscription_models.dart';

abstract class SubscriptionRepository {
  Future<TrialPolicyConfig> getTrialPolicy();
  Future<void> updateTrialPolicy(TrialPolicyConfig config);
  Future<Entitlement?> getEntitlement(String userId);
  Future<void> saveEntitlement(Entitlement entitlement);
  Future<void> savePaymentClaim(PaymentClaim claim);
  Future<List<PaymentClaim>> getPendingClaims();
}
