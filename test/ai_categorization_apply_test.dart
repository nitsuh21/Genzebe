import 'package:flutter_test/flutter_test.dart';
import 'package:genzeb/features/ai/application/ai_assistant_service.dart';
import 'package:genzeb/features/ai/application/ai_categorization_service.dart';
import 'package:genzeb/features/ai/data/gemini_client.dart';
import 'package:genzeb/features/budget/application/budget_service.dart';
import 'package:genzeb/features/budget/data/in_memory_budget_repository.dart';
import 'package:genzeb/features/reports/application/report_service.dart';
import 'package:genzeb/features/sms_ingestion/application/account_mapping_service.dart';
import 'package:genzeb/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzeb/features/sms_ingestion/data/in_memory_category_rule_repository.dart';
import 'package:genzeb/features/sms_ingestion/data/in_memory_sms_message_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/transactions/data/in_memory_ledger_repository.dart';
import 'package:genzeb/features/transactions/domain/models/money.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('applying a direction fix rewrites the transaction and ledger entry',
      () async {
    final ledger = InMemoryLedgerRepository();
    final gemini = GeminiClient();
    final ingestion = SmsIngestionService(
      parser: SmsParserEngine(const [GenericAmountParserTemplate()]),
      ledgerRepository: ledger,
      smsMessageRepository: InMemorySmsMessageRepository(),
      accountMappingService: AccountMappingService(ledger),
      categoryRuleRepository: InMemoryCategoryRuleRepository(),
    );
    final service = AiCategorizationService(
      geminiClient: gemini,
      categoryRuleRepository: InMemoryCategoryRuleRepository(),
      assistantService: AiAssistantService(
        geminiClient: gemini,
        reportService: ReportService(ledger, ingestion),
        budgetService: BudgetService(
          budgetRepository: InMemoryBudgetRepository(),
          ledgerRepository: ledger,
        ),
        ledgerRepository: ledger,
      ),
      ledgerRepository: ledger,
    );

    // A salary SMS the regex parser misread as an expense.
    const txId = 'sms-mis-1';
    await ledger.saveTransaction(
      TransactionRecord(
        id: txId,
        accountId: 'cbe-main',
        type: TransactionType.expense,
        amount: const Money(minorUnits: 500000),
        occurredAt: DateTime(2026, 6, 5),
        categoryId: 'expense',
        source: TransactionSource.sms,
        smsSender: 'CBE',
        smsSnippet: 'Salary payment processed ETB 5000.00',
      ),
    );
    await ledger.appendLedgerEntry(
      LedgerEntry(
        id: 'ledger-$txId',
        transactionId: txId,
        accountId: 'cbe-main',
        delta: const Money(minorUnits: -500000),
        createdAt: DateTime(2026, 6, 5),
        source: TransactionSource.sms,
      ),
    );

    final applied = await service.applySuggestions([
      AiCategorySuggestion(
        transactionId: txId,
        smsSnippet: 'Salary payment processed ETB 5000.00',
        amountMinor: 500000,
        currentCategoryId: 'expense',
        suggestedCategoryId: 'salary',
        currentType: TransactionType.expense,
        suggestedType: TransactionType.income,
        reason: 'salary is income',
      ),
    ]);

    expect(applied, 1);
    final updated = await ledger.getTransactionById(txId);
    expect(updated!.type, TransactionType.income);
    expect(updated.categoryId, 'salary');
    // Amount is untouched — AI must never modify it.
    expect(updated.amount.minorUnits, 500000);
    final entries = await ledger.getLedgerEntries();
    expect(entries, hasLength(1));
    expect(entries.single.delta.minorUnits, 500000);
  });
}
