import 'package:genzebet/features/transactions/domain/models/money.dart';
import 'package:genzebet/features/transactions/domain/models/transaction_models.dart';
import 'package:genzebet/features/transactions/domain/repositories/ledger_repository.dart';

class TransactionService {
  TransactionService(this._ledgerRepository);

  final LedgerRepository _ledgerRepository;

  Future<void> addManualTransaction({
    required String transactionId,
    required String accountId,
    required TransactionType type,
    required int amountMinor,
    required String categoryId,
    String? accountName,
    String? note,
    DateTime? occurredAt,
  }) async {
    // Make sure the account exists so it appears in carousels/reports.
    final accounts = await _ledgerRepository.getAccounts();
    if (!accounts.any((a) => a.id == accountId)) {
      await _ledgerRepository.upsertAccount(
        Account(
          id: accountId,
          name: accountName ?? 'Primary Wallet',
          kind: 'wallet',
          createdAt: DateTime.now(),
        ),
      );
    }

    final transaction = TransactionRecord(
      id: transactionId,
      accountId: accountId,
      type: type,
      amount: Money(minorUnits: amountMinor.abs()),
      occurredAt: occurredAt ?? DateTime.now(),
      categoryId: categoryId,
      source: TransactionSource.manual,
      note: note,
    );

    await _ledgerRepository.saveTransaction(transaction);
    await _ledgerRepository.appendLedgerEntry(
      LedgerEntry(
        id: 'ledger-$transactionId',
        transactionId: transaction.id,
        accountId: accountId,
        delta: Money(
          minorUnits: type == TransactionType.expense
              ? -amountMinor.abs()
              : amountMinor.abs(),
        ),
        createdAt: DateTime.now(),
        source: TransactionSource.manual,
      ),
    );
  }
}
