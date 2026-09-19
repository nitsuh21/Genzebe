import 'package:genzeb/features/budget/domain/models/budget.dart';
import 'package:genzeb/features/budget/domain/repositories/budget_repository.dart';
import 'package:genzeb/features/reports/application/report_service.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:genzeb/features/transactions/domain/repositories/ledger_repository.dart';

class BudgetService {
  BudgetService({
    required BudgetRepository budgetRepository,
    required LedgerRepository ledgerRepository,
  })  : _budgetRepository = budgetRepository,
        _ledgerRepository = ledgerRepository;

  final BudgetRepository _budgetRepository;
  final LedgerRepository _ledgerRepository;

  Future<List<Budget>> getBudgets() => _budgetRepository.getBudgets();

  Future<void> saveBudget(Budget budget) =>
      _budgetRepository.upsertBudget(budget);

  Future<void> deleteBudget(String id) => _budgetRepository.deleteBudget(id);

  /// Builds an overview of all budgets against actual spend in the current
  /// calendar month, derived from the live ledger transactions.
  Future<BudgetOverview> buildOverview({
    Set<String> institutionCodes = const <String>{},
  }) async {
    final budgets = await _budgetRepository.getBudgets();
    final monthOutflows = await _currentMonthOutflows(
      institutionCodes: institutionCodes,
    );
    final accounts = await _ledgerRepository.getAccounts();
    final institutionByAccount = <String, String>{};
    for (final account in accounts) {
      institutionByAccount[account.id] =
          account.institutionCode?.trim().toLowerCase() ?? '';
    }
    final spendByCategory = _spendByCategory(monthOutflows);

    final items = <BudgetProgress>[];
    var totalLimit = 0;
    var totalSpent = 0;
    final coveredCategories = <String>{};
    var hasGeneralBudget = false;
    for (final budget in budgets) {
      final spent = _spentForBudget(
        budget: budget,
        records: monthOutflows,
        institutionByAccount: institutionByAccount,
      );
      if (budget.isGeneral) {
        hasGeneralBudget = true;
      } else {
        coveredCategories.addAll(budget.categoryIds);
      }
      totalLimit += budget.limitMinor;
      totalSpent += spent;
      items.add(BudgetProgress(budget: budget, spentMinor: spent));
    }
    items.sort((a, b) => b.ratio.compareTo(a.ratio));

    final unbudgeted = hasGeneralBudget
        ? 0
        : _sumForCategories(
            spendByCategory,
            spendByCategory.keys
                .where((category) => !coveredCategories.contains(category))
                .toList(growable: false),
          );

    return BudgetOverview(
      items: items,
      totalLimitMinor: totalLimit,
      totalSpentMinor: totalSpent,
      unbudgetedSpendMinor: unbudgeted,
    );
  }

  Future<List<TransactionRecord>> _currentMonthOutflows({
    required Set<String> institutionCodes,
  }) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1);

    var transactions = await _ledgerRepository.getTransactions();
    // Moving money between your own accounts (bank -> wallet top-up) is not
    // spending; pair the legs the same way Reports does and drop them.
    final internalIds = ReportService.analyzeFlows(transactions).internalIds;
    if (institutionCodes.isNotEmpty) {
      final accounts = await _ledgerRepository.getAccounts();
      final allowedIds = accounts
          .where((account) {
            final code = account.institutionCode?.trim().toLowerCase();
            return code != null && institutionCodes.contains(code);
          })
          .map((account) => account.id)
          .toSet();
      transactions = transactions
          .where((tx) => allowedIds.contains(tx.accountId))
          .toList(growable: false);
    }

    final outflows = <TransactionRecord>[];
    for (final tx in transactions) {
      if (!isOutflowType(tx.type)) continue;
      if (tx.occurredAt.isBefore(start) || !tx.occurredAt.isBefore(end)) {
        continue;
      }
      if (internalIds.contains(tx.id)) continue;
      // Unconfirmed parses stay out of budgets, matching Reports and the
      // ledger total.
      if (tx.reviewStatus == TransactionReviewStatus.pendingReview) continue;
      outflows.add(tx);
    }
    return outflows;
  }

  Map<String, int> _spendByCategory(List<TransactionRecord> records) {
    final spend = <String, int>{};
    for (final tx in records) {
      spend.update(
        tx.categoryId,
        (value) => value + tx.amount.minorUnits,
        ifAbsent: () => tx.amount.minorUnits,
      );
    }
    return spend;
  }

  int _spentForBudget({
    required Budget budget,
    required List<TransactionRecord> records,
    required Map<String, String> institutionByAccount,
  }) {
    var sum = 0;
    for (final tx in records) {
      if (budget.excludedTransactionIds.contains(tx.id)) continue;
      if (budget.institutionCodes.isNotEmpty) {
        final code = institutionByAccount[tx.accountId] ?? '';
        if (!budget.institutionCodes.contains(code)) continue;
      }
      if (!budget.isGeneral && !budget.categoryIds.contains(tx.categoryId)) {
        continue;
      }
      sum += tx.amount.minorUnits;
    }
    return sum;
  }

  int _sumForCategories(
      Map<String, int> spendByCategory, List<String> categories) {
    var sum = 0;
    for (final category in categories) {
      sum += spendByCategory[category] ?? 0;
    }
    return sum;
  }
}
