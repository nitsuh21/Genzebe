import 'package:genzeb/features/sms_ingestion/domain/repositories/category_rule_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/transactions/domain/models/money.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:genzeb/features/transactions/domain/repositories/ledger_repository.dart';

class TransactionService {
  TransactionService(this._ledgerRepository, this._categoryRules);

  final LedgerRepository _ledgerRepository;
  final CategoryRuleRepository _categoryRules;

  /// Recategorizes a transaction, optionally flipping its direction (fixes
  /// income parsed as expense and vice versa — the ledger entry is rewritten
  /// so balances stay correct). For SMS transactions the merchant is also
  /// remembered as a rule so every future sync files it correctly. Returns
  /// the merchant a rule was learned for, or null.
  Future<String?> changeCategory({
    required String transactionId,
    required String categoryId,
    bool? makeExpense,
  }) async {
    final existing = await _ledgerRepository.getTransactionById(transactionId);
    if (existing == null) return null;

    final currentlyExpense = existing.type == TransactionType.expense ||
        existing.type == TransactionType.transferOut;
    final wantExpense = makeExpense ?? currentlyExpense;
    final newType = wantExpense
        ? (categoryId == 'transfer_out'
            ? TransactionType.transferOut
            : TransactionType.expense)
        : (categoryId == 'transfer_in'
            ? TransactionType.transferIn
            : TransactionType.income);

    if (existing.categoryId == categoryId && existing.type == newType) {
      return null;
    }

    final updated = existing.copyWith(categoryId: categoryId, type: newType);
    if (newType != existing.type) {
      // The old ledger entry's sign encodes the old direction — rebuild it.
      final hadEntry =
          await _ledgerRepository.hasLedgerEntryForTransaction(existing.id);
      await _ledgerRepository.deleteTransaction(existing.id);
      await _ledgerRepository.saveTransaction(updated);
      if (hadEntry) {
        await _ledgerRepository.appendLedgerEntry(
          LedgerEntry(
            id: 'ledger-${updated.id}',
            transactionId: updated.id,
            accountId: updated.accountId,
            delta: Money(
              minorUnits: wantExpense
                  ? -updated.amount.minorUnits
                  : updated.amount.minorUnits,
              currency: updated.amount.currency,
            ),
            createdAt: DateTime.now(),
            source: updated.source,
          ),
        );
      }
    } else {
      await _ledgerRepository.saveTransaction(updated);
    }

    final snippet = existing.smsSnippet;
    if (existing.source != TransactionSource.sms ||
        snippet == null ||
        snippet.trim().isEmpty) {
      return null;
    }
    final merchant = extractMerchant(snippet, isExpense: wantExpense);
    if (merchant == null) return null;
    await _categoryRules.saveRule(normalizeMerchant(merchant), categoryId);
    return merchant;
  }

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
