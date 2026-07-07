import 'package:genzebet/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzebet/features/sms_ingestion/domain/repositories/sms_message_repository.dart';

class InMemorySmsMessageRepository implements SmsMessageRepository {
  final Map<String, StoredSmsMessage> _messagesById = {};

  @override
  Future<StoredSmsMessage?> getByHash(String messageHash) async {
    for (final entry in _messagesById.values) {
      if (entry.messageHash == messageHash) return entry;
    }
    return null;
  }

  @override
  Future<StoredSmsMessage?> getById(String smsId) async {
    return _messagesById[smsId];
  }

  @override
  Future<List<StoredSmsMessage>> getAll() async {
    final values = _messagesById.values.toList(growable: false);
    values.sort((a, b) => b.sms.receivedAt.compareTo(a.sms.receivedAt));
    return values;
  }

  @override
  Future<List<StoredSmsMessage>> getByStatus(SmsIngestionStatus status) async {
    return _messagesById.values
        .where((message) => message.status == status)
        .toList(growable: false);
  }

  @override
  Future<void> save(StoredSmsMessage message) async {
    _messagesById[message.sms.id] = message;
  }
}
