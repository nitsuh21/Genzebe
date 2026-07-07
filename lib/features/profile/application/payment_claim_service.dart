import 'package:genzebet/features/profile/application/entitlement_service.dart';
import 'package:genzebet/features/profile/domain/models/subscription_models.dart';
import 'package:genzebet/features/profile/domain/repositories/subscription_repository.dart';

class PaymentClaimService {
  PaymentClaimService({
    required SubscriptionRepository repository,
    required EntitlementService entitlementService,
  })  : _repository = repository,
        _entitlementService = entitlementService;

  final SubscriptionRepository _repository;
  final EntitlementService _entitlementService;

  Future<void> submitClaim(PaymentClaim claim) async {
    await _repository.savePaymentClaim(
      PaymentClaim(
        id: claim.id,
        userId: claim.userId,
        method: claim.method,
        reference: claim.reference,
        amountMinor: claim.amountMinor,
        submittedAt: claim.submittedAt,
        status: PaymentClaimStatus.submitted,
        proofUri: claim.proofUri,
      ),
    );
  }

  Future<PaymentClaimStatus> autoMatchAndResolve({
    required PaymentClaim claim,
    required int expectedAmountMinor,
  }) async {
    final looksMatched = claim.amountMinor == expectedAmountMinor &&
        claim.reference.trim().isNotEmpty;
    if (!looksMatched) {
      await _repository.savePaymentClaim(
        PaymentClaim(
          id: claim.id,
          userId: claim.userId,
          method: claim.method,
          reference: claim.reference,
          amountMinor: claim.amountMinor,
          submittedAt: claim.submittedAt,
          status: PaymentClaimStatus.needsManualReview,
          proofUri: claim.proofUri,
        ),
      );
      return PaymentClaimStatus.needsManualReview;
    }

    await _repository.savePaymentClaim(
      PaymentClaim(
        id: claim.id,
        userId: claim.userId,
        method: claim.method,
        reference: claim.reference,
        amountMinor: claim.amountMinor,
        submittedAt: claim.submittedAt,
        status: PaymentClaimStatus.approved,
        proofUri: claim.proofUri,
      ),
    );
    await _entitlementService.applyPremiumForSixMonths(claim.userId);
    return PaymentClaimStatus.approved;
  }
}
