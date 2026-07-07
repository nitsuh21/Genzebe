import 'package:genzebet/features/ai/application/ai_summary_service.dart';
import 'package:genzebet/features/ai/domain/boundaries/summary_boundary.dart';
import 'package:genzebet/features/ai/domain/models/summary_snapshot.dart';
import 'package:genzebet/features/reports/application/report_service.dart';

class SummaryBoundaryImpl implements SummaryBoundary {
  SummaryBoundaryImpl({
    required ReportService reportService,
    required AiSummaryService aiSummaryService,
  })  : _reportService = reportService,
        _aiSummaryService = aiSummaryService;

  final ReportService _reportService;
  final AiSummaryService _aiSummaryService;

  @override
  Future<MonthlySummarySnapshot> buildSnapshot(String userId) async {
    final report = await _reportService.generateCurrentMonthReport();
    final now = DateTime.now();
    final topEntries = report.categoryTotalsMinor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = topEntries.isEmpty ? 'N/A' : topEntries.first.key;

    final explainability = <String>[
      'Income and expense totals are derived from accepted ledger events.',
      'Top category is computed by absolute category spending in current month.',
      'SMS low-confidence parses stay in review queue until approved.',
    ];

    return MonthlySummarySnapshot(
      userId: userId,
      year: now.year,
      month: now.month,
      incomeMinor: report.incomeMinor,
      expenseMinor: report.expenseMinor,
      netMinor: report.netMinor,
      topCategory: top,
      explainabilityNotes: explainability,
    );
  }

  @override
  Future<String> generateNarrativeSummary(String userId) {
    return _aiSummaryService.generateMonthlySummary(userId);
  }
}
