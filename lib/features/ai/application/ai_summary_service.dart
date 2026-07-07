import 'package:genzebet/features/profile/domain/repositories/subscription_repository.dart';
import 'package:genzebet/features/reports/application/report_service.dart';

class AiSummaryService {
  AiSummaryService({
    required SubscriptionRepository subscriptionRepository,
    required ReportService reportService,
  })  : _subscriptionRepository = subscriptionRepository,
        _reportService = reportService;

  final SubscriptionRepository _subscriptionRepository;
  final ReportService _reportService;

  Future<bool> canUseAi(String userId) async {
    final entitlement = await _subscriptionRepository.getEntitlement(userId);
    if (entitlement == null) return false;
    if (!entitlement.isActive(DateTime.now())) return false;
    return entitlement.aiAccessAllowed;
  }

  Future<String> generateMonthlySummary(String userId) async {
    final allowed = await canUseAi(userId);
    if (!allowed) {
      return 'AI summary is a premium feature. Activate trial or premium plan.';
    }

    final report = await _reportService.generateCurrentMonthReport();
    final top = report.categoryTotalsMinor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCategory = top.isEmpty
        ? 'N/A'
        : '${top.first.key} (${top.first.value / 100.0} ETB)';

    return 'Monthly cashflow summary: income ${report.incomeMinor / 100.0} ETB, '
        'expense ${report.expenseMinor / 100.0} ETB, net ${report.netMinor / 100.0} ETB. '
        'Top spending category: $topCategory.';
  }
}
