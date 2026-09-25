import 'package:genzeb/core/db/app_database.dart';
import 'package:genzeb/features/alerts/domain/money_alert.dart';
import 'package:sqflite/sqflite.dart';

class SqfliteMoneyAlertRepository implements MoneyAlertRepository {
  SqfliteMoneyAlertRepository(this._database);

  final AppDatabase _database;

  Future<Database> get _db => _database.database;

  @override
  Future<List<MoneyAlert>> getAll({int limit = 200}) async {
    final db = await _db;
    final rows = await db.query(
      'money_alerts',
      orderBy: 'occurredAt DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> saveAll(List<MoneyAlert> alerts) async {
    if (alerts.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    for (final alert in alerts) {
      batch.insert(
        'money_alerts',
        _toRow(alert),
        // An alert per transaction, once: a re-sync never re-notifies.
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> markAllRead() async {
    final db = await _db;
    await db.update('money_alerts', {'isRead': 1}, where: 'isRead = 0');
  }

  @override
  Future<void> markRead(String id) async {
    final db = await _db;
    await db.update(
      'money_alerts',
      {'isRead': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> clear() async {
    final db = await _db;
    await db.delete('money_alerts');
  }

  Map<String, Object?> _toRow(MoneyAlert alert) => {
        'id': alert.id,
        'transactionId': alert.transactionId,
        'isIncome': alert.isIncome ? 1 : 0,
        'amountMinor': alert.amountMinor,
        'institutionCode': alert.institutionCode,
        'counterparty': alert.counterparty,
        'categoryId': alert.categoryId,
        'needsReview': alert.needsReview ? 1 : 0,
        'occurredAt': alert.occurredAt.toIso8601String(),
        'createdAt': alert.createdAt.toIso8601String(),
        'isRead': alert.isRead ? 1 : 0,
      };

  MoneyAlert _fromRow(Map<String, Object?> row) => MoneyAlert(
        id: row['id'] as String,
        transactionId: row['transactionId'] as String,
        isIncome: (row['isIncome'] as int) == 1,
        amountMinor: row['amountMinor'] as int,
        institutionCode: row['institutionCode'] as String?,
        counterparty: row['counterparty'] as String?,
        categoryId: row['categoryId'] as String?,
        needsReview: (row['needsReview'] as int) == 1,
        occurredAt: DateTime.parse(row['occurredAt'] as String),
        createdAt: DateTime.parse(row['createdAt'] as String),
        isRead: (row['isRead'] as int) == 1,
      );
}

class InMemoryMoneyAlertRepository implements MoneyAlertRepository {
  final Map<String, MoneyAlert> _alerts = {};

  @override
  Future<List<MoneyAlert>> getAll({int limit = 200}) async {
    final all = _alerts.values.toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return all.take(limit).toList(growable: false);
  }

  @override
  Future<void> saveAll(List<MoneyAlert> alerts) async {
    for (final alert in alerts) {
      _alerts.putIfAbsent(alert.id, () => alert);
    }
  }

  @override
  Future<void> markAllRead() async {
    _alerts.updateAll((_, alert) => alert.copyWith(isRead: true));
  }

  @override
  Future<void> markRead(String id) async {
    final alert = _alerts[id];
    if (alert != null) _alerts[id] = alert.copyWith(isRead: true);
  }

  @override
  Future<void> clear() async => _alerts.clear();
}
