import 'package:genzebet/features/transactions/domain/models/transaction_models.dart';

class SyncConflictResolver {
  const SyncConflictResolver();

  TransactionRecord resolveTransaction(
    TransactionRecord local,
    TransactionRecord remote,
  ) {
    // Mutable display fields use last-write-wins using occurredAt as baseline.
    return local.occurredAt.isAfter(remote.occurredAt) ? local : remote;
  }

  LedgerEntry resolveLedgerEntry(
    LedgerEntry local,
    LedgerEntry remote,
  ) {
    // Ledger entries are immutable financial events. Keep both by default.
    return local.createdAt.isAfter(remote.createdAt) ? local : remote;
  }
}
