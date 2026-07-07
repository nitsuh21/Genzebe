import 'package:genzebet/features/profile/domain/models/admin_models.dart';
import 'package:genzebet/features/profile/domain/repositories/admin_repository.dart';

class AdminAuditService {
  AdminAuditService(this._adminRepository);

  final AdminRepository _adminRepository;

  Future<void> logAction({
    required String adminUserId,
    required AdminRole role,
    required String action,
    required String targetUserId,
    String? reason,
  }) {
    return _adminRepository.logAudit(
      AdminActionAudit(
        id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
        adminUserId: adminUserId,
        role: role,
        action: action,
        targetUserId: targetUserId,
        timestamp: DateTime.now(),
        reason: reason,
      ),
    );
  }
}
