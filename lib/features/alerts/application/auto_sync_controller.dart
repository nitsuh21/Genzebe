import 'dart:async';

import 'package:genzeb/core/logging/app_logger.dart';
import 'package:genzeb/features/alerts/application/money_alert_service.dart';
import 'package:genzeb/features/alerts/domain/money_alert.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/device_sms_source.dart';
import 'package:genzeb/features/sync/application/sync_service.dart';

/// Keeps the ledger current without a manual "sync" button: refreshes on
/// launch, when the app returns to the foreground, and moments after a bank
/// or wallet SMS arrives while it is open. Each refresh that books fresh
/// money movements emits them on [newAlerts] for the in-app banner.
class AutoSyncController {
  AutoSyncController({
    required SyncService syncService,
    required MoneyAlertService alertService,
    required DeviceSmsSource deviceSmsSource,
    required void Function() onDataChanged,
  })  : _syncService = syncService,
        _alertService = alertService,
        _deviceSmsSource = deviceSmsSource,
        _onDataChanged = onDataChanged;

  final SyncService _syncService;
  final MoneyAlertService _alertService;
  final DeviceSmsSource _deviceSmsSource;
  final void Function() _onDataChanged;

  /// The SMS provider writes the inbox row shortly after the broadcast.
  static const incomingSettleDelay = Duration(seconds: 2);

  final _alerts = StreamController<List<MoneyAlert>>.broadcast();
  StreamSubscription<Object?>? _incoming;
  Timer? _debounce;
  bool _running = false;
  bool _rerun = false;

  /// Only react to live SMS while the app is on screen. In the background
  /// the native receiver books the message and posts a system notification;
  /// reacting here too would race it on the same database.
  bool foreground = true;

  Stream<List<MoneyAlert>> get newAlerts => _alerts.stream;

  void start() {
    _incoming ??= _deviceSmsSource.incomingMessages().listen(
      (message) {
        if (!foreground || !isFinancialSender(message.sender)) return;
        _debounce?.cancel();
        _debounce = Timer(incomingSettleDelay, refresh);
      },
      onError: (Object error) =>
          AppLogger.info('sync.auto', 'Incoming SMS listener error: $error'),
    );
  }

  /// Incremental refresh. Never prompts for permission; concurrent calls
  /// collapse into one follow-up run.
  Future<void> refresh() async {
    if (_running) {
      _rerun = true;
      return;
    }
    _running = true;
    try {
      do {
        _rerun = false;
        final result = await _syncService.forceSyncFromSms(
          incremental: true,
          requestPermission: false,
        );
        if (result.smsPermissionState != SmsPermissionState.granted) break;
        final alerts = await _alertService.recordFromSync(result);
        if (result.newTransactions.isNotEmpty) _onDataChanged();
        if (alerts.isNotEmpty && !_alerts.isClosed) _alerts.add(alerts);
      } while (_rerun);
    } catch (error) {
      AppLogger.info('sync.auto', 'Auto refresh failed: $error');
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _debounce?.cancel();
    _incoming?.cancel();
    _alerts.close();
  }
}
