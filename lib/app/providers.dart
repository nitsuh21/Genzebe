import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui' as ui;

import 'package:genzeb/core/config/app_config.dart';
import 'package:genzeb/core/db/app_database.dart';
import 'package:genzeb/core/demo/demo_data_service.dart';
import 'package:genzeb/core/l10n/app_strings.dart';
import 'package:genzeb/features/account/application/account_controller.dart';
import 'package:genzeb/features/account/data/supabase_account_repository.dart';
import 'package:genzeb/features/account/domain/models/account_models.dart';
import 'package:genzeb/features/account/domain/repositories/account_repository.dart';
import 'package:genzeb/features/ai/ai_config.dart';
import 'package:genzeb/features/ai/application/ai_assistant_service.dart';
import 'package:genzeb/features/ai/application/ai_categorization_service.dart';
import 'package:genzeb/features/ai/data/gemini_client.dart';
import 'package:genzeb/features/budget/application/budget_service.dart';
import 'package:genzeb/features/budget/data/sqflite_budget_repository.dart';
import 'package:genzeb/features/budget/domain/models/budget.dart';
import 'package:genzeb/features/budget/domain/repositories/budget_repository.dart';
import 'package:genzeb/features/reports/application/report_service.dart';
import 'package:genzeb/features/sms_ingestion/application/account_mapping_service.dart';
import 'package:genzeb/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzeb/features/sms_ingestion/data/android_device_sms_source.dart';
import 'package:genzeb/features/sms_ingestion/data/sqflite_sms_message_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/device_sms_source.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/sms_message_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/sync/application/sync_service.dart';
import 'package:genzeb/features/transactions/application/transaction_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:genzeb/features/transactions/data/sqflite_ledger_repository.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:genzeb/features/transactions/domain/repositories/ledger_repository.dart';

class InstitutionFilterOption {
  const InstitutionFilterOption({
    required this.code,
    required this.label,
  });

  final String code;
  final String label;
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase.instance;
});

final accountRepositoryProvider = Provider<AccountRepository?>((ref) {
  if (!AppConfig.isBackendConfigured) return null;
  return SupabaseAccountRepository();
});

final accountControllerProvider =
    StateNotifierProvider<AccountController, AccountState>((ref) {
  return AccountController(repository: ref.watch(accountRepositoryProvider));
});

/// Whether the one-time SMS setup step of onboarding has been completed
/// (null while loading from disk).
class OnboardingFlagController extends StateNotifier<bool?> {
  OnboardingFlagController() : super(null) {
    _load();
  }

  static const _prefKey = 'sms_setup_done';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_prefKey) ?? false;
  }

  Future<void> markDone() async {
    state = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }
}

final smsSetupDoneProvider =
    StateNotifierProvider<OnboardingFlagController, bool?>((ref) {
  return OnboardingFlagController();
});

final ledgerRepositoryProvider = Provider<LedgerRepository>((ref) {
  return SqfliteLedgerRepository(ref.watch(appDatabaseProvider));
});

final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  return SqfliteBudgetRepository(ref.watch(appDatabaseProvider));
});

final budgetServiceProvider = Provider<BudgetService>((ref) {
  return BudgetService(
    budgetRepository: ref.watch(budgetRepositoryProvider),
    ledgerRepository: ref.watch(ledgerRepositoryProvider),
  );
});

final geminiClientProvider = Provider<GeminiClient>((ref) {
  return GeminiClient(model: AiConfig.geminiModel);
});

final aiAssistantServiceProvider = Provider<AiAssistantService>((ref) {
  return AiAssistantService(
    geminiClient: ref.watch(geminiClientProvider),
    reportService: ref.watch(reportServiceProvider),
    budgetService: ref.watch(budgetServiceProvider),
    ledgerRepository: ref.watch(ledgerRepositoryProvider),
  );
});

final aiCategorizationServiceProvider =
    Provider<AiCategorizationService>((ref) {
  return AiCategorizationService(
    geminiClient: ref.watch(geminiClientProvider),
    assistantService: ref.watch(aiAssistantServiceProvider),
    ledgerRepository: ref.watch(ledgerRepositoryProvider),
  );
});

final aiAvailableProvider = FutureProvider<bool>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(aiAssistantServiceProvider).isAvailable();
});

final budgetOverviewProvider = FutureProvider<BudgetOverview>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(budgetServiceProvider).buildOverview();
});

final smsMessageRepositoryProvider = Provider<SmsMessageRepository>((ref) {
  return SqfliteSmsMessageRepository(ref.watch(appDatabaseProvider));
});

final deviceSmsSourceProvider = Provider<DeviceSmsSource>((ref) {
  return AndroidDeviceSmsSource();
});

final accountMappingServiceProvider = Provider<AccountMappingService>((ref) {
  return AccountMappingService(ref.watch(ledgerRepositoryProvider));
});

final smsParserEngineProvider = Provider<SmsParserEngine>((ref) {
  return SmsParserEngine(
    const [
      CbeSmsParserTemplate(),
      AwashSmsParserTemplate(),
      TelebirrSmsParserTemplate(),
      BoaSmsParserTemplate(),
      HibretSmsParserTemplate(),
      DashenSmsParserTemplate(),
      GenericAmountParserTemplate(),
    ],
  );
});

final smsIngestionServiceProvider = Provider<SmsIngestionService>((ref) {
  return SmsIngestionService(
    parser: ref.watch(smsParserEngineProvider),
    ledgerRepository: ref.watch(ledgerRepositoryProvider),
    smsMessageRepository: ref.watch(smsMessageRepositoryProvider),
    accountMappingService: ref.watch(accountMappingServiceProvider),
  );
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    smsMessageRepository: ref.watch(smsMessageRepositoryProvider),
    smsIngestionService: ref.watch(smsIngestionServiceProvider),
    deviceSmsSource: ref.watch(deviceSmsSourceProvider),
    accountMappingService: ref.watch(accountMappingServiceProvider),
  );
});

final demoDataServiceProvider = Provider<DemoDataService>((ref) {
  return DemoDataService(
    ledgerRepository: ref.watch(ledgerRepositoryProvider),
    budgetRepository: ref.watch(budgetRepositoryProvider),
    smsIngestionService: ref.watch(smsIngestionServiceProvider),
  );
});

final transactionServiceProvider = Provider<TransactionService>((ref) {
  return TransactionService(ref.watch(ledgerRepositoryProvider));
});

final reportServiceProvider = Provider<ReportService>((ref) {
  return ReportService(
    ref.watch(ledgerRepositoryProvider),
    ref.watch(smsIngestionServiceProvider),
  );
});

/// Theme choice, persisted so it survives app restarts.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.system) {
    _load();
  }

  static const _prefKey = 'theme_mode';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    if (stored == null) return;
    state = ThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, mode.name);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController();
});

/// App language: 'system' follows the device locale; 'en'/'am' force one.
class AppLanguageController extends StateNotifier<String> {
  AppLanguageController() : super('system') {
    _load();
  }

  static const _prefKey = 'app_language';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    if (stored == 'en' || stored == 'am' || stored == 'system') {
      state = stored!;
    }
  }

  Future<void> setLanguage(String value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, value);
  }
}

final appLanguageProvider =
    StateNotifierProvider<AppLanguageController, String>((ref) {
  return AppLanguageController();
});

final stringsProvider = Provider<AppStrings>((ref) {
  final language = ref.watch(appLanguageProvider);
  final resolved = language == 'system'
      ? ui.PlatformDispatcher.instance.locale.languageCode
      : language;
  return resolved == 'am' ? amStrings : enStrings;
});

/// Bumping this version invalidates all derived data providers so the UI
/// refreshes after a mutation (manual add, SMS ingest, force sync, etc.).
final dataVersionProvider = StateProvider<int>((ref) => 0);

void refreshAppData(WidgetRef ref) {
  ref.read(dataVersionProvider.notifier).state++;
}

final selectedInstitutionCodesProvider = StateProvider<Set<String>>((ref) {
  return <String>{};
});

void toggleInstitutionFilter(WidgetRef ref, String code) {
  final current = ref.read(selectedInstitutionCodesProvider);
  final updated = {...current};
  if (updated.contains(code)) {
    updated.remove(code);
  } else {
    updated.add(code);
  }
  ref.read(selectedInstitutionCodesProvider.notifier).state = updated;
}

void clearInstitutionFilters(WidgetRef ref) {
  ref.read(selectedInstitutionCodesProvider.notifier).state = <String>{};
}

final institutionFilterOptionsProvider =
    FutureProvider<List<InstitutionFilterOption>>((ref) async {
  ref.watch(dataVersionProvider);
  final accounts = await ref.watch(ledgerRepositoryProvider).getAccounts();
  final seen = <String>{};
  final options = <InstitutionFilterOption>[];
  for (final account in accounts) {
    final code = account.institutionCode?.trim().toLowerCase();
    if (code == null || code.isEmpty) continue;
    if (!seen.add(code)) continue;
    options.add(
      InstitutionFilterOption(
        code: code,
        label: _institutionLabelFromCode(code),
      ),
    );
  }
  options.sort((a, b) => a.label.compareTo(b.label));
  return options;
});

final ledgerTransactionsProvider =
    FutureProvider<List<TransactionRecord>>((ref) async {
  ref.watch(dataVersionProvider);
  final selectedCodes = ref.watch(selectedInstitutionCodesProvider);
  final repo = ref.watch(ledgerRepositoryProvider);
  final transactions = await repo.getTransactions();
  if (selectedCodes.isEmpty) return transactions;
  final accounts = await repo.getAccounts();
  final allowedAccountIds = accounts
      .where((account) {
        final code = account.institutionCode?.trim().toLowerCase();
        return code != null && selectedCodes.contains(code);
      })
      .map((account) => account.id)
      .toSet();
  return transactions
      .where((tx) => allowedAccountIds.contains(tx.accountId))
      .toList(growable: false);
});

final allTransactionsProvider =
    FutureProvider<List<TransactionRecord>>((ref) async {
  ref.watch(dataVersionProvider);
  final repo = ref.watch(ledgerRepositoryProvider);
  return repo.getTransactions();
});

final accountsProvider = FutureProvider<List<Account>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(ledgerRepositoryProvider).getAccounts();
});

final dashboardInsightsProvider = FutureProvider<DashboardInsights>((ref) {
  ref.watch(dataVersionProvider);
  final selectedCodes = ref.watch(selectedInstitutionCodesProvider);
  return ref.watch(reportServiceProvider).generateDashboardInsights(
        institutionCodes: selectedCodes,
      );
});

final monthlyReportProvider = FutureProvider<MonthlyReport>((ref) {
  ref.watch(dataVersionProvider);
  final selectedCodes = ref.watch(selectedInstitutionCodesProvider);
  return ref.watch(reportServiceProvider).generateCurrentMonthReport(
        institutionCodes: selectedCodes,
      );
});

final monthlySeriesProvider = FutureProvider<List<MonthBucket>>((ref) {
  ref.watch(dataVersionProvider);
  final selectedCodes = ref.watch(selectedInstitutionCodesProvider);
  return ref.watch(reportServiceProvider).monthlySeries(
        institutionCodes: selectedCodes,
      );
});

final reviewQueueProvider = FutureProvider<List<SmsReviewItem>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(smsIngestionServiceProvider).getReviewQueue();
});

final storedSmsProvider = FutureProvider<List<StoredSmsMessage>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(smsMessageRepositoryProvider).getAll();
});

String _institutionLabelFromCode(String code) {
  switch (code) {
    case 'cbe':
      return 'CBE';
    case 'awash':
      return 'Awash';
    case 'telebirr':
      return 'Telebirr';
    case 'boa':
      return 'Abyssinia';
    case 'hibret':
      return 'Hibret';
    case 'dashen':
      return 'Dashen';
    default:
      return code.toUpperCase();
  }
}
