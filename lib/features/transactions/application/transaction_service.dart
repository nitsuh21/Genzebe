import 'package:genzeb/features/sms_ingestion/domain/repositories/category_rule_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/transactions/domain/models/money.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:genzeb/features/transactions/domain/repositories/ledger_repository.dart';

class TransactionService {
  TransactionService(this._ledgerRepository, this._categoryRules);

  final LedgerRepository _ledgerRepository;
  final CategoryRuleRepository _categoryRules;

  /// Recategorizes a transaction. For SMS transactions the merchant is also
  /// remembered as a rule so every future sync files it correctly. Returns
  /// the merchant a rule was learned for, or null.
  Future<String?> changeCategory({
    required String transactionId,
    required String categoryId,
  }) async {
    final existing =
        await _ledgerRepository.getTransactionById(transactionId);
    if (existing == null || existing.categoryId == categoryId) return null;

    await _ledgerRepository
        .saveTransaction(existing.copyWith(categoryId: categoryId));

    final snippet = existing.smsSnippet;
    if (existing.source != TransactionSource.sms ||
        snippet == null ||
        snippet.trim().isEmpty) {
      return null;
    }
    final isExpense = existing.type == TransactionType.expense ||
        existing.type == TransactionType.transferOut;
    final merchant = extractMerchant(snippet, isExpense: isExpense);
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
