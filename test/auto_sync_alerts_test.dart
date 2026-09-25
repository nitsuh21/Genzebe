import 'package:flutter_test/flutter_test.dart';
import 'package:genzeb/core/l10n/app_strings.dart';
import 'package:genzeb/features/alerts/application/background_sms_handler.dart';
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
  SmsPermissionState permission = SmsPermissionState.granted;

  @override
  Future<SmsPermissionState> ensurePermission() async => permission;

  @override
  Future<SmsPermissionState> currentPermission() async => permission;

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
  late SmsIngestionService ingestion;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ledger = InMemoryLedgerRepository();
    store = InMemorySmsMessageRepository();
    inbox = _Inbox();
    ingestion = SmsIngestionService(
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

  group('background SMS (app closed)', () {
    BackgroundSmsHandler handler({bool hidden = false}) => BackgroundSmsHandler(
          ingestion: ingestion,
          alerts: alerts,
          strings: enStrings,
          amountsHidden: hidden,
        );
    const body =
        'You have received ETB 750.00 from Hana T. Your telebirr balance is ETB 1,020.00. Thank you for using telebirr';

    test('books the SMS, records the alert and builds the notification',
        () async {
      final notification = await handler().handle(
        sender: '127',
        body: body,
        receivedAt: DateTime.now(),
      );
      expect(notification, isNotNull);
      expect(notification!.title, 'Money in · +ETB 750.00');
      expect(notification.text, 'telebirr · from Hana T');
      expect(notification.publicText, 'Money in · telebirr',
          reason: 'lock screen never shows the amount');
      expect(await ledger.getTransactionById(notification.transactionId),
          isNotNull);
      expect(await alerts.getAll(), hasLength(1));
    });

    test('hidden amounts stay hidden in the notification', () async {
      final notification = await handler(hidden: true).handle(
        sender: '127',
        body: body,
        receivedAt: DateTime.now(),
      );
      expect(notification!.title, 'Money in · + ETB ••••');
    });

    test('ignores personal and non-financial senders', () async {
      expect(
        await handler().handle(
          sender: '+251911223344',
          body: 'I sent you 500 birr',
          receivedAt: DateTime.now(),
        ),
        isNull,
      );
      expect(await store.getAll(), isEmpty);
    });

    test('the later inbox read of the same SMS never double-books', () async {
      await sync.forceSyncFromSms(); // establishes the last-sync mark
      final live = DateTime.now();
      await handler().handle(sender: '127', body: body, receivedAt: live);
      // The inbox row carries the device time, a few seconds apart.
      inbox.messages.add(
          _sms('inbox-row', '127', body, live.add(const Duration(seconds: 4))));

      final result = await sync.forceSyncFromSms(incremental: true);

      expect(result.newTransactions, isEmpty);
      final smsTransactions = (await ledger.getTransactions())
          .where((tx) => tx.source == TransactionSource.sms);
      expect(smsTransactions, hasLength(1));
      expect((await store.getById('inbox-row'))?.status,
          SmsIngestionStatus.duplicate);
    });
  });

  group('parser upgrade', () {
    final at = DateTime.now().subtract(const Duration(days: 5));
    const hibret =
        'Dear customer, Please be informed that ETB -1011.5 Outgoing Transfer To M-Pesa Via Mobile is made from your account 474041*******013  . Available Balance : 65065.87 Current Balance : 65065.87  .For further queries please call 995. United, We Prosper!';

    Future<void> simulateOldInstall() async {
      SharedPreferences.setMockInitialValues({
        'sms_last_sync_at': at.millisecondsSinceEpoch,
        'sms_parser_version': 1,
        'sms_non_financial_cleanup_v1': true,
      });
      // The old parser dropped this payment (signed amount).
      await store.save(StoredSmsMessage(
        sms: _sms('h1', 'HibretBank', hibret, at),
        messageHash: 'old',
        status: SmsIngestionStatus.failed,
      ));
      inbox.messages.add(_sms('h1', 'HibretBank', hibret, at));
    }

    test('re-parses history once so old misreads are corrected', () async {
      await simulateOldInstall();

      await sync.forceSyncFromSms(incremental: true, requestPermission: false);

      final tx = await ledger.getTransactionById('sms-h1');
      expect(tx?.amount.minorUnits, 101150);
      expect(tx?.type, TransactionType.expense);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('sms_parser_version'), kParserVersion);
    });

    test('never clears history without SMS access', () async {
      await simulateOldInstall();
      await ledger.saveTransaction(TransactionRecord(
        id: 'sms-kept',
        accountId: 'cbe-main',
        type: TransactionType.expense,
        amount: const Money(minorUnits: 100),
        occurredAt: at,
        categoryId: 'food',
        source: TransactionSource.sms,
      ));
      inbox.permission = SmsPermissionState.denied;

      await sync.forceSyncFromSms(incremental: true, requestPermission: false);

      expect(await ledger.getTransactionById('sms-kept'), isNotNull);
      expect(await store.getById('h1'), isNotNull);
    });
  });
}
