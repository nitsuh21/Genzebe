import 'package:genzebet/features/profile/domain/models/admin_models.dart';
import 'package:genzebet/features/profile/domain/repositories/admin_repository.dart';

class InMemoryAdminRepository implements AdminRepository {
  final List<AdminActionAudit> _audits = [];
  final List<RiskSignal> _riskSignals = [];

  @override
  Future<List<AdminActionAudit>> getAuditLogs() async {
    return List<AdminActionAudit>.unmodifiable(_audits);
  }

  @override
  Future<List<RiskSignal>> getOpenRiskSignals() async {
    return _riskSignals
        .where((signal) => !signal.resolved)
        .toList(growable: false);
  }

  @override
  Future<void> logAudit(AdminActionAudit action) async {
    _audits.add(action);
  }

  @override
  Future<void> saveRiskSignal(RiskSignal signal) async {
    _riskSignals.removeWhere((existing) => existing.id == signal.id);
    _riskSignals.add(signal);
  }
}
