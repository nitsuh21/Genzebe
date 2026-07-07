import 'package:genzebet/features/profile/domain/models/subscription_models.dart';
import 'package:genzebet/features/profile/domain/repositories/subscription_repository.dart';

class EntitlementService {
  EntitlementService(this._repository);

  final SubscriptionRepository _repository;

  Future<Entitlement> ensureInitialEntitlement(String userId) async {
    final existing = await _repository.getEntitlement(userId);
    if (existing != null) return existing;

    final trialPolicy = await _repository.getTrialPolicy();
    if (trialPolicy.enabled) {
      final now = DateTime.now();
      final trial = Entitlement(
        userId: userId,
        type: EntitlementType.trial,
        status: EntitlementStatus.active,
        startAt: now,
        expiresAt: now.add(Duration(days: trialPolicy.durationDays)),
        aiAccessAllowed: trialPolicy.allowAiInTrial,
      );
      await _repository.saveEntitlement(trial);
      return trial;
    }

    final free = Entitlement(
      userId: userId,
      type: EntitlementType.free,
      status: EntitlementStatus.active,
      startAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 3650)),
      aiAccessAllowed: false,
    );
    await _repository.saveEntitlement(free);
    return free;
  }

  Future<void> applyPremiumForSixMonths(String userId) async {
    final now = DateTime.now();
    final premium = Entitlement(
      userId: userId,
      type: EntitlementType.premium,
      status: EntitlementStatus.active,
      startAt: now,
      expiresAt: now.add(const Duration(days: 180)),
      aiAccessAllowed: true,
    );
    await _repository.saveEntitlement(premium);
  }

  Future<void> expireIfNeeded(String userId) async {
    final entitlement = await _repository.getEntitlement(userId);
    if (entitlement == null) return;

    if (DateTime.now().isBefore(entitlement.expiresAt)) return;
    final expired = Entitlement(
      userId: entitlement.userId,
      type: entitlement.type,
      status: EntitlementStatus.expired,
      startAt: entitlement.startAt,
      expiresAt: entitlement.expiresAt,
      aiAccessAllowed: false,
    );
    await _repository.saveEntitlement(expired);
  }
}
