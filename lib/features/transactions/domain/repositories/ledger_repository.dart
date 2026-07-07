import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';

abstract class LedgerRepository {
  Future<void> upsertAccount(Account account);
  Future<void> saveTransaction(TransactionRecord transaction);
  Future<void> appendLedgerEntry(LedgerEntry ledgerEntry);

  /// Removes the transaction and any ledger entries derived from it.
  Future<void> deleteTransaction(String transactionId);
  Future<TransactionRecord?> getTransactionById(String transactionId);
  Future<bool> hasLedgerEntryForTransaction(String transactionId);
  Future<List<Account>> getAccounts();
  Future<List<TransactionRecord>> getTransactions();
  Future<List<LedgerEntry>> getLedgerEntries();
}
