import 'package:genzebet/features/transactions/domain/models/transaction_models.dart';
import 'package:genzebet/features/transactions/domain/repositories/ledger_repository.dart';

class InMemoryLedgerRepository implements LedgerRepository {
  final Map<String, Account> _accounts = {};
  final Map<String, TransactionRecord> _transactions = {};
  final List<LedgerEntry> _ledgerEntries = [];

  @override
  Future<void> appendLedgerEntry(LedgerEntry ledgerEntry) async {
    final exists = _ledgerEntries.any(
      (entry) => entry.transactionId == ledgerEntry.transactionId,
    );
    if (exists) return;
    _ledgerEntries.add(ledgerEntry);
  }

  @override
  Future<TransactionRecord?> getTransactionById(String transactionId) async {
    return _transactions[transactionId];
  }

  @override
  Future<bool> hasLedgerEntryForTransaction(String transactionId) async {
    return _ledgerEntries.any((entry) => entry.transactionId == transactionId);
  }

  @override
  Future<List<Account>> getAccounts() async {
    return _accounts.values.toList(growable: false);
  }

  @override
  Future<List<LedgerEntry>> getLedgerEntries() async {
    return List<LedgerEntry>.unmodifiable(_ledgerEntries);
  }

  @override
  Future<List<TransactionRecord>> getTransactions() async {
    final values = _transactions.values.toList(growable: false);
    values.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return values;
  }

  @override
  Future<void> saveTransaction(TransactionRecord transaction) async {
    _transactions[transaction.id] = transaction;
  }

  @override
  Future<void> upsertAccount(Account account) async {
    _accounts[account.id] = account;
  }
}
