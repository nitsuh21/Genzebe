import 'package:genzeb/core/logging/app_logger.dart';
import 'package:genzeb/features/ai/application/ai_categorization_service.dart';

/// Outcome of a CruiseControl pass over freshly synced transactions.
class CruiseControlReport {
  const CruiseControlReport({
    required this.aiUsed,
    this.audited = 0,
    this.corrected = 0,
    this.error,
  });

  static const skipped = CruiseControlReport(aiUsed: false);

  /// Whether the AI actually ran (key configured, network up).
  final bool aiUsed;

  /// How many new transactions were sent for audit.
  final int audited;

  /// How many corrections (category / direction / account) were applied.
  final int corrected;

  final String? error;
}

/// CruiseControl: the categorization autopilot that runs inside every sync.
///
/// Authority order — the guardrails that make this safe to automate:
///  1. User-taught merchant rules are untouchable (filtered out before the
///     AI ever sees the row).
///  2. AI corrections apply only to category, direction, and the account of
///     transactions stranded in the generic wallet — never amounts or dates,
///     and every value is validated against the app's catalogs.
///  3. Any failure (no key, offline, quota, garbage output) degrades to the
///     deterministic parser result. Sync never blocks and never throws
///     because of CruiseControl.
class CruiseControlService {
  CruiseControlService({required AiCategorizationService categorization})
      : _categorization = categorization;

  final AiCategorizationService _categorization;

  Future<CruiseControlReport> steer({
    required Set<String> transactionIds,
  }) async {
    if (transactionIds.isEmpty) return CruiseControlReport.skipped;
    try {
      if (!await _categorization.isAvailable()) {
        return CruiseControlReport.skipped;
      }
      final suggestions = await _categorization.suggestCorrections(
        onlyTransactionIds: transactionIds,
      );
      final corrected = suggestions.isEmpty
          ? 0
          : await _categorization.applySuggestions(suggestions);
      AppLogger.info(
        'cruisecontrol',
        'steer: audited=${transactionIds.length} corrected=$corrected',
      );
      return CruiseControlReport(
        aiUsed: true,
        audited: transactionIds.length,
        corrected: corrected,
      );
    } catch (error) {
      // Autopilot disengages silently; the deterministic result stands.
      AppLogger.info('cruisecontrol', 'steer failed, falling back: $error');
      return CruiseControlReport(aiUsed: false, error: '$error');
    }
  }
}
