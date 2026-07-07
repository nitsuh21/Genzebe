class BudgetEnvelope {
  const BudgetEnvelope({
    required this.id,
    required this.categoryId,
    required this.limitMinor,
    required this.spentMinor,
  });

  final String id;
  final String categoryId;
  final int limitMinor;
  final int spentMinor;
}

class BillReminder {
  const BillReminder({
    required this.id,
    required this.title,
    required this.amountMinor,
    required this.dueDate,
    required this.isPaid,
  });

  final String id;
  final String title;
  final int amountMinor;
  final DateTime dueDate;
  final bool isPaid;
}

class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.title,
    required this.targetMinor,
    required this.savedMinor,
    required this.targetDate,
  });

  final String id;
  final String title;
  final int targetMinor;
  final int savedMinor;
  final DateTime targetDate;
}
