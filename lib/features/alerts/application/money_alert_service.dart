import 'package:genzeb/features/alerts/domain/money_alert.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/sync/application/sync_service.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';

class MoneyAlertService {
  MoneyAlertService(this._repository);

  final MoneyAlertRepository _repository;

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
    final alerts = <MoneyAlert>[
      for (final tx in result.newTransactions)
        if (clock.difference(tx.occurredAt) <= freshness) alertFor(tx, clock),
    ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    await _repository.saveAll(alerts);
    return alerts;
  }

  /// Records the alert for one transaction booked in the background (a
  /// bank SMS that arrived while the app was closed).
  Future<MoneyAlert> recordTransaction(TransactionRecord tx) async {
    final alert = alertFor(tx, DateTime.now());
    await _repository.saveAll([alert]);
    return alert;
  }

  MoneyAlert alertFor(TransactionRecord tx, DateTime now) {
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
      needsReview: tx.reviewStatus == TransactionReviewStatus.pendingReview,
      occurredAt: tx.occurredAt,
      createdAt: now,
    );
  }

  Future<List<MoneyAlert>> getAll() => _repository.getAll();
  Future<void> markAllRead() => _repository.markAllRead();
  Future<void> markRead(String id) => _repository.markRead(id);
}
