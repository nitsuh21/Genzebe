import 'package:genzeb/features/alerts/domain/money_alert.dart';
import 'package:genzeb/features/budget/application/budget_service.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/sync/application/sync_service.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';

class MoneyAlertService {
  MoneyAlertService(this._repository, {BudgetService? budgets})
      : _budgets = budgets;

  final MoneyAlertRepository _repository;

  /// When set, an alert also says which budget its spending pushed past
  /// 80% or over the limit.
  final BudgetService? _budgets;

  /// Only money that moved recently is news. Older rows surfacing in a sync
  /// (late provider writes, a long gap since the last open) are booked
  /// quietly instead of flooding the user with stale alerts.
  static const freshness = Duration(days: 3);

  /// Records an alert for every fresh money-in / money-out transaction the
  /// sync created and returns them (for the in-app banner). The first,
  /// history-importing sync never alerts — that's backfill, not news.
  Future<List<MoneyAlert>> recordFromSync(
    ForceSyncResult result, {
    DateTime? now,
  }) async {
    if (!result.wasIncremental) return const [];
    final clock = now ?? DateTime.now();
    final fresh = [
      for (final tx in result.newTransactions)
        if (clock.difference(tx.occurredAt) <= freshness) tx,
    ];
    final notes = await _budgetNotes(fresh, clock);
    final alerts = <MoneyAlert>[
      for (final tx in fresh) alertFor(tx, clock, budgetNote: notes[tx.id]),
    ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    await _repository.saveAll(alerts);
    return alerts;
  }

  /// Records the alert for one transaction booked in the background (a
  /// bank SMS that arrived while the app was closed).
  Future<MoneyAlert> recordTransaction(TransactionRecord tx) async {
    final clock = DateTime.now();
    final notes = await _budgetNotes([tx], clock);
    final alert = alertFor(tx, clock, budgetNote: notes[tx.id]);
    await _repository.saveAll([alert]);
    return alert;
  }

  /// Transaction id -> budget warning text, for the transactions that
  /// crossed a budget line. A failed budget check never blocks the alert.
  Future<Map<String, String>> _budgetNotes(
    List<TransactionRecord> transactions,
    DateTime now,
  ) async {
    final budgets = _budgets;
    if (budgets == null || transactions.isEmpty) return const {};
    try {
      final warnings = await budgets.warningsFor(transactions, now: now);
      final notes = <String, List<String>>{};
      for (final warning in warnings) {
        (notes[warning.transactionId] ??= []).add(warning.message);
      }
      return {
        for (final entry in notes.entries) entry.key: entry.value.join('\n'),
      };
    } catch (_) {
      return const {};
    }
  }

  MoneyAlert alertFor(
    TransactionRecord tx,
    DateTime now, {
    String? budgetNote,
  }) {
    final isIncome = tx.type == TransactionType.income;
    final body = tx.smsSnippet;
    final sender = tx.smsSender;
    return MoneyAlert(
      id: 'alert-${tx.id}',
      transactionId: tx.id,
      isIncome: isIncome,
      amountMinor: tx.amount.minorUnits,
      institutionCode:
          sender == null ? null : institutionForSender(sender).name,
      counterparty:
          body == null ? null : extractMerchant(body, isExpense: !isIncome),
      categoryId: tx.categoryId,
      needsReview: tx.reviewStatus == TransactionReviewStatus.pendingReview,
      occurredAt: tx.occurredAt,
      createdAt: now,
      budgetNote: budgetNote,
    );
  }

  Future<List<MoneyAlert>> getAll() => _repository.getAll();
  Future<void> markAllRead() => _repository.markAllRead();
  Future<void> markRead(String id) => _repository.markRead(id);
}
