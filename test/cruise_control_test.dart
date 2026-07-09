import 'package:flutter_test/flutter_test.dart';
import 'package:genzeb/core/config/app_config.dart';
import 'package:genzeb/features/ai/application/ai_assistant_service.dart';
import 'package:genzeb/features/ai/application/ai_categorization_service.dart';
import 'package:genzeb/features/ai/application/cruise_control_service.dart';
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

/// Gemini stub: returns a canned JSON payload instead of calling the API.
class _FakeGemini extends GeminiClient {
  _FakeGemini(this.response);

  final String response;

  @override
  Future<String> generate({
    required String apiKey,
    required String systemInstruction,
    required List<GeminiChatTurn> history,
  }) async {
    return response;
  }
}

CruiseControlService _cruiseControl(
  InMemoryLedgerRepository ledger,
  InMemoryCategoryRuleRepository rules,
  String cannedResponse,
) {
  final gemini = _FakeGemini(cannedResponse);
  final ingestion = SmsIngestionService(
    parser: SmsParserEngine(const [GenericAmountParserTemplate()]),
    ledgerRepository: ledger,
    smsMessageRepository: InMemorySmsMessageRepository(),
    accountMappingService: AccountMappingService(ledger),
    categoryRuleRepository: rules,
  );
  return CruiseControlService(
    categorization: AiCategorizationService(
      geminiClient: gemini,
      categoryRuleRepository: rules,
      ledgerRepository: ledger,
      assistantService: AiAssistantService(
        geminiClient: gemini,
        reportService: ReportService(ledger, ingestion),
        budgetService: BudgetService(
          budgetRepository: InMemoryBudgetRepository(),
          ledgerRepository: ledger,
        ),
        ledgerRepository: ledger,
      ),
    ),
  );
}

Future<void> _seedTx(
  InMemoryLedgerRepository ledger, {
  required String id,
  required String accountId,
  required TransactionType type,
  required String categoryId,
  required String snippet,
}) async {
  await ledger.saveTransaction(TransactionRecord(
    id: id,
    accountId: accountId,
    type: type,
    amount: const Money(minorUnits: 100000),
    occurredAt: DateTime(2026, 7, 9),
    categoryId: categoryId,
    source: TransactionSource.sms,
    smsSender: 'somebank',
    smsSnippet: snippet,
  ));
  await ledger.appendLedgerEntry(LedgerEntry(
    id: 'ledger-$id',
    transactionId: id,
    accountId: accountId,
    delta: Money(
      minorUnits: type == TransactionType.income ? 100000 : -100000,
    ),
    createdAt: DateTime(2026, 7, 9),
    source: TransactionSource.sms,
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // AI is app-provided only; simulate a configured build.
  AppConfig.overrideForTesting(geminiApiKey: 'test-key');

  test('steer applies category, direction, and account fixes safely',
      () async {
    final ledger = InMemoryLedgerRepository();
    final rules = InMemoryCategoryRuleRepository();
    await _seedTx(
      ledger,
      id: 'sms-a',
      accountId: 'main-wallet',
      type: TransactionType.expense,
      categoryId: 'expense',
      snippet: 'Salary payment credited 1000.00 birr by employer',
    );

    final service = _cruiseControl(
      ledger,
      rules,
      '[{"id": "sms-a", "category": "salary", "direction": "in", '
      '"institution": "cbe", "reason": "salary credit"}]',
    );
    final report = await service.steer(transactionIds: {'sms-a'});

    expect(report.aiUsed, isTrue);
    expect(report.corrected, 1);
    final tx = await ledger.getTransactionById('sms-a');
    expect(tx!.categoryId, 'salary');
    expect(tx.type, TransactionType.income);
    expect(tx.accountId, 'cbe-main');
    // Amount untouched; ledger entry re-signed and re-homed.
    expect(tx.amount.minorUnits, 100000);
    final entry = (await ledger.getLedgerEntries()).single;
    expect(entry.delta.minorUnits, 100000);
    expect(entry.accountId, 'cbe-main');
  });

  test('user-taught rules are never overridden by the AI', () async {
    final ledger = InMemoryLedgerRepository();
    final rules = InMemoryCategoryRuleRepository();
    // The user already decided: Soreti Hotel is rent.
    await rules.saveRule(normalizeMerchant('Soreti Hotel'), 'rent');
    await _seedTx(
      ledger,
      id: 'sms-b',
      accountId: 'telebirr-main',
      type: TransactionType.expense,
      categoryId: 'rent',
      snippet: 'You have paid ETB 1,000.00 to Soreti Hotel via telebirr',
    );

    final service = _cruiseControl(
      ledger,
      rules,
      // Malicious/wrong AI answer trying to move it to food.
      '[{"id": "sms-b", "category": "food", "direction": "out", '
      '"reason": "hotel is food"}]',
    );
    final report = await service.steer(transactionIds: {'sms-b'});

    expect(report.aiUsed, isTrue);
    expect(report.corrected, 0);
    expect((await ledger.getTransactionById('sms-b'))!.categoryId, 'rent');
  });

  test('garbage AI output degrades to no-op, never throws', () async {
    final ledger = InMemoryLedgerRepository();
    final rules = InMemoryCategoryRuleRepository();
    await _seedTx(
      ledger,
      id: 'sms-c',
      accountId: 'main-wallet',
      type: TransactionType.expense,
      categoryId: 'expense',
      snippet: 'You paid 99.00 birr somewhere',
    );

    final service = _cruiseControl(
      ledger,
      rules,
      'sorry, as an AI model I cannot ' // not JSON
      '[{"id": "sms-c", "category": "not_a_category", "direction": "maybe"}]',
    );
    final report = await service.steer(transactionIds: {'sms-c'});

    expect(report.corrected, 0);
    expect((await ledger.getTransactionById('sms-c'))!.categoryId, 'expense');
  });
}
