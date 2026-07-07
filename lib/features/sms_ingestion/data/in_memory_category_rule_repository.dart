import 'package:genzeb/features/sms_ingestion/domain/repositories/category_rule_repository.dart';

class InMemoryCategoryRuleRepository implements CategoryRuleRepository {
  final Map<String, CategoryRule> _rules = {};

  @override
  Future<String?> categoryForMerchant(String normalizedMerchant) async {
    return _rules[normalizedMerchant]?.categoryId;
  }

  @override
  Future<void> saveRule(String normalizedMerchant, String categoryId) async {
    if (normalizedMerchant.trim().isEmpty) return;
    _rules[normalizedMerchant] = CategoryRule(
      pattern: normalizedMerchant,
      categoryId: categoryId,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<List<CategoryRule>> getAll() async {
    return _rules.values.toList(growable: false);
  }

  @override
  Future<void> deleteRule(String pattern) async {
    _rules.remove(pattern);
  }
}
