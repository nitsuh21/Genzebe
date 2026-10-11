import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genzeb/app/providers.dart';
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
import 'package:genzeb/features/sync/data/excluded_institutions_store.dart';
import 'package:genzeb/features/transactions/data/in_memory_ledger_repository.dart';
import 'package:genzeb/features/transactions/domain/models/money.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Inbox implements DeviceSmsSource {
  final messages = <SmsMessage>[];
  var reads = 0;

  /// Holds a read open until completed.
  Completer<void>? gate;

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
    reads += 1;
    await gate?.future;
    return messages
        .where((m) => since == null || m.receivedAt.isAfter(since))
        .toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryLedgerRepository ledger;
  late InMemorySmsMessageRepository store;
  late SmsIngestionService ingestion;
  late _Inbox inbox;
  late SyncService sync;

  final now = DateTime.now();
  SmsMessage sms(String id, String sender, String body, int daysAgo) =>
      SmsMessage(
        id: id,
        sender: sender,
        body: body,
        receivedAt: now.subtract(Duration(days: daysAgo)),
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ledger = InMemoryLedgerRepository();
    store = InMemorySmsMessageRepository();
    inbox = _Inbox()
      ..messages.addAll([
        sms(
          'cbe-1',
          'CBE',
          'CBE Alert: Your account was debited ETB 450.00 at supermarket. '
              'Bal ETB 9100.00',
          3,
        ),
        sms(
          'cbe-2',
          'CBE',
          'CBE Alert: Your account was debited ETB 120.00 at pharmacy. '
              'Bal ETB 8980.00',
          2,
        ),
        sms(
          'awash-1',
          'AWASH',
          'Awash Bank: Credited with ETB 2000.00 salary payment. Ref AXE1234',
          2,
        ),
        sms(
          'telebirr-1',
          'TELEBIRR',
          'Telebirr wallet paid ETB 150.50 for ride. Available balance ETB '
              '600.20',
          1,
        ),
        sms('friend', '+251911000000', 'See you at 6', 1),
      ]);
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
  });

  Future<Set<String>> transactionIds() async =>
      {for (final tx in await ledger.getTransactions()) tx.id};

  Future<Set<String>> accountIds() async =>
      {for (final account in await ledger.getAccounts()) account.id};

  test('a scan finds the banks without storing anything', () async {
    final scan = await sync.scanInbox();

    expect(scan.institutions, [
      (EthiopianInstitution.cbe, 2),
      (EthiopianInstitution.awash, 1),
      (EthiopianInstitution.telebirr, 1),
    ]);
    expect(scan.fetchedCount, 5);
    expect(await store.getAll(), isEmpty);
    expect(await ledger.getTransactions(), isEmpty);
  });

  test('the first import books the scan minus the banks left out', () async {
    final scan = await sync.scanInbox();
    await sync.setExcludedInstitutions({EthiopianInstitution.cbe});
    final result = await sync.forceSyncFromSms(
      requestPermission: false,
      scan: scan,
    );

    // The scan is reused: the inbox is read once.
    expect(inbox.reads, 1);
    expect(result.institutionsFound, {
      EthiopianInstitution.awash,
      EthiopianInstitution.telebirr,
    });
    expect(await transactionIds(), {'sms-awash-1', 'sms-telebirr-1'});
    expect(await accountIds(), isNot(contains('cbe-main')));
  });

  test('every later sync and rebuild keeps skipping a bank turned off',
      () async {
    await const ExcludedInstitutionsStore()
        .save({EthiopianInstitution.telebirr});

    await sync.forceSyncFromSms();
    await sync.forceSyncFromSms(incremental: true);
    await sync.forceSyncFromSms(rebuild: true);

    expect(
      await transactionIds(),
      {'sms-cbe-1', 'sms-cbe-2', 'sms-awash-1'},
    );
  });

  test('turning a bank off removes it; turning it on brings it back', () async {
    await sync.forceSyncFromSms();
    // The user's own entry and a rejection must survive.
    await ledger.saveTransaction(TransactionRecord(
      id: 'manual-1',
      accountId: 'main-wallet',
      type: TransactionType.expense,
      amount: const Money(minorUnits: 5000),
      occurredAt: now,
      categoryId: 'food',
      source: TransactionSource.manual,
    ));
    final cbe2 = (await store.getById('cbe-2'))!;
    await ledger.deleteTransaction(cbe2.parsedTransactionId!);
    await store.save(cbe2.copyWith(status: SmsIngestionStatus.rejected));

    await sync.excludeInstitution(EthiopianInstitution.cbe);

    expect(
      await transactionIds(),
      {'sms-awash-1', 'sms-telebirr-1', 'manual-1'},
    );
    expect(await accountIds(), isNot(contains('cbe-main')));
    expect(await store.getById('cbe-1'), isNull);
    expect((await store.getById('cbe-2'))?.status, SmsIngestionStatus.rejected);
    expect(await sync.excludedInstitutions(), {EthiopianInstitution.cbe});

    // A plain refresh doesn't bring it back...
    await sync.forceSyncFromSms(incremental: true);
    expect(await transactionIds(), isNot(contains('sms-cbe-1')));

    // ...turning it on does, with its history, and the rejection holds.
    final result = await sync.includeInstitution(EthiopianInstitution.cbe);
    expect(result.newTransactions.map((tx) => tx.id), ['sms-cbe-1']);
    expect(await transactionIds(), contains('sms-cbe-1'));
    expect(await transactionIds(), isNot(contains('sms-cbe-2')));
    expect(await accountIds(), contains('cbe-main'));
    expect(await sync.excludedInstitutions(), isEmpty);
  });

  test('a sync already running cannot rebook a bank being turned off',
      () async {
    // The sync has read its exclusions and is waiting on the inbox when
    // the bank is turned off.
    inbox.gate = Completer<void>();
    final running = sync.forceSyncFromSms();
    await pumpEventQueue();
    final excluding = sync.excludeInstitution(EthiopianInstitution.awash);
    await pumpEventQueue();
    inbox.gate!.complete();
    await Future.wait([running, excluding]);

    expect(await transactionIds(), isNot(contains('sms-awash-1')));
    expect(await accountIds(), isNot(contains('awash-main')));
  });

  test(
      'a message arriving in the background from a bank turned off is '
      'ignored', () async {
    final alerts = InMemoryMoneyAlertRepository();
    final handler = BackgroundSmsHandler(
      ingestion: ingestion,
      alerts: MoneyAlertService(alerts),
      strings: enStrings,
      amountsHidden: true,
      excluded: {EthiopianInstitution.cbe},
    );

    final skipped = await handler.handle(
      sender: 'CBE',
      body: 'CBE Alert: Your account was debited ETB 75.00 at cafe. '
          'Bal ETB 8905.00',
      receivedAt: now,
    );
    final kept = await handler.handle(
      sender: 'AWASH',
      body: 'Awash Bank: Credited with ETB 300.00 transfer. Ref AXE9999',
      receivedAt: now,
    );

    expect(skipped, isNull);
    expect(kept, isNotNull);
    expect(await store.getAll(), hasLength(1));
    expect(await alerts.getAll(), hasLength(1));
  });

  test('a choice made while the stored set is still loading sticks', () async {
    final controller = ExcludedInstitutionsController(sync, () {});
    await controller.replaceAll({EthiopianInstitution.hibret});
    await pumpEventQueue();

    expect(controller.state, {EthiopianInstitution.hibret});
    expect(await sync.excludedInstitutions(), {EthiopianInstitution.hibret});
  });
}
