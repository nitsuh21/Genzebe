import 'package:genzeb/core/db/app_database.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/sms_message_repository.dart';
import 'package:sqflite/sqflite.dart';

/// Persistent [SmsMessageRepository] backed by on-device SQLite, so ingestion
/// and review decisions survive app restarts.
class SqfliteSmsMessageRepository implements SmsMessageRepository {
  SqfliteSmsMessageRepository(this._database);

  final AppDatabase _database;

  Future<Database> get _db => _database.database;

  @override
  Future<StoredSmsMessage?> getByHash(String messageHash) async {
    final db = await _db;
    final rows = await db.query(
      'sms_messages',
      where: 'messageHash = ?',
      whereArgs: [messageHash],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapRow(rows.first);
  }

  @override
  Future<StoredSmsMessage?> getById(String smsId) async {
    final db = await _db;
    final rows = await db.query(
      'sms_messages',
      where: 'id = ?',
      whereArgs: [smsId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapRow(rows.first);
  }

  @override
  Future<List<StoredSmsMessage>> getAll() async {
    final db = await _db;
    final rows = await db.query('sms_messages', orderBy: 'receivedAt DESC');
    return rows.map(_mapRow).toList(growable: false);
  }

  @override
  Future<List<StoredSmsMessage>> getByStatus(SmsIngestionStatus status) async {
    final db = await _db;
    final rows = await db.query(
      'sms_messages',
      where: 'status = ?',
      whereArgs: [status.name],
    );
    return rows.map(_mapRow).toList(growable: false);
  }

  @override
  Future<void> delete(String smsId) async {
    final db = await _db;
    await db.delete('sms_messages', where: 'id = ?', whereArgs: [smsId]);
  }

  @override
  Future<void> save(StoredSmsMessage message) async {
    final db = await _db;
    await db.insert(
      'sms_messages',
      {
        'id': message.sms.id,
        'sender': message.sms.sender,
        'body': message.sms.body,
        'receivedAt': message.sms.receivedAt.toIso8601String(),
        'messageHash': message.messageHash,
        'status': message.status.name,
        'parsedTransactionId': message.parsedTransactionId,
        'failureReason': message.failureReason,
        'ingestedAt': message.ingestedAt?.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  StoredSmsMessage _mapRow(Map<String, Object?> row) {
    return StoredSmsMessage(
      sms: SmsMessage(
        id: row['id'] as String,
        sender: row['sender'] as String,
        body: row['body'] as String,
        receivedAt: DateTime.parse(row['receivedAt'] as String),
      ),
      messageHash: row['messageHash'] as String,
      status: _parseStatus(row['status'] as String),
      parsedTransactionId: row['parsedTransactionId'] as String?,
      failureReason: row['failureReason'] as String?,
      ingestedAt: row['ingestedAt'] == null
          ? null
          : DateTime.parse(row['ingestedAt'] as String),
    );
  }

  SmsIngestionStatus _parseStatus(String value) {
    return SmsIngestionStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => SmsIngestionStatus.pending,
    );
  }
}
