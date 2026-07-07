import 'package:genzebet/features/sms_ingestion/domain/models/sms_models.dart';

abstract class SmsMessageRepository {
  Future<StoredSmsMessage?> getById(String smsId);
  Future<StoredSmsMessage?> getByHash(String messageHash);
  Future<void> save(StoredSmsMessage message);
  Future<List<StoredSmsMessage>> getAll();
  Future<List<StoredSmsMessage>> getByStatus(SmsIngestionStatus status);
}
