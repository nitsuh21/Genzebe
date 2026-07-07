import 'package:genzebet/features/transactions/domain/models/transaction_models.dart';

abstract class CloudSyncRepository {
  Future<void> saveTransactions({
    required String userId,
    required List<TransactionRecord> records,
  });
  Future<List<TransactionRecord>> fetchTransactions(String userId);
  Future<DateTime?> getLastSyncAt(String userId);
}
