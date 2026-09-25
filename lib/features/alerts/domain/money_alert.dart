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
    this.needsReview = false,
    this.isRead = false,
  });

  final String id;
  final String transactionId;
  final bool isIncome;
  final int amountMinor;
  final String? institutionCode;

  /// Merchant or person on the other side, when the SMS names one.
  final String? counterparty;

  /// The parse was uncertain; the transaction waits in the review queue.
  final bool needsReview;
  final DateTime occurredAt;
  final DateTime createdAt;
  final bool isRead;

  MoneyAlert copyWith({bool? isRead}) {
    return MoneyAlert(
      id: id,
      transactionId: transactionId,
      isIncome: isIncome,
      amountMinor: amountMinor,
      occurredAt: occurredAt,
      createdAt: createdAt,
      institutionCode: institutionCode,
      counterparty: counterparty,
      needsReview: needsReview,
      isRead: isRead ?? this.isRead,
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
