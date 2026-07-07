import 'package:genzebet/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzebet/features/transactions/domain/models/transaction_models.dart';
import 'package:genzebet/features/transactions/domain/repositories/ledger_repository.dart';

bool isOutflowType(TransactionType type) {
  return type == TransactionType.expense || type == TransactionType.transferOut;
}

bool isInflowType(TransactionType type) {
  return type == TransactionType.income || type == TransactionType.transferIn;
}

int signedMinorForRecord(TransactionRecord record) {
  return isOutflowType(record.type)
      ? -record.amount.minorUnits
      : record.amount.minorUnits;
}

class MonthlyReport {
  const MonthlyReport({
    required this.incomeMinor,
    required this.expenseMinor,
    required this.netMinor,
    required this.categoryTotalsMinor,
  });

  final int incomeMinor;
  final int expenseMinor;
  final int netMinor;
  final Map<String, int> categoryTotalsMinor;
}

class ReportService {
  ReportService(
    this._ledgerRepository,
    this._smsIngestionService,
  );

  final LedgerRepository _ledgerRepository;
  final SmsIngestionService _smsIngestionService;

  Future<MonthlyReport> generateCurrentMonthReport({
    Set<String> institutionCodes = const <String>{},
  }) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1);
    return generateReportForRange(
      startInclusive: start,
      endExclusive: end,
      institutionCodes: institutionCodes,
    );
  }

  Future<MonthlyReport> generateReportForRange({
    required DateTime startInclusive,
    required DateTime endExclusive,
    Set<String> institutionCodes = const <String>{},
  }) async {
    final transactions = await _filteredTransactions(
      institutionCodes: institutionCodes,
    );
    final scoped = _filterByRange(
      transactions,
      startInclusive: startInclusive,
      endExclusive: endExclusive,
    );
    return _toMonthlyReport(scoped);
  }

  Future<DashboardInsights> generateDashboardInsights({
    Set<String> institutionCodes = const <String>{},
  }) async {
    final transactions = await _filteredTransactions(
      institutionCodes: institutionCodes,
    );
    final filteredAccountIds = await _filteredAccountIds(
      institutionCodes: institutionCodes,
    );
    final now = DateTime.now();
    final currentStart = DateTime(now.year, now.month, 1);
    final currentEnd = DateTime(now.year, now.month + 1, 1);
    final previousStart = DateTime(now.year, now.month - 1, 1);
    final previousEnd = DateTime(now.year, now.month, 1);
    final currentMonth = _filterByRange(
      transactions,
      startInclusive: currentStart,
      endExclusive: currentEnd,
    );
    final previousMonth = _filterByRange(
      transactions,
      startInclusive: previousStart,
      endExclusive: previousEnd,
    );
    final currentTotals = _toMonthlyReport(currentMonth);
    final previousTotals = _toMonthlyReport(previousMonth);
    final currentNet = currentTotals.netMinor;
    final previousNet = previousTotals.netMinor;
    final netDeltaPct = previousNet == 0
        ? 0.0
        : ((currentNet - previousNet) / previousNet.abs()) * 100.0;
    final income = currentTotals.incomeMinor;
    final expense = currentTotals.expenseMinor;
    final expenseByCategory = currentTotals.categoryTotalsMinor;
    String topCategory = 'No data';
    int topCategoryAmount = 0;
    for (final entry in expenseByCategory.entries) {
      if (entry.value > topCategoryAmount) {
        topCategory = entry.key;
        topCategoryAmount = entry.value;
      }
    }
    final savingsRate =
        income == 0 ? 0.0 : ((income - expense) / income) * 100.0;
    final pendingReview = await _smsIngestionService.pendingReviewCount();
    final balancesByAccount = await _computeAccountBalances(
      transactions: transactions,
    );
    final accountCards = await _buildAccountCards(
      accountIdsFilter: filteredAccountIds,
      balancesByAccount: balancesByAccount,
    );
    final totalBalance = accountCards.fold<int>(
      0,
      (sum, card) => sum + card.balanceMinor,
    );
    final smsCount =
        transactions.where((t) => t.source == TransactionSource.sms).length;
    return DashboardInsights(
      netMinor: currentNet,
      totalBalanceMinor: totalBalance,
      incomeMinor: income,
      expenseMinor: expense,
      savingsRate: savingsRate.clamp(-100.0, 100.0).toDouble(),
      topExpenseCategory: topCategory,
      topExpenseShare: expense == 0
          ? 0.0
          : ((topCategoryAmount / expense) * 100.0).toDouble(),
      categoryTotalsMinor: expenseByCategory,
      pendingReviewCount: pendingReview,
      parserHealthScore: (100 - (pendingReview * 4)).clamp(0, 100),
      monthNetDeltaPercent: netDeltaPct.clamp(-100.0, 300.0).toDouble(),
      smsTransactionCount: smsCount,
      transactionCount: transactions.length,
      accountCards: accountCards,
    );
  }

  /// Income/expense totals for the trailing [months] months (oldest first).
  Future<List<MonthBucket>> monthlySeries({
    int months = 6,
    Set<String> institutionCodes = const <String>{},
  }) async {
    final transactions = await _filteredTransactions(
      institutionCodes: institutionCodes,
    );
    final now = DateTime.now();
    final buckets = <MonthBucket>[];
    for (var i = months - 1; i >= 0; i--) {
      final monthStart = DateTime(now.year, now.month - i, 1);
      var income = 0;
      var expense = 0;
      for (final record in transactions) {
        if (record.occurredAt.year == monthStart.year &&
            record.occurredAt.month == monthStart.month) {
          if (isOutflowType(record.type)) {
            expense += record.amount.minorUnits;
          } else if (isInflowType(record.type)) {
            income += record.amount.minorUnits;
          }
        }
      }
      buckets.add(
        MonthBucket(
          month: monthStart,
          incomeMinor: income,
          expenseMinor: expense,
        ),
      );
    }
    return buckets;
  }

  Future<List<AccountInsightCard>> _buildAccountCards({
    Set<String>? accountIdsFilter,
    Map<String, int>? balancesByAccount,
  }) async {
    var accounts = await _ledgerRepository.getAccounts();
    if (accountIdsFilter != null && accountIdsFilter.isNotEmpty) {
      accounts = accounts
          .where((account) => accountIdsFilter.contains(account.id))
          .toList(growable: false);
    }
    final balances =
        balancesByAccount ?? await _computeAccountBalances(transactions: null);
    if (accounts.isEmpty) {
      return const [
        AccountInsightCard(
          id: 'main-wallet',
          title: 'Primary Wallet',
          subtitle: 'Default account',
          balanceMinor: 0,
        ),
      ];
    }
    return accounts.map((account) {
      return AccountInsightCard(
        id: account.id,
        title: account.name,
        subtitle: account.institutionCode ?? account.kind,
        balanceMinor: balances[account.id] ?? 0,
      );
    }).toList(growable: false);
  }

  /// Computes a balance per account, preferring the most recent SMS statement
  /// balance (the real remaining balance reported by the bank/wallet) and
  /// falling back to the sum of ledger deltas when no statement balance exists.
  Future<Map<String, int>> _computeAccountBalances({
    required List<TransactionRecord>? transactions,
  }) async {
    final records = transactions ?? await _ledgerRepository.getTransactions();
    final ledger = await _ledgerRepository.getLedgerEntries();

    final latestStatementByAccount = <String, TransactionRecord>{};
    for (final record in records) {
      if (record.statementBalanceMinor == null) continue;
      final existing = latestStatementByAccount[record.accountId];
      if (existing == null ||
          record.occurredAt.isAfter(existing.occurredAt)) {
        latestStatementByAccount[record.accountId] = record;
      }
    }

    final ledgerByAccount = <String, int>{};
    for (final entry in ledger) {
      ledgerByAccount.update(
        entry.accountId,
        (value) => value + entry.delta.minorUnits,
        ifAbsent: () => entry.delta.minorUnits,
      );
    }

    final accountIds = <String>{
      ...latestStatementByAccount.keys,
      ...ledgerByAccount.keys,
    };
    final balances = <String, int>{};
    for (final accountId in accountIds) {
      final statement = latestStatementByAccount[accountId];
      if (statement != null) {
        balances[accountId] = statement.statementBalanceMinor!;
      } else {
        balances[accountId] = ledgerByAccount[accountId] ?? 0;
      }
    }
    return balances;
  }

  List<TransactionRecord> _filterByRange(
    List<TransactionRecord> records, {
    required DateTime startInclusive,
    required DateTime endExclusive,
  }) {
    return records.where((record) {
      return !record.occurredAt.isBefore(startInclusive) &&
          record.occurredAt.isBefore(endExclusive);
    }).toList(growable: false);
  }

  MonthlyReport _toMonthlyReport(List<TransactionRecord> records) {
    int income = 0;
    int expense = 0;
    final categoryTotals = <String, int>{};
    for (final entry in records) {
      if (isOutflowType(entry.type)) {
        expense += entry.amount.minorUnits;
        categoryTotals.update(
          entry.categoryId,
          (value) => value + entry.amount.minorUnits,
          ifAbsent: () => entry.amount.minorUnits,
        );
      } else if (isInflowType(entry.type)) {
        income += entry.amount.minorUnits;
      }
    }

    return MonthlyReport(
      incomeMinor: income,
      expenseMinor: expense,
      netMinor: income - expense,
      categoryTotalsMinor: categoryTotals,
    );
  }

  Future<List<TransactionRecord>> _filteredTransactions({
    required Set<String> institutionCodes,
  }) async {
    final transactions = await _ledgerRepository.getTransactions();
    if (institutionCodes.isEmpty) return transactions;
    final accountIds = await _filteredAccountIds(institutionCodes: institutionCodes);
    return transactions
        .where((tx) => accountIds.contains(tx.accountId))
        .toList(growable: false);
  }

  Future<Set<String>> _filteredAccountIds({
    required Set<String> institutionCodes,
  }) async {
    final accounts = await _ledgerRepository.getAccounts();
    if (institutionCodes.isEmpty) {
      return accounts.map((account) => account.id).toSet();
    }
    return accounts
        .where((account) {
          final code = account.institutionCode?.trim().toLowerCase();
          return code != null && institutionCodes.contains(code);
        })
        .map((account) => account.id)
        .toSet();
  }
}

class DashboardInsights {
  const DashboardInsights({
    required this.netMinor,
    required this.totalBalanceMinor,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.savingsRate,
    required this.topExpenseCategory,
    required this.topExpenseShare,
    required this.categoryTotalsMinor,
    required this.pendingReviewCount,
    required this.parserHealthScore,
    required this.monthNetDeltaPercent,
    required this.smsTransactionCount,
    required this.transactionCount,
    required this.accountCards,
  });

  final int netMinor;
  final int totalBalanceMinor;
  final int incomeMinor;
  final int expenseMinor;
  final double savingsRate;
  final String topExpenseCategory;
  final double topExpenseShare;
  final Map<String, int> categoryTotalsMinor;
  final int pendingReviewCount;
  final int parserHealthScore;
  final double monthNetDeltaPercent;
  final int smsTransactionCount;
  final int transactionCount;
  final List<AccountInsightCard> accountCards;
}

class MonthBucket {
  const MonthBucket({
    required this.month,
    required this.incomeMinor,
    required this.expenseMinor,
  });

  final DateTime month;
  final int incomeMinor;
  final int expenseMinor;

  int get netMinor => incomeMinor - expenseMinor;
}

class AccountInsightCard {
  const AccountInsightCard({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.balanceMinor,
  });

  final String id;
  final String title;
  final String subtitle;
  final int balanceMinor;
}
