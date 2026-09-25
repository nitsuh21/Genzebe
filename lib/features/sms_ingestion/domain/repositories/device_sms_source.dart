import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';

enum SmsPermissionState {
  granted,
  denied,
  permanentlyDenied,
  unsupported,
}

abstract class DeviceSmsSource {
  /// Asks for the permission when it hasn't been granted yet.
  Future<SmsPermissionState> ensurePermission();

  /// The current permission state, without ever showing a system prompt —
  /// for background refreshes (app resume, incoming SMS).
  Future<SmsPermissionState> currentPermission();

  Future<List<SmsMessage>> fetchRecentMessages({DateTime? since});

  /// Messages arriving while the app is running. Empty on platforms (and in
  /// tests) that can't observe the inbox.
  Stream<SmsMessage> incomingMessages();
}
