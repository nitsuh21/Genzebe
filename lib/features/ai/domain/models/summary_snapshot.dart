class MonthlySummarySnapshot {
  const MonthlySummarySnapshot({
    required this.userId,
    required this.year,
    required this.month,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.netMinor,
    required this.topCategory,
    required this.explainabilityNotes,
  });

  final String userId;
  final int year;
  final int month;
  final int incomeMinor;
  final int expenseMinor;
  final int netMinor;
  final String topCategory;
  final List<String> explainabilityNotes;
}
