import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens (and migrates) the on-device SQLite database that persists the
/// ledger, accounts, ledger entries, and budgets across app restarts.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _databaseName = 'genzebet.db';
  static const _databaseVersion = 5;

  Database? _db;
  Future<Database>? _opening;

  Future<Database> get database {
    final existing = _db;
    if (existing != null) return Future.value(existing);
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, _databaseName);
    final db = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    _db = db;
    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        institutionCode TEXT,
        maskedAccount TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        accountId TEXT NOT NULL,
        type TEXT NOT NULL,
        amountMinor INTEGER NOT NULL,
        occurredAt TEXT NOT NULL,
        categoryId TEXT NOT NULL,
        source TEXT NOT NULL,
        smsSender TEXT,
        smsSnippet TEXT,
        note TEXT,
        parserConfidence REAL,
        reviewStatus TEXT NOT NULL,
        statementBalanceMinor INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE ledger_entries (
        id TEXT PRIMARY KEY,
        transactionId TEXT NOT NULL,
        accountId TEXT NOT NULL,
        deltaMinor INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        source TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE budgets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        categoryIds TEXT,
        institutionCodes TEXT,
        excludedTransactionIds TEXT,
        categoryId TEXT,
        limitMinor INTEGER NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    await _createSmsMessagesTable(db);
  }

  Future<void> _createSmsMessagesTable(Database db) async {
    await db.execute('''
      CREATE TABLE sms_messages (
        id TEXT PRIMARY KEY,
        sender TEXT NOT NULL,
        body TEXT NOT NULL,
        receivedAt TEXT NOT NULL,
        messageHash TEXT NOT NULL,
        status TEXT NOT NULL,
        parsedTransactionId TEXT,
        failureReason TEXT,
        ingestedAt TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_sms_messages_hash ON sms_messages(messageHash)',
    );
    await db.execute(
      'CREATE INDEX idx_sms_messages_status ON sms_messages(status)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE budgets ADD COLUMN name TEXT NOT NULL DEFAULT 'General budget'",
      );
      await db.execute("ALTER TABLE budgets ADD COLUMN categoryIds TEXT");
      await db.execute(
        "UPDATE budgets SET categoryIds = json_array(categoryId) WHERE categoryId IS NOT NULL AND TRIM(categoryId) != ''",
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE budgets ADD COLUMN excludedTransactionIds TEXT",
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        "ALTER TABLE budgets ADD COLUMN institutionCodes TEXT",
      );
    }
    if (oldVersion < 5) {
      await _createSmsMessagesTable(db);
    }
  }
}
