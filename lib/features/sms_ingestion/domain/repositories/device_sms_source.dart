import 'package:genzebet/features/sms_ingestion/domain/models/sms_models.dart';

enum SmsPermissionState {
  granted,
  denied,
  permanentlyDenied,
  unsupported,
}

abstract class DeviceSmsSource {
  Future<SmsPermissionState> ensurePermission();
  Future<List<SmsMessage>> fetchRecentMessages({DateTime? since});
}
