import 'package:genzebet/features/profile/domain/models/admin_models.dart';
import 'package:genzebet/features/profile/domain/repositories/admin_repository.dart';
import 'package:genzebet/features/profile/domain/repositories/subscription_repository.dart';

class RiskService {
  RiskService({
    required SubscriptionRepository subscriptionRepository,
    required AdminRepository adminRepository,
  })  : _subscriptionRepository = subscriptionRepository,
        _adminRepository = adminRepository;

  final SubscriptionRepository _subscriptionRepository;
  final AdminRepository _adminRepository;

  Future<void> checkTrialAbuse(String userId) async {
    final entitlement = await _subscriptionRepository.getEntitlement(userId);
    if (entitlement == null) return;

    if (entitlement.type.name == 'trial' &&
        entitlement.status.name == 'expired') {
      await _adminRepository.saveRiskSignal(
        RiskSignal(
          id: 'risk-$userId-${DateTime.now().millisecondsSinceEpoch}',
          userId: userId,
          level: 'medium',
          summary: 'User exhausted trial and attempted to reactivate.',
          createdAt: DateTime.now(),
        ),
      );
    }
  }
}
