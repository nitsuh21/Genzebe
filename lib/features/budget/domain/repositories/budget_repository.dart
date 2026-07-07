import 'package:genzebet/features/budget/domain/models/budget.dart';

abstract class BudgetRepository {
  Future<List<Budget>> getBudgets();
  Future<void> upsertBudget(Budget budget);
  Future<void> deleteBudget(String id);
}
