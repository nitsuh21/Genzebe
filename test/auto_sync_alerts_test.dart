import 'package:flutter_test/flutter_test.dart';
import 'package:genzeb/features/alerts/application/money_alert_service.dart';
import 'package:genzeb/features/alerts/data/money_alert_repositories.dart';
import 'package:genzeb/features/sms_ingestion/application/account_resolver.dart';
import 'package:genzeb/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzeb/features/sms_ingestion/data/in_memory_category_rule_repository.dart';
import 'package:genzeb/features/sms_ingestion/data/in_memory_sms_message_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/device_sms_source.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/sync/application/sync_service.dart';
import 'package:genzeb/features/transactions/data/in_memory_ledger_repository.dart';
import 'package:genzeb/features/transactions/domain/models/money.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Inbox implements DeviceSmsSource {
  final messages = <SmsMessage>[];

  @override
  Future<SmsPermissionState> ensurePermission() async =>
      SmsPermissionState.granted;

  @override
  Future<SmsPermissionState> currentPermission() async =>
      SmsPermissionState.granted;

  @override
  Stream<SmsMessage> incomingMessages() => const Stream.empty();

  @override
  Future<List<SmsMessage>> fetchRecentMessages({DateTime? since}) async {
    return messages
        .where((m) => since == null || m.receivedAt.isAfter(since))
        .toList();
  }
}

SmsMessage _sms(String id, String sender, String body, DateTime at) =>
    SmsMessage(id: id, sender: sender, body: body, receivedAt: at);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryLedgerRepository ledger;
  late InMemorySmsMessageRepository store;
  late _Inbox inbox;
  late SyncService sync;
  late MoneyAlertService alerts;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ledger = InMemoryLedgerRepository();
    store = InMemorySmsMessageRepository();
    inbox = _Inbox();
    final ingestion = SmsIngestionService(
      parser: buildDefaultSmsParserEngine(),
      ledgerRepository: ledger,
      smsMessageRepository: store,
      accountResolver: AccountResolver(ledger),
      categoryRuleRepository: InMemoryCategoryRuleRepository(),
    );
    sync = SyncService(
      smsMessageRepository: store,
      smsIngestionService: ingestion,
      deviceSmsSource: inbox,
      ledgerRepository: ledger,
    );
    alerts = MoneyAlertService(InMemoryMoneyAlertRepository());
  });

  test('only bank and wallet senders are read; each gets its own account',
      () async {
    final now = DateTime.now();
    inbox.messages.addAll([
      _sms(
          'cbe',
          'CBE',
          'Dear Customer your Account 1****111 has been debited with ETB 250.00. Your Current Balance is ETB 900.00. Thank you for Banking with CBE!',
          now.subtract(const Duration(days: 3))),
      _sms(
          'weg',
          'Wegagen',
          'Your account 01****5678 has been credited with ETB 1,000.00. Available balance ETB 2,000.00.',
          now.subtract(const Duration(days: 2))),
      _sms('friend', '+251911223344', 'Please send me 500 birr for lunch',
          now.subtract(const Duration(days: 1))),
      _sms('otp', 'VERIFY', 'Your verification code is 1234. Paid 5 birr.',
          now.subtract(const Duration(hours: 5))),
      _sms('promo', 'PROMO', 'You have received 1000 birr bonus! Click here',
          now.subtract(const Duration(hours: 2))),
    ]);

    final result = await sync.forceSyncFromSms();

    expect(result.deviceFetched, 5);
    expect(result.deviceFinancial, 2);
    expect(result.newTransactions, hasLength(2));
    expect(result.institutionsFound,
        {EthiopianInstitution.cbe, EthiopianInstitution.wegagen});
    final storedIds = (await store.getAll()).map((m) => m.sms.id).toSet();
    expect(storedIds, {'cbe', 'weg'}, reason: 'personal SMS never stored');
    expect(result.pendingReview, 0);
    final weg = await ledger.getTransactionById('sms-weg');
    expect(weg?.accountId, 'wegagen-main');
    final accounts = await ledger.getAccounts();
    expect(accounts.map((a) => a.institutionCode),
        containsAll(['cbe', 'wegagen']));
  });

  test('upgrade removes personal messages an old sync queued for review',
      () async {
    final at = DateTime.now().subtract(const Duration(days: 4));
    final personal = _sms('old-1', '+251911000000',
        'I sent you 300 birr yesterday, received?', at);
    await store.save(StoredSmsMessage(
      sms: personal,
      messageHash: 'h1',
      status: SmsIngestionStatus.pendingReview,
      parsedTransactionId: 'sms-old-1',
    ));
    await ledger.saveTransaction(TransactionRecord(
      id: 'sms-old-1',
      accountId: 'main-wallet',
      type: TransactionType.expense,
      amount: const Money(minorUnits: 30000),
      occurredAt: at,
      categoryId: 'expense',
      source: TransactionSource.sms,
      reviewStatus: TransactionReviewStatus.pendingReview,
    ));

    await sync.forceSyncFromSms();

    expect(await store.getById('old-1'), isNull);
    expect(await ledger.getTransactionById('sms-old-1'), isNull);
  });

  test('alerts: history import is silent, new money alerts exactly once',
      () async {
    final now = DateTime.now();
    inbox.messages.add(_sms(
        'hist',
        'CBE',
        'Your Account 1****111 has been credited with ETB 5,000.00. Your Current Balance is ETB 9,000.00.',
        now.subtract(const Duration(days: 40))));

    final first = await sync.forceSyncFromSms(incremental: true);
    expect(first.wasIncremental, isFalse, reason: 'no earlier sync');
    expect(await alerts.recordFromSync(first), isEmpty);

    inbox.messages.add(_sms(
        'fresh',
        '127',
        'You have received ETB 750.00 from Hana T. Your telebirr balance is ETB 1,020.00. Thank you for using telebirr',
        now.subtract(const Duration(minutes: 1))));
    final second = await sync.forceSyncFromSms(incremental: true);
    final raised = await alerts.recordFromSync(second);
    expect(raised, hasLength(1));
    expect(raised.single.isIncome, isTrue);
    expect(raised.single.amountMinor, 75000);
    expect(raised.single.institutionCode, 'telebirr');

    final third = await sync.forceSyncFromSms(incremental: true);
    expect(await alerts.recordFromSync(third), isEmpty);
    expect(await alerts.getAll(), hasLength(1));
  });

  test('alerts skip stale rows that surface late', () async {
    final now = DateTime.now();
    await sync.forceSyncFromSms(); // establishes the last-sync mark
    inbox.messages.add(_sms(
        'late',
        'CBE',
        'Your Account 1****111 has been debited with ETB 100.00. Your Current Balance is ETB 800.00.',
        now.subtract(const Duration(days: 1, hours: 20))));
    final result = await sync.forceSyncFromSms(incremental: true);
    expect(result.newTransactions, hasLength(1));
    expect(
      await alerts.recordFromSync(
        result,
        now: now.add(const Duration(days: 2)),
      ),
      isEmpty,
    );
  });
}
