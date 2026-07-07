import 'package:genzebet/features/sync/domain/repositories/cloud_sync_repository.dart';
import 'package:genzebet/features/transactions/domain/models/transaction_models.dart';

class InMemoryCloudSyncRepository implements CloudSyncRepository {
  final Map<String, List<TransactionRecord>> _store = {};
  final Map<String, DateTime> _lastSync = {};

  @override
  Future<List<TransactionRecord>> fetchTransactions(String userId) async {
    return List<TransactionRecord>.unmodifiable(_store[userId] ?? []);
  }

  @override
  Future<DateTime?> getLastSyncAt(String userId) async {
    return _lastSync[userId];
  }

  @override
  Future<void> saveTransactions({
    required String userId,
    required List<TransactionRecord> records,
  }) async {
    final existing = Map<String, TransactionRecord>.fromEntries(
      (_store[userId] ?? []).map((record) => MapEntry(record.id, record)),
    );
    for (final record in records) {
      existing[record.id] = record;
    }
    _store[userId] = existing.values.toList(growable: false);
    _lastSync[userId] = DateTime.now();
  }
}
