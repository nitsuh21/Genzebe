import 'package:genzeb/features/budget/domain/models/budget.dart';
import 'package:genzeb/features/budget/domain/repositories/budget_repository.dart';

class InMemoryBudgetRepository implements BudgetRepository {
  final Map<String, Budget> _budgets = {};

  @override
  Future<List<Budget>> getBudgets() async {
    final values = _budgets.values.toList(growable: false);
    values.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return values;
  }

  @override
  Future<void> upsertBudget(Budget budget) async {
    _budgets[budget.id] = budget;
  }

  @override
  Future<void> deleteBudget(String id) async {
    _budgets.remove(id);
  }
}
