/// One "money in / money out" notification shown inside the app, raised
/// when a bank or wallet SMS arrives and becomes a transaction.
class MoneyAlert {
  const MoneyAlert({
    required this.id,
    required this.transactionId,
    required this.isIncome,
    required this.amountMinor,
    required this.occurredAt,
    required this.createdAt,
    this.institutionCode,
    this.counterparty,
    this.categoryId,
    this.needsReview = false,
    this.isRead = false,
    this.budgetNote,
  });

  final String id;
  final String transactionId;
  final bool isIncome;
  final int amountMinor;
  final String? institutionCode;

  /// Merchant or person on the other side, when the SMS names one.
  final String? counterparty;

  /// Transaction type ("transfer_in", "salary", "groceries", ...).
  final String? categoryId;

  /// The parse was uncertain; the transaction waits in the review queue.
  final bool needsReview;
  final DateTime occurredAt;
  final DateTime createdAt;
  final bool isRead;

  /// Set when this spending pushed a budget past 80% or over its limit:
  /// "Food budget is 85% used · 9 days left". Never contains amounts.
  final String? budgetNote;

  MoneyAlert copyWith({bool? isRead, String? budgetNote}) {
    return MoneyAlert(
      id: id,
      transactionId: transactionId,
      isIncome: isIncome,
      amountMinor: amountMinor,
      occurredAt: occurredAt,
      createdAt: createdAt,
      institutionCode: institutionCode,
      counterparty: counterparty,
      categoryId: categoryId,
      needsReview: needsReview,
      isRead: isRead ?? this.isRead,
      budgetNote: budgetNote ?? this.budgetNote,
    );
  }
}

abstract class MoneyAlertRepository {
  /// Newest first.
  Future<List<MoneyAlert>> getAll({int limit = 200});
  Future<void> saveAll(List<MoneyAlert> alerts);
  Future<void> markAllRead();
  Future<void> markRead(String id);
  Future<void> clear();
}
