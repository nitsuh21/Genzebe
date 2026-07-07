class CategoryRule {
  const CategoryRule({
    required this.pattern,
    required this.categoryId,
    required this.createdAt,
  });

  /// Normalized merchant name (see `normalizeMerchant`).
  final String pattern;
  final String categoryId;
  final DateTime createdAt;
}

/// User-taught categorization: "always file `merchant` under `category`".
/// Rules are learned from manual corrections and applied on every ingest,
/// so the same merchant is categorized correctly on all future syncs.
abstract class CategoryRuleRepository {
  Future<String?> categoryForMerchant(String normalizedMerchant);
  Future<void> saveRule(String normalizedMerchant, String categoryId);
  Future<List<CategoryRule>> getAll();
  Future<void> deleteRule(String pattern);
}
