import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzebet/core/db/app_database.dart';
import 'package:genzebet/features/ai/ai_config.dart';
import 'package:genzebet/features/ai/application/ai_assistant_service.dart';
import 'package:genzebet/features/ai/application/ai_summary_service.dart';
import 'package:genzebet/features/ai/data/gemini_client.dart';
import 'package:genzebet/features/budget/application/budget_service.dart';
import 'package:genzebet/features/budget/data/sqflite_budget_repository.dart';
import 'package:genzebet/features/budget/domain/models/budget.dart';
import 'package:genzebet/features/budget/domain/repositories/budget_repository.dart';
import 'package:genzebet/features/ai/application/summary_boundary_impl.dart';
import 'package:genzebet/features/ai/domain/boundaries/summary_boundary.dart';
import 'package:genzebet/features/profile/application/admin_audit_service.dart';
import 'package:genzebet/features/profile/application/auth_service.dart';
import 'package:genzebet/features/profile/application/entitlement_service.dart';
import 'package:genzebet/features/profile/application/payment_claim_service.dart';
import 'package:genzebet/features/profile/application/reminder_service.dart';
import 'package:genzebet/features/profile/application/risk_service.dart';
import 'package:genzebet/features/profile/domain/models/auth_models.dart';
import 'package:genzebet/features/profile/data/in_memory_admin_repository.dart';
import 'package:genzebet/features/profile/data/in_memory_subscription_repository.dart';
import 'package:genzebet/features/profile/domain/repositories/admin_repository.dart';
import 'package:genzebet/features/profile/domain/repositories/subscription_repository.dart';
import 'package:genzebet/features/reports/application/report_service.dart';
import 'package:genzebet/features/sms_ingestion/application/account_mapping_service.dart';
import 'package:genzebet/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzebet/features/sms_ingestion/data/android_device_sms_source.dart';
import 'package:genzebet/features/sms_ingestion/data/in_memory_sms_message_repository.dart';
import 'package:genzebet/features/sms_ingestion/domain/repositories/device_sms_source.dart';
import 'package:genzebet/features/sms_ingestion/domain/repositories/sms_message_repository.dart';
import 'package:genzebet/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzebet/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzebet/features/sync/application/sync_service.dart';
import 'package:genzebet/features/sync/data/in_memory_cloud_sync_repository.dart';
import 'package:genzebet/features/sync/domain/repositories/cloud_sync_repository.dart';
import 'package:genzebet/features/transactions/application/transaction_service.dart';
import 'package:genzebet/features/transactions/data/sqflite_ledger_repository.dart';
import 'package:genzebet/features/transactions/domain/models/transaction_models.dart';
import 'package:genzebet/features/transactions/domain/repositories/ledger_repository.dart';

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

final aiAvailableProvider = FutureProvider<bool>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(aiAssistantServiceProvider).isAvailable();
});

final budgetOverviewProvider = FutureProvider<BudgetOverview>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(budgetServiceProvider).buildOverview();
});

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return InMemorySubscriptionRepository();
});

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return InMemoryAdminRepository();
});

final smsMessageRepositoryProvider = Provider<SmsMessageRepository>((ref) {
  return InMemorySmsMessageRepository();
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

final cloudSyncRepositoryProvider = Provider<CloudSyncRepository>((ref) {
  return InMemoryCloudSyncRepository();
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ledgerRepository: ref.watch(ledgerRepositoryProvider),
    cloudSyncRepository: ref.watch(cloudSyncRepositoryProvider),
    smsMessageRepository: ref.watch(smsMessageRepositoryProvider),
    smsIngestionService: ref.watch(smsIngestionServiceProvider),
    deviceSmsSource: ref.watch(deviceSmsSourceProvider),
    accountMappingService: ref.watch(accountMappingServiceProvider),
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

final entitlementServiceProvider = Provider<EntitlementService>((ref) {
  return EntitlementService(ref.watch(subscriptionRepositoryProvider));
});

final paymentClaimServiceProvider = Provider<PaymentClaimService>((ref) {
  return PaymentClaimService(
    repository: ref.watch(subscriptionRepositoryProvider),
    entitlementService: ref.watch(entitlementServiceProvider),
  );
});

final reminderServiceProvider = Provider<ReminderService>((ref) {
  return const ReminderService();
});

final adminAuditServiceProvider = Provider<AdminAuditService>((ref) {
  return AdminAuditService(ref.watch(adminRepositoryProvider));
});

final riskServiceProvider = Provider<RiskService>((ref) {
  return RiskService(
    subscriptionRepository: ref.watch(subscriptionRepositoryProvider),
    adminRepository: ref.watch(adminRepositoryProvider),
  );
});

final aiSummaryServiceProvider = Provider<AiSummaryService>((ref) {
  return AiSummaryService(
    subscriptionRepository: ref.watch(subscriptionRepositoryProvider),
    reportService: ref.watch(reportServiceProvider),
  );
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthSession>((ref) {
  return AuthController();
});

final summaryBoundaryProvider = Provider<SummaryBoundary>((ref) {
  return SummaryBoundaryImpl(
    reportService: ref.watch(reportServiceProvider),
    aiSummaryService: ref.watch(aiSummaryServiceProvider),
  );
});

final themeModeProvider = StateProvider<ThemeMode>((ref) {
  return ThemeMode.system;
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
