/// A monthly spending plan.
///
/// [categoryIds] can be empty which means a general budget that applies to
/// all spending categories.
class Budget {
  const Budget({
    required this.id,
    required this.name,
    required this.categoryIds,
    this.institutionCodes = const [],
    this.excludedTransactionIds = const [],
    required this.limitMinor,
    required this.createdAt,
  });

  final String id;
  final String name;
  final List<String> categoryIds;
  final List<String> institutionCodes;
  final List<String> excludedTransactionIds;
  final int limitMinor;
  final DateTime createdAt;

  bool get isGeneral => categoryIds.isEmpty;
  bool get isAllInstitutions => institutionCodes.isEmpty;

  Budget copyWith({
    String? name,
    List<String>? categoryIds,
    List<String>? institutionCodes,
    List<String>? excludedTransactionIds,
    int? limitMinor,
  }) {
    return Budget(
      id: id,
      name: name ?? this.name,
      categoryIds: categoryIds ?? this.categoryIds,
      institutionCodes: institutionCodes ?? this.institutionCodes,
      excludedTransactionIds:
          excludedTransactionIds ?? this.excludedTransactionIds,
      limitMinor: limitMinor ?? this.limitMinor,
      createdAt: createdAt,
    );
  }
}

/// A budget paired with its actual spend for the current period.
class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.spentMinor,
  });

  final Budget budget;
  final int spentMinor;

  int get remainingMinor => budget.limitMinor - spentMinor;

  double get ratio {
    if (budget.limitMinor <= 0) return 0;
    return spentMinor / budget.limitMinor;
  }

  bool get isOverBudget => spentMinor > budget.limitMinor;
}

/// Aggregated view of all budgets for a period.
class BudgetOverview {
  const BudgetOverview({
    required this.items,
    required this.totalLimitMinor,
    required this.totalSpentMinor,
    required this.unbudgetedSpendMinor,
  });

  final List<BudgetProgress> items;
  final int totalLimitMinor;
  final int totalSpentMinor;

  /// Spend in the current month that has no matching budget category.
  final int unbudgetedSpendMinor;

  int get remainingMinor => totalLimitMinor - totalSpentMinor;

  double get ratio {
    if (totalLimitMinor <= 0) return 0;
    return totalSpentMinor / totalLimitMinor;
  }
}
