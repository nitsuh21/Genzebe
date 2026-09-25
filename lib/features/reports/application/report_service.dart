import 'package:genzeb/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart'
    show extractItemizedFeesMinor, extractMerchant, normalizeMerchant;
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:genzeb/features/transactions/domain/repositories/ledger_repository.dart';

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
    this.internalMovedMinor = 0,
    this.feesMinor = 0,
    this.pendingCount = 0,
    this.incomeByCategoryMinor = const {},
  });

  /// Real inflows: internal transfer legs and unconfirmed parses excluded.
  final int incomeMinor;

  /// Real outflows: internal transfer legs excluded; their fee delta counts.
  final int expenseMinor;
  final int netMinor;
  final Map<String, int> categoryTotalsMinor;

  /// Money moved between the user's own accounts (counted once).
  final int internalMovedMinor;

  /// Bank charges: itemized receipt fees + fees-category transactions.
  final int feesMinor;

  /// Parses awaiting review — excluded from every total above.
  final int pendingCount;

  final Map<String, int> incomeByCategoryMinor;
}

/// Result of classifying transactions into real flows vs internal movements.
class FlowAnalysis {
  const FlowAnalysis({
    required this.internalIds,
    required this.pairFeeByOutflowId,
  });

  /// Transaction ids that are legs of an own-account movement (both legs of
  /// a matched pair, plus outflows into own savings).
  final Set<String> internalIds;

  /// For matched pairs: outflow-leg id -> fee delta (outflow - inflow).
  final Map<String, int> pairFeeByOutflowId;
}

class MerchantSpend {
  const MerchantSpend({
    required this.name,
    required this.totalMinor,
    required this.count,
    this.transactionIds = const {},
  });

  final String name;
  final int totalMinor;
  final int count;
  final Set<String> transactionIds;
}

class BalancePoint {
  const BalancePoint({required this.at, required this.balanceMinor});

  final DateTime at;
  final int balanceMinor;
}

/// Everything the Reports page renders for one period, computed on real
/// flows so the numbers reconcile with each other.
class PeriodReport {
  const PeriodReport({
    required this.totals,
    required this.previousTotals,
    required this.topMerchants,
    required this.biggestSpends,
    required this.balanceSeries,
    required this.daysElapsed,
    required this.daysTotal,
    required this.scopedTransactions,
    required this.internalIds,
    required this.feeByTransactionId,
  });

  /// Confirmed transactions inside the period (for drill-down and export).
  final List<TransactionRecord> scopedTransactions;

  /// Ids classified as own-account movements.
  final Set<String> internalIds;

  /// Transactions that carried a bank fee, with the fee amount per id.
  final Map<String, int> feeByTransactionId;

  final MonthlyReport totals;

  /// Same-length window immediately before the period, for comparisons.
  final MonthlyReport previousTotals;
  final List<MerchantSpend> topMerchants;
  final List<TransactionRecord> biggestSpends;

  /// Total of bank-reported statement balances over time (carry-forward).
  final List<BalancePoint> balanceSeries;
  final int daysElapsed;
  final int daysTotal;

  int get dailyAverageExpenseMinor =>
      daysElapsed <= 0 ? 0 : totals.expenseMinor ~/ daysElapsed;

  int get projectedExpenseMinor => dailyAverageExpenseMinor * daysTotal;
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
    // Flow analysis runs on the full history so a transfer pair straddling
    // the range boundary is still recognized.
    final flows = analyzeFlows(transactions);
    final scoped = _filterByRange(
      transactions,
      startInclusive: startInclusive,
      endExclusive: endExclusive,
    );
    return _toMonthlyReport(scoped, flows: flows);
  }

  /// Everything the Reports page needs for one period, in a single pass.
  Future<PeriodReport> generatePeriodReport({
    required DateTime startInclusive,
    required DateTime endExclusive,
    Set<String> institutionCodes = const <String>{},
  }) async {
    final transactions = await _filteredTransactions(
      institutionCodes: institutionCodes,
    );
    final flows = analyzeFlows(transactions);
    final scoped = _filterByRange(
      transactions,
      startInclusive: startInclusive,
      endExclusive: endExclusive,
    );
    final totals = _toMonthlyReport(scoped, flows: flows);

    final length = endExclusive.difference(startInclusive);
    final previous = _toMonthlyReport(
      _filterByRange(
        transactions,
        startInclusive: startInclusive.subtract(length),
        endExclusive: startInclusive,
      ),
      flows: flows,
    );

    // Real spending rows for merchant + biggest lists.
    final spends = scoped
        .where((tx) =>
            tx.reviewStatus != TransactionReviewStatus.pendingReview &&
            isOutflowType(tx.type) &&
            !flows.internalIds.contains(tx.id))
        .toList(growable: false);

    final merchantTotals = <String, MerchantSpend>{};
    for (final tx in spends) {
      final snippet = tx.smsSnippet;
      if (snippet == null) continue;
      final merchant = extractMerchant(snippet, isExpense: true);
      if (merchant == null) continue;
      final key = normalizeMerchant(merchant);
      final existing = merchantTotals[key];
      merchantTotals[key] = MerchantSpend(
        name: existing?.name ?? merchant,
        totalMinor: (existing?.totalMinor ?? 0) + tx.amount.minorUnits,
        count: (existing?.count ?? 0) + 1,
        transactionIds: {...?existing?.transactionIds, tx.id},
      );
    }
    final topMerchants = merchantTotals.values.toList()
      ..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));

    final biggest = List<TransactionRecord>.from(spends)
      ..sort((a, b) => b.amount.minorUnits.compareTo(a.amount.minorUnits));

    final now = DateTime.now();
    final endForElapsed = now.isBefore(endExclusive) ? now : endExclusive;
    final daysElapsed = endForElapsed.difference(startInclusive).inDays + 1;
    final daysTotal = length.inDays;

    return PeriodReport(
      totals: totals,
      previousTotals: previous,
      topMerchants: topMerchants.take(5).toList(growable: false),
      biggestSpends: biggest.take(5).toList(growable: false),
      balanceSeries: _balanceSeries(
        transactions,
        startInclusive: startInclusive,
        endExclusive: endExclusive,
      ),
      daysElapsed: daysElapsed.clamp(1, 1 << 30),
      daysTotal: daysTotal.clamp(1, 1 << 30),
      scopedTransactions: scoped
          .where(
              (tx) => tx.reviewStatus != TransactionReviewStatus.pendingReview)
          .toList(growable: false),
      internalIds: flows.internalIds,
      feeByTransactionId: {
        for (final tx in scoped)
          if (_feesFor(tx, flows) > 0) tx.id: _feesFor(tx, flows),
      },
    );
  }

  /// Total of the latest bank-reported statement balances over time. Real
  /// numbers straight from the SMS receipts — no reconstruction.
  List<BalancePoint> _balanceSeries(
    List<TransactionRecord> transactions, {
    required DateTime startInclusive,
    required DateTime endExclusive,
  }) {
    final events = transactions
        .where((tx) => tx.statementBalanceMinor != null)
        .toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    if (events.isEmpty) return const [];

    final latestByAccount = <String, int>{};
    final points = <BalancePoint>[];
    for (final tx in events) {
      latestByAccount[tx.accountId] = tx.statementBalanceMinor!;
      if (tx.occurredAt.isBefore(startInclusive) ||
          !tx.occurredAt.isBefore(endExclusive)) {
        continue;
      }
      final total = latestByAccount.values.fold<int>(0, (sum, v) => sum + v);
      points.add(BalancePoint(at: tx.occurredAt, balanceMinor: total));
    }
    // Cap the point count for painting.
    if (points.length <= 80) return points;
    final step = points.length / 80;
    return [
      for (var i = 0; i < 80; i++) points[(i * step).floor()],
      points.last,
    ];
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
    final flows = analyzeFlows(transactions);
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
    final currentTotals = _toMonthlyReport(currentMonth, flows: flows);
    final previousTotals = _toMonthlyReport(previousMonth, flows: flows);
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
      internalMovedMinor: currentTotals.internalMovedMinor,
      feesMinor: currentTotals.feesMinor,
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
    final flows = analyzeFlows(transactions);
    final now = DateTime.now();
    final buckets = <MonthBucket>[];
    for (var i = months - 1; i >= 0; i--) {
      final monthStart = DateTime(now.year, now.month - i, 1);
      var income = 0;
      var expense = 0;
      for (final record in transactions) {
        if (record.reviewStatus == TransactionReviewStatus.pendingReview) {
          continue;
        }
        if (flows.internalIds.contains(record.id)) continue;
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
        institutionCode: account.institutionCode,
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
      if (existing == null || record.occurredAt.isAfter(existing.occurredAt)) {
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

  /// Detects own-account movements so they never masquerade as income or
  /// spending. Deliberately conservative — a false pair silently deletes
  /// real income AND real spending, which is worse than missing a transfer:
  ///  - The OUTFLOW leg must actually look like a transfer (transfer_out /
  ///    savings category, or the receipt says "transfer"). A grocery
  ///    payment can never be swallowed by a coincidental same-amount credit.
  ///  - The inflow leg must not be salary.
  ///  - Legs must be on DIFFERENT accounts, within 3 hours (bank->wallet
  ///    hops land in minutes), amounts equal up to a plausible fee
  ///    (<= 2% or ETB 25).
  ///  - Outflows categorized as savings are money the user keeps.
  static FlowAnalysis analyzeFlows(List<TransactionRecord> records) {
    final confirmed = records
        .where((tx) => tx.reviewStatus != TransactionReviewStatus.pendingReview)
        .toList(growable: false);

    bool transferishOutflow(TransactionRecord tx) {
      if (tx.type == TransactionType.transferOut) return true;
      if (tx.categoryId == 'transfer_out' || tx.categoryId == 'savings') {
        return true;
      }
      final snippet = tx.smsSnippet?.toLowerCase();
      return snippet != null && snippet.contains('transfer');
    }

    final outflows = confirmed
        .where((tx) => isOutflowType(tx.type) && transferishOutflow(tx))
        .toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final inflows = confirmed
        .where((tx) => isInflowType(tx.type) && tx.categoryId != 'salary')
        .toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    final internalIds = <String>{};
    final pairFees = <String, int>{};
    final usedInflows = <String>{};

    bool feeTolerated(int outMinor, int inMinor) {
      final delta = outMinor - inMinor;
      if (delta < 0) return false;
      final tolerance =
          (outMinor * 0.02).round() > 2500 ? (outMinor * 0.02).round() : 2500;
      return delta <= tolerance;
    }

    for (final out in outflows) {
      TransactionRecord? best;
      Duration? bestGap;
      for (final inn in inflows) {
        if (usedInflows.contains(inn.id)) continue;
        if (inn.accountId == out.accountId) continue;
        final gap = inn.occurredAt.difference(out.occurredAt).abs();
        if (gap > const Duration(hours: 3)) continue;
        if (!feeTolerated(out.amount.minorUnits, inn.amount.minorUnits)) {
          continue;
        }
        if (best == null || gap < bestGap!) {
          best = inn;
          bestGap = gap;
        }
      }
      if (best != null) {
        usedInflows.add(best.id);
        internalIds
          ..add(out.id)
          ..add(best.id);
        pairFees[out.id] = out.amount.minorUnits - best.amount.minorUnits;
      } else if (out.categoryId == 'savings') {
        internalIds.add(out.id);
      }
    }
    return FlowAnalysis(
      internalIds: internalIds,
      pairFeeByOutflowId: pairFees,
    );
  }

  /// Bank charges for one transaction. Itemized receipt fees are the ground
  /// truth: a big debit that merely MENTIONS "service charge" (or was once
  /// miscategorized as fees) contributes only its itemized charge — never
  /// its whole amount. Only a pure charge SMS with no itemization counts
  /// fully.
  static int _feesFor(TransactionRecord tx, FlowAnalysis flows) {
    if (tx.reviewStatus == TransactionReviewStatus.pendingReview) return 0;
    final itemized =
        tx.smsSnippet == null ? 0 : extractItemizedFeesMinor(tx.smsSnippet!);
    final pairFee = flows.pairFeeByOutflowId[tx.id];
    if (pairFee != null) return pairFee > itemized ? pairFee : itemized;
    if (!isOutflowType(tx.type)) return 0;
    if (itemized > 0) return itemized;
    if (tx.categoryId == 'fees') return tx.amount.minorUnits;
    return 0;
  }

  MonthlyReport _toMonthlyReport(
    List<TransactionRecord> records, {
    FlowAnalysis? flows,
  }) {
    final analysis = flows ?? analyzeFlows(records);
    int income = 0;
    int expense = 0;
    int internal = 0;
    int fees = 0;
    int pending = 0;
    final categoryTotals = <String, int>{};
    final incomeByCategory = <String, int>{};

    for (final entry in records) {
      // Unconfirmed parses must never inflate totals — they count only after
      // the user approves them in Review.
      if (entry.reviewStatus == TransactionReviewStatus.pendingReview) {
        pending += 1;
        continue;
      }
      fees += _feesFor(entry, analysis);

      if (analysis.internalIds.contains(entry.id)) {
        if (isOutflowType(entry.type)) {
          internal += entry.amount.minorUnits;
          // The fee delta of an internal pair is real money lost.
          final pairFee = analysis.pairFeeByOutflowId[entry.id] ?? 0;
          if (pairFee > 0) {
            expense += pairFee;
            categoryTotals.update(
              'fees',
              (value) => value + pairFee,
              ifAbsent: () => pairFee,
            );
          }
        }
        continue;
      }

      if (isOutflowType(entry.type)) {
        expense += entry.amount.minorUnits;
        categoryTotals.update(
          entry.categoryId,
          (value) => value + entry.amount.minorUnits,
          ifAbsent: () => entry.amount.minorUnits,
        );
      } else if (isInflowType(entry.type)) {
        income += entry.amount.minorUnits;
        incomeByCategory.update(
          entry.categoryId,
          (value) => value + entry.amount.minorUnits,
          ifAbsent: () => entry.amount.minorUnits,
        );
      }
    }

    return MonthlyReport(
      incomeMinor: income,
      expenseMinor: expense,
      netMinor: income - expense,
      categoryTotalsMinor: categoryTotals,
      internalMovedMinor: internal,
      feesMinor: fees,
      pendingCount: pending,
      incomeByCategoryMinor: incomeByCategory,
    );
  }

  Future<List<TransactionRecord>> _filteredTransactions({
    required Set<String> institutionCodes,
  }) async {
    final transactions = await _ledgerRepository.getTransactions();
    if (institutionCodes.isEmpty) return transactions;
    final accountIds =
        await _filteredAccountIds(institutionCodes: institutionCodes);
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
    this.internalMovedMinor = 0,
    this.feesMinor = 0,
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
  final int internalMovedMinor;
  final int feesMinor;
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
    this.institutionCode,
  });

  final String id;
  final String title;
  final String subtitle;
  final int balanceMinor;
  final String? institutionCode;
}
