import 'package:genzebet/features/profile/domain/models/admin_models.dart';

abstract class AdminRepository {
  Future<void> logAudit(AdminActionAudit action);
  Future<List<AdminActionAudit>> getAuditLogs();
  Future<void> saveRiskSignal(RiskSignal signal);
  Future<List<RiskSignal>> getOpenRiskSignals();
}
