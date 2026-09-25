import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:genzeb/core/db/app_database.dart';
import 'package:genzeb/core/l10n/app_strings.dart';
import 'package:genzeb/core/logging/app_logger.dart';
import 'package:genzeb/features/alerts/application/background_sms_handler.dart';
import 'package:genzeb/features/alerts/application/money_alert_service.dart';
import 'package:genzeb/features/alerts/data/money_alert_repositories.dart';
import 'package:genzeb/features/sms_ingestion/application/account_resolver.dart';
import 'package:genzeb/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzeb/features/sms_ingestion/data/sqflite_category_rule_repository.dart';
import 'package:genzeb/features/sms_ingestion/data/sqflite_sms_message_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/transactions/data/sqflite_ledger_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Channel shared with the native `BackgroundSmsRunner`.
const _channel = MethodChannel('genzeb/background');

/// Runs in a headless engine started by the native SMS receiver when a
/// message arrives and the app isn't in the foreground. Asks native for the
/// received messages, books them, posts a notification per new money
/// movement, then tells native it may shut the engine down.
Future<void> runBackgroundSmsEntry() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final messages =
        await _channel.invokeListMethod<Map<Object?, Object?>>('ready') ??
            const [];
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.instance;
    final ledger = SqfliteLedgerRepository(db);
    final handler = BackgroundSmsHandler(
      ingestion: SmsIngestionService(
        parser: buildDefaultSmsParserEngine(),
        ledgerRepository: ledger,
        smsMessageRepository: SqfliteSmsMessageRepository(db),
        accountResolver: AccountResolver(ledger),
        categoryRuleRepository: SqfliteCategoryRuleRepository(db),
      ),
      alerts: MoneyAlertService(SqfliteMoneyAlertRepository(db)),
      strings: _stringsFor(prefs.getString('app_language')),
      amountsHidden: prefs.getBool('amounts_hidden') ?? true,
    );
    for (final message in messages) {
      final notification = await handler.handle(
        sender: message['sender'] as String? ?? '',
        body: message['body'] as String? ?? '',
        receivedAt: DateTime.fromMillisecondsSinceEpoch(
          message['receivedAt'] as int? ??
              DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (notification != null) {
        await _channel.invokeMethod<void>('notify', notification.toMap());
      }
    }
  } catch (error) {
    AppLogger.info('sms.background', 'Background SMS handling failed: $error');
  } finally {
    await _channel.invokeMethod<void>('done');
  }
}

AppStrings _stringsFor(String? language) {
  final resolved = (language == null || language == 'system')
      ? ui.PlatformDispatcher.instance.locale.languageCode
      : language;
  return resolved == 'am' ? amStrings : enStrings;
}
