import 'package:genzebet/features/ai/domain/models/summary_snapshot.dart';

abstract class SummaryBoundary {
  Future<MonthlySummarySnapshot> buildSnapshot(String userId);
  Future<String> generateNarrativeSummary(String userId);
}
