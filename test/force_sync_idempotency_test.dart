import 'package:flutter_test/flutter_test.dart';
import 'package:genzebet/features/sms_ingestion/application/account_mapping_service.dart';
import 'package:genzebet/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzebet/features/sms_ingestion/data/in_memory_sms_message_repository.dart';
import 'package:genzebet/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzebet/features/sms_ingestion/domain/repositories/device_sms_source.dart';
import 'package:genzebet/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzebet/features/sync/application/sync_service.dart';
import 'package:genzebet/features/sync/data/in_memory_cloud_sync_repository.dart';
import 'package:genzebet/features/transactions/data/in_memory_ledger_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Test-only fake; the app itself reads real device SMS on Android.
class _FakeDeviceSmsSource implements DeviceSmsSource {
  @override
  Future<SmsPermissionState> ensurePermission() async {
    return SmsPermissionState.granted;
  }

  @override
  Future<List<SmsMessage>> fetchRecentMessages({DateTime? since}) async {
    final messages = [
      SmsMessage(
        id: 'fake-cbe-1',
        sender: 'CBE',
        body:
            'CBE Alert: Your account was debited ETB 450.00 at supermarket. Bal ETB 9100.00',
        receivedAt: DateTime(2026, 6, 1, 9, 20),
      ),
      SmsMessage(
        id: 'fake-awash-1',
        sender: 'AWASH',
        body:
            'Awash Bank: Credited with ETB 2000.00 salary payment. Ref AXE1234',
        receivedAt: DateTime(2026, 6, 1, 11, 40),
      ),
      SmsMessage(
        id: 'fake-telebirr-1',
        sender: 'TELEBIRR',
        body:
            'Telebirr wallet paid ETB 150.50 for ride. Available balance ETB 600.20',
        receivedAt: DateTime(2026, 6, 2, 8, 10),
      ),
    ];
    if (since == null) return messages;
    return messages
        .where((message) => message.receivedAt.isAfter(since))
        .toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('force sync is idempotent for seeded device SMS', () async {
    final ledger = InMemoryLedgerRepository();
    final smsStore = InMemorySmsMessageRepository();
    final accountMapping = AccountMappingService(ledger);
    final ingestion = SmsIngestionService(
      parser: SmsParserEngine(
        const [
          CbeSmsParserTemplate(),
          AwashSmsParserTemplate(),
          TelebirrSmsParserTemplate(),
          BoaSmsParserTemplate(),
          HibretSmsParserTemplate(),
          DashenSmsParserTemplate(),
          GenericAmountParserTemplate(),
        ],
      ),
      ledgerRepository: ledger,
      smsMessageRepository: smsStore,
      accountMappingService: accountMapping,
    );
    final sync = SyncService(
      ledgerRepository: ledger,
      cloudSyncRepository: InMemoryCloudSyncRepository(),
      smsMessageRepository: smsStore,
      smsIngestionService: ingestion,
      deviceSmsSource: _FakeDeviceSmsSource(),
      accountMappingService: accountMapping,
    );

    final first = await sync.forceSyncFromSms();
    final txAfterFirst = await ledger.getTransactions();
    final ledgerAfterFirst = await ledger.getLedgerEntries();

    final second = await sync.forceSyncFromSms();
    final txAfterSecond = await ledger.getTransactions();
    final ledgerAfterSecond = await ledger.getLedgerEntries();

    expect(first.processed, greaterThan(0));
    expect(txAfterSecond.length, txAfterFirst.length);
    expect(ledgerAfterSecond.length, ledgerAfterFirst.length);
    expect(second.processed, first.processed);
  });
}
