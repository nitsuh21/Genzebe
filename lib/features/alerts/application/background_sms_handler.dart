import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:genzeb/core/l10n/app_strings.dart';
import 'package:genzeb/features/alerts/application/money_alert_service.dart';
import 'package:genzeb/features/alerts/domain/money_alert.dart';
import 'package:genzeb/features/alerts/presentation/alert_text.dart';
import 'package:genzeb/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';

/// What the native side needs to post one system notification.
class MoneyNotification {
  const MoneyNotification({
    required this.id,
    required this.title,
    required this.text,
    required this.publicText,
    required this.transactionId,
  });

  /// Stable per transaction, so a re-post replaces instead of stacking.
  final int id;
  final String title;
  final String text;

  /// Lock-screen version: never shows the amount or the counterparty.
  final String publicText;
  final String transactionId;

  Map<String, Object> toMap() => {
        'id': id,
        'title': title,
        'text': text,
        'publicText': publicText,
        'transactionId': transactionId,
      };
}

/// Handles a bank/wallet SMS that arrived while the app was closed: books
/// it exactly like an inbox sync would, records the in-app alert, and
/// returns the system notification to post. Returns null for anything that
/// isn't a new money movement from a recognised institution.
class BackgroundSmsHandler {
  BackgroundSmsHandler({
    required SmsIngestionService ingestion,
    required MoneyAlertService alerts,
    required AppStrings strings,
    required bool amountsHidden,
  })  : _ingestion = ingestion,
        _alerts = alerts,
        _strings = strings,
        _amountsHidden = amountsHidden;

  final SmsIngestionService _ingestion;
  final MoneyAlertService _alerts;
  final AppStrings _strings;
  final bool _amountsHidden;

  /// Same id scheme family as the inbox reader; the ingestion twin check
  /// makes the later inbox read of this message a no-op.
  static String liveMessageId({
    required String sender,
    required String body,
    required DateTime receivedAt,
  }) {
    final payload = '$sender|$body|${receivedAt.toIso8601String()}';
    return 'live-${sha1.convert(utf8.encode(payload)).toString().substring(0, 16)}';
  }

  Future<MoneyNotification?> handle({
    required String sender,
    required String body,
    required DateTime receivedAt,
  }) async {
    final trimmedSender = sender.trim();
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty || !isFinancialSender(trimmedSender)) return null;

    final record = await _ingestion.ingest(
      sms: SmsMessage(
        id: liveMessageId(
          sender: trimmedSender,
          body: trimmedBody,
          receivedAt: receivedAt,
        ),
        sender: trimmedSender,
        body: trimmedBody,
        receivedAt: receivedAt,
      ),
    );
    if (record == null) return null;
    final alert = await _alerts.recordTransaction(record);
    return notificationFor(alert);
  }

  MoneyNotification notificationFor(MoneyAlert alert) {
    final direction =
        alert.isIncome ? _strings.alertMoneyIn : _strings.alertMoneyOut;
    final institution = institutionInfoForCode(alert.institutionCode).shortName;
    final subtitle = alertSubtitle(alert);
    return MoneyNotification(
      id: alert.transactionId.hashCode & 0x7fffffff,
      title: '$direction · ${alertAmountLabel(alert, hidden: _amountsHidden)}',
      text: alert.needsReview
          ? '$subtitle · ${_strings.alertNeedsReview}'
          : subtitle,
      publicText: '$direction · $institution',
      transactionId: alert.transactionId,
    );
  }
}
