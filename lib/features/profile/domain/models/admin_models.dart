enum AdminRole { superAdmin, opsAdmin, riskAdmin }

class AdminActionAudit {
  const AdminActionAudit({
    required this.id,
    required this.adminUserId,
    required this.role,
    required this.action,
    required this.targetUserId,
    required this.timestamp,
    this.reason,
  });

  final String id;
  final String adminUserId;
  final AdminRole role;
  final String action;
  final String targetUserId;
  final DateTime timestamp;
  final String? reason;
}

class RiskSignal {
  const RiskSignal({
    required this.id,
    required this.userId,
    required this.level,
    required this.summary,
    required this.createdAt,
    this.resolved = false,
  });

  final String id;
  final String userId;
  final String level;
  final String summary;
  final DateTime createdAt;
  final bool resolved;
}
