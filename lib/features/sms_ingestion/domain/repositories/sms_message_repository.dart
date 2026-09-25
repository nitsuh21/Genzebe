import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';

abstract class SmsMessageRepository {
  Future<StoredSmsMessage?> getById(String smsId);
  Future<StoredSmsMessage?> getByHash(String messageHash);
  Future<void> save(StoredSmsMessage message);
  Future<List<StoredSmsMessage>> getAll();
  Future<List<StoredSmsMessage>> getByStatus(SmsIngestionStatus status);
  Future<void> delete(String smsId);

  /// Another stored message with the same sender and text received within
  /// [window] of [around] — the same SMS seen twice (live broadcast vs.
  /// inbox row carry different timestamps).
  Future<StoredSmsMessage?> findTwin({
    required String sender,
    required String body,
    required DateTime around,
    required Duration window,
    required String excludingId,
  });
}
