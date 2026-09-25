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
import 'package:genzeb/features/alerts/application/auto_sync_controller.dart';
import 'package:genzeb/features/alerts/application/money_alert_service.dart';
import 'package:genzeb/features/alerts/data/money_alert_repositories.dart';
import 'package:genzeb/features/alerts/data/notification_bridge.dart';
import 'package:genzeb/features/alerts/domain/money_alert.dart';
import 'package:genzeb/features/ai/application/ai_assistant_service.dart';
import 'package:genzeb/features/ai/data/gemini_client.dart';
import 'package:genzeb/features/budget/application/budget_service.dart';
import 'package:genzeb/features/budget/data/sqflite_budget_repository.dart';
import 'package:genzeb/features/budget/domain/models/budget.dart';
import 'package:genzeb/features/budget/domain/repositories/budget_repository.dart';
import 'package:genzeb/features/reports/application/report_service.dart';
import 'package:genzeb/features/sms_ingestion/application/account_resolver.dart';
import 'package:genzeb/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzeb/features/sms_ingestion/data/android_device_sms_source.dart';
import 'package:genzeb/features/sms_ingestion/data/sqflite_category_rule_repository.dart';
import 'package:genzeb/features/sms_ingestion/data/sqflite_sms_message_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/category_rule_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/device_sms_source.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/sms_message_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart';
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

/// A persisted one-time flag (null while loading from disk).
class OnboardingFlagController extends StateNotifier<bool?> {
  OnboardingFlagController(this._prefKey) : super(null) {
    _load();
  }

  final String _prefKey;

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

/// The intro slides have been seen (first launch only).
final introSeenProvider =
    StateNotifierProvider<OnboardingFlagController, bool?>((ref) {
  return OnboardingFlagController('intro_seen');
});

/// The one-time SMS setup step has been completed.
final smsSetupDoneProvider =
    StateNotifierProvider<OnboardingFlagController, bool?>((ref) {
  return OnboardingFlagController('sms_setup_done');
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

/// The AI assistant is a Genzeb Plus perk: free users never reach Gemini,
/// whatever keys the build carries.
final aiEntitledProvider = Provider<bool>((ref) {
  final account = ref.watch(accountControllerProvider);
  return account.status == AuthStatus.signedIn && account.plan.includesAi;
});

final aiAvailableProvider = FutureProvider<bool>((ref) async {
  ref.watch(dataVersionProvider);
  if (!ref.watch(aiEntitledProvider)) return false;
  return ref.watch(aiAssistantServiceProvider).isAvailable();
});

final budgetOverviewProvider = FutureProvider<BudgetOverview>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(budgetServiceProvider).buildOverview();
});

final smsMessageRepositoryProvider = Provider<SmsMessageRepository>((ref) {
  return SqfliteSmsMessageRepository(ref.watch(appDatabaseProvider));
});

final categoryRuleRepositoryProvider = Provider<CategoryRuleRepository>((ref) {
  return SqfliteCategoryRuleRepository(ref.watch(appDatabaseProvider));
});

final deviceSmsSourceProvider = Provider<DeviceSmsSource>((ref) {
  return AndroidDeviceSmsSource();
});

final accountResolverProvider = Provider<AccountResolver>((ref) {
  return AccountResolver(ref.watch(ledgerRepositoryProvider));
});

final smsParserEngineProvider = Provider<SmsParserEngine>((ref) {
  return buildDefaultSmsParserEngine();
});

final smsIngestionServiceProvider = Provider<SmsIngestionService>((ref) {
  return SmsIngestionService(
    parser: ref.watch(smsParserEngineProvider),
    ledgerRepository: ref.watch(ledgerRepositoryProvider),
    smsMessageRepository: ref.watch(smsMessageRepositoryProvider),
    accountResolver: ref.watch(accountResolverProvider),
    categoryRuleRepository: ref.watch(categoryRuleRepositoryProvider),
  );
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    smsMessageRepository: ref.watch(smsMessageRepositoryProvider),
    smsIngestionService: ref.watch(smsIngestionServiceProvider),
    deviceSmsSource: ref.watch(deviceSmsSourceProvider),
    ledgerRepository: ref.watch(ledgerRepositoryProvider),
  );
});

final moneyAlertRepositoryProvider = Provider<MoneyAlertRepository>((ref) {
  return SqfliteMoneyAlertRepository(ref.watch(appDatabaseProvider));
});

final moneyAlertServiceProvider = Provider<MoneyAlertService>((ref) {
  return MoneyAlertService(ref.watch(moneyAlertRepositoryProvider));
});

/// App-lifetime auto-sync (launch, resume, incoming bank SMS).
final autoSyncControllerProvider = Provider<AutoSyncController>((ref) {
  final controller = AutoSyncController(
    syncService: ref.watch(syncServiceProvider),
    alertService: ref.watch(moneyAlertServiceProvider),
    deviceSmsSource: ref.watch(deviceSmsSourceProvider),
    onDataChanged: () => ref.read(dataVersionProvider.notifier).state++,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final autoSyncStatusProvider = StreamProvider<AutoSyncStatus>((ref) async* {
  final controller = ref.watch(autoSyncControllerProvider);
  yield controller.status;
  yield* controller.statusChanges;
});

/// Every bank/wallet seen in the inbox — including ones that have only sent
/// promotions so far — so the user can see the app found them.
final institutionsSeenProvider =
    FutureProvider<List<InstitutionSighting>>((ref) async {
  final stored = await ref.watch(storedSmsProvider.future);
  final accounts = await ref.watch(accountsProvider.future);
  final withTransactions = {
    for (final account in accounts)
      institutionInfoForCode(account.institutionCode).id,
  };
  final seen = <EthiopianInstitution>{
    for (final message in stored) institutionForSender(message.sms.sender),
    ...withTransactions,
  }..remove(EthiopianInstitution.unknown);
  final sightings = [
    for (final id in seen)
      InstitutionSighting(
        info: institutionInfo(id),
        hasTransactions: withTransactions.contains(id),
      ),
  ]..sort((a, b) {
      if (a.hasTransactions != b.hasTransactions) {
        return a.hasTransactions ? -1 : 1;
      }
      return a.info.name.compareTo(b.info.name);
    });
  return sightings;
});

class InstitutionSighting {
  const InstitutionSighting(
      {required this.info, required this.hasTransactions});

  final InstitutionInfo info;
  final bool hasTransactions;
}

final notificationBridgeProvider = Provider<NotificationBridge>((ref) {
  return NotificationBridge();
});

final moneyAlertsProvider = FutureProvider<List<MoneyAlert>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(moneyAlertServiceProvider).getAll();
});

final unreadAlertCountProvider = Provider<int>((ref) {
  final alerts = ref.watch(moneyAlertsProvider).valueOrNull ?? const [];
  return alerts.where((alert) => !alert.isRead).length;
});

final demoDataServiceProvider = Provider<DemoDataService>((ref) {
  return DemoDataService(
    ledgerRepository: ref.watch(ledgerRepositoryProvider),
    budgetRepository: ref.watch(budgetRepositoryProvider),
    smsIngestionService: ref.watch(smsIngestionServiceProvider),
  );
});

final transactionServiceProvider = Provider<TransactionService>((ref) {
  return TransactionService(
    ref.watch(ledgerRepositoryProvider),
    ref.watch(categoryRuleRepositoryProvider),
  );
});

final reportServiceProvider = Provider<ReportService>((ref) {
  return ReportService(
    ref.watch(ledgerRepositoryProvider),
    ref.watch(smsIngestionServiceProvider),
  );
});

/// Theme choice, persisted so it survives app restarts. Light by default;
/// dark (or following the system) is an explicit choice in Profile.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.light) {
    _load();
  }

  // v2: the old key mostly held "system" from the Home toggle; everyone
  // starts on the new light default once.
  static const _prefKey = 'theme_mode_v2';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    if (stored == null) return;
    state = ThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => ThemeMode.light,
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

/// Which bottom tab HomeShell shows. Exposed so screens can deep-link
/// ("See all" on Home jumps to the Ledger).
final homeTabProvider = StateProvider<int>((ref) => 0);

/// One app-wide "hide amounts" switch, persisted so it survives restarts.
/// Every screen that shows money reads this — a privacy toggle that only
/// applied to one tab was worse than none.
class AmountsHiddenController extends StateNotifier<bool> {
  AmountsHiddenController() : super(true) {
    _load();
  }

  static const _prefKey = 'amounts_hidden';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_prefKey) ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, state);
  }
}

final amountsHiddenProvider =
    StateNotifierProvider<AmountsHiddenController, bool>((ref) {
  return AmountsHiddenController();
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
        label: institutionInfoForCode(code).shortName,
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
