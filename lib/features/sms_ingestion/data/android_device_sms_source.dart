import 'dart:io';
import 'dart:convert';

import 'package:android_sms_reader/android_sms_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:genzeb/core/logging/app_logger.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/device_sms_source.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android implementation that reads actual inbox SMS.
class AndroidDeviceSmsSource implements DeviceSmsSource {
  static const _pageSize = 200;

  @override
  Future<SmsPermissionState> ensurePermission() async {
    if (!Platform.isAndroid) return SmsPermissionState.unsupported;
    final status = await Permission.sms.status;
    if (status.isGranted) return SmsPermissionState.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return SmsPermissionState.permanentlyDenied;
    }
    final requested = await Permission.sms.request();
    if (requested.isGranted) return SmsPermissionState.granted;
    if (requested.isPermanentlyDenied || requested.isRestricted) {
      return SmsPermissionState.permanentlyDenied;
    }
    return SmsPermissionState.denied;
  }

  @override
  Future<SmsPermissionState> currentPermission() async {
    if (!Platform.isAndroid) return SmsPermissionState.unsupported;
    final status = await Permission.sms.status;
    if (status.isGranted) return SmsPermissionState.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return SmsPermissionState.permanentlyDenied;
    }
    return SmsPermissionState.denied;
  }

  @override
  Stream<SmsMessage> incomingMessages() {
    if (!Platform.isAndroid) return const Stream.empty();
    // The broadcast carries the network timestamp, not the inbox row's
    // received time, so these messages are only a signal to re-read the
    // inbox — ingesting them directly would duplicate on the next sync.
    return AndroidSMSReader.observeIncomingMessages().map((message) {
      return SmsMessage(
        id: 'live-${message.date}',
        sender: message.address.trim(),
        body: message.body.trim(),
        receivedAt: DateTime.fromMillisecondsSinceEpoch(message.date),
      );
    });
  }

  @override
  Future<List<SmsMessage>> fetchRecentMessages({DateTime? since}) async {
    if (!Platform.isAndroid) return const [];

    // Never prompt from here: callers decide when a prompt is appropriate.
    final permission = await currentPermission();
    if (permission != SmsPermissionState.granted) {
      AppLogger.info(
        'sms.device',
        'fetchRecentMessages: SMS permission not granted ($permission)',
      );
      return const [];
    }
    final results = <SmsMessage>[];
    var start = 0;
    var shouldContinue = true;
    while (shouldContinue) {
      final page = await AndroidSMSReader.fetchMessages(
        type: AndroidSMSType.inbox,
        start: start,
        count: _pageSize,
      );
      if (page.isEmpty) break;

      for (final message in page) {
        final receivedAt = DateTime.fromMillisecondsSinceEpoch(message.date);
        if (since != null && receivedAt.isBefore(since)) {
          shouldContinue = false;
          break;
        }

        final body = message.body.trim();
        if (body.isEmpty) continue;
        final sender =
            message.address.trim().isEmpty ? 'UNKNOWN' : message.address.trim();
        final stableId = _stableMessageId(
          sender: sender,
          body: body,
          receivedAt: receivedAt,
        );

        results.add(
          SmsMessage(
            id: stableId,
            sender: sender,
            body: body,
            receivedAt: receivedAt,
          ),
        );
      }

      if (page.length < _pageSize) break;
      start += _pageSize;
    }
    AppLogger.info(
      'sms.device',
      'fetchRecentMessages: returned=${results.length}, since=$since',
    );
    return results;
  }

  String _stableMessageId({
    required String sender,
    required String body,
    required DateTime receivedAt,
  }) {
    final payload = '$sender|$body|${receivedAt.toIso8601String()}';
    final digest =
        sha1.convert(utf8.encode(payload)).toString().substring(0, 16);
    return 'device-$digest';
  }
}
