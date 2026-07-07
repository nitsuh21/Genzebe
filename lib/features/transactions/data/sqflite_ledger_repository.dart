import 'package:genzebet/core/db/app_database.dart';
import 'package:genzebet/features/transactions/domain/models/money.dart';
import 'package:genzebet/features/transactions/domain/models/transaction_models.dart';
import 'package:genzebet/features/transactions/domain/repositories/ledger_repository.dart';
import 'package:sqflite/sqflite.dart';

/// Persistent [LedgerRepository] backed by on-device SQLite.
class SqfliteLedgerRepository implements LedgerRepository {
  SqfliteLedgerRepository(this._database);

  final AppDatabase _database;

  Future<Database> get _db => _database.database;

  @override
  Future<void> upsertAccount(Account account) async {
    final db = await _db;
    await db.insert(
      'accounts',
      {
        'id': account.id,
        'name': account.name,
        'kind': account.kind,
        'createdAt': account.createdAt.toIso8601String(),
        'institutionCode': account.institutionCode,
        'maskedAccount': account.maskedAccount,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> saveTransaction(TransactionRecord transaction) async {
    final db = await _db;
    await db.insert(
      'transactions',
      {
        'id': transaction.id,
        'accountId': transaction.accountId,
        'type': transaction.type.name,
        'amountMinor': transaction.amount.minorUnits,
        'occurredAt': transaction.occurredAt.toIso8601String(),
        'categoryId': transaction.categoryId,
        'source': transaction.source.name,
        'smsSender': transaction.smsSender,
        'smsSnippet': transaction.smsSnippet,
        'note': transaction.note,
        'parserConfidence': transaction.parserConfidence,
        'reviewStatus': transaction.reviewStatus.name,
        'statementBalanceMinor': transaction.statementBalanceMinor,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> appendLedgerEntry(LedgerEntry ledgerEntry) async {
    final db = await _db;
    final existing = await db.query(
      'ledger_entries',
      where: 'transactionId = ?',
      whereArgs: [ledgerEntry.transactionId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await db.insert(
      'ledger_entries',
      {
        'id': ledgerEntry.id,
        'transactionId': ledgerEntry.transactionId,
        'accountId': ledgerEntry.accountId,
        'deltaMinor': ledgerEntry.delta.minorUnits,
        'createdAt': ledgerEntry.createdAt.toIso8601String(),
        'source': ledgerEntry.source.name,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<TransactionRecord?> getTransactionById(String transactionId) async {
    final db = await _db;
    final rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapTransaction(rows.first);
  }

  @override
  Future<bool> hasLedgerEntryForTransaction(String transactionId) async {
    final db = await _db;
    final rows = await db.query(
      'ledger_entries',
      where: 'transactionId = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<List<Account>> getAccounts() async {
    final db = await _db;
    final rows = await db.query('accounts');
    return rows.map(_mapAccount).toList(growable: false);
  }

  @override
  Future<List<TransactionRecord>> getTransactions() async {
    final db = await _db;
    final rows = await db.query('transactions', orderBy: 'occurredAt DESC');
    return rows.map(_mapTransaction).toList(growable: false);
  }

  @override
  Future<List<LedgerEntry>> getLedgerEntries() async {
    final db = await _db;
    final rows = await db.query('ledger_entries');
    return rows.map(_mapLedgerEntry).toList(growable: false);
  }

  Account _mapAccount(Map<String, Object?> row) {
    return Account(
      id: row['id'] as String,
      name: row['name'] as String,
      kind: row['kind'] as String,
      createdAt: DateTime.parse(row['createdAt'] as String),
      institutionCode: row['institutionCode'] as String?,
      maskedAccount: row['maskedAccount'] as String?,
    );
  }

  TransactionRecord _mapTransaction(Map<String, Object?> row) {
    return TransactionRecord(
      id: row['id'] as String,
      accountId: row['accountId'] as String,
      type: _parseTransactionType(row['type'] as String),
      amount: Money(minorUnits: row['amountMinor'] as int),
      occurredAt: DateTime.parse(row['occurredAt'] as String),
      categoryId: row['categoryId'] as String,
      source: _parseSource(row['source'] as String),
      smsSender: row['smsSender'] as String?,
      smsSnippet: row['smsSnippet'] as String?,
      note: row['note'] as String?,
      parserConfidence: (row['parserConfidence'] as num?)?.toDouble(),
      reviewStatus: _parseReviewStatus(row['reviewStatus'] as String),
      statementBalanceMinor: row['statementBalanceMinor'] as int?,
    );
  }

  LedgerEntry _mapLedgerEntry(Map<String, Object?> row) {
    return LedgerEntry(
      id: row['id'] as String,
      transactionId: row['transactionId'] as String,
      accountId: row['accountId'] as String,
      delta: Money(minorUnits: row['deltaMinor'] as int),
      createdAt: DateTime.parse(row['createdAt'] as String),
      source: _parseSource(row['source'] as String),
    );
  }

  TransactionType _parseTransactionType(String value) {
    return TransactionType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => TransactionType.expense,
    );
  }

  TransactionSource _parseSource(String value) {
    return TransactionSource.values.firstWhere(
      (source) => source.name == value,
      orElse: () => TransactionSource.manual,
    );
  }

  TransactionReviewStatus _parseReviewStatus(String value) {
    return TransactionReviewStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => TransactionReviewStatus.autoAccepted,
    );
  }
}
