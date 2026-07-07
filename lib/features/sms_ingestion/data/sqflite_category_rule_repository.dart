import 'package:genzeb/core/db/app_database.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/category_rule_repository.dart';
import 'package:sqflite/sqflite.dart';

class SqfliteCategoryRuleRepository implements CategoryRuleRepository {
  SqfliteCategoryRuleRepository(this._database);

  final AppDatabase _database;

  Future<Database> get _db => _database.database;

  @override
  Future<String?> categoryForMerchant(String normalizedMerchant) async {
    if (normalizedMerchant.trim().isEmpty) return null;
    final db = await _db;
    final rows = await db.query(
      'category_rules',
      where: 'pattern = ?',
      whereArgs: [normalizedMerchant],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['categoryId'] as String;
  }

  @override
  Future<void> saveRule(String normalizedMerchant, String categoryId) async {
    if (normalizedMerchant.trim().isEmpty) return;
    final db = await _db;
    await db.insert(
      'category_rules',
      {
        'pattern': normalizedMerchant,
        'categoryId': categoryId,
        'createdAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<CategoryRule>> getAll() async {
    final db = await _db;
    final rows = await db.query('category_rules', orderBy: 'createdAt DESC');
    return rows
        .map(
          (row) => CategoryRule(
            pattern: row['pattern'] as String,
            categoryId: row['categoryId'] as String,
            createdAt: DateTime.parse(row['createdAt'] as String),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> deleteRule(String pattern) async {
    final db = await _db;
    await db.delete(
      'category_rules',
      where: 'pattern = ?',
      whereArgs: [pattern],
    );
  }
}
