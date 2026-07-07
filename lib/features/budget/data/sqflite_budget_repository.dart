import 'dart:convert';

import 'package:genzebet/core/db/app_database.dart';
import 'package:genzebet/features/budget/domain/models/budget.dart';
import 'package:genzebet/features/budget/domain/repositories/budget_repository.dart';
import 'package:sqflite/sqflite.dart';

class SqfliteBudgetRepository implements BudgetRepository {
  SqfliteBudgetRepository(this._database);

  final AppDatabase _database;
  static const _legacyGeneralCategorySentinel = '__all__';

  @override
  Future<List<Budget>> getBudgets() async {
    final db = await _database.database;
    final rows = await db.query('budgets', orderBy: 'createdAt ASC');
    return rows
        .map(
          (row) => Budget(
            id: row['id'] as String,
            name: (row['name'] as String?)?.trim().isNotEmpty == true
                ? row['name'] as String
                : 'General budget',
            categoryIds: _decodeCategoryIds(row),
            institutionCodes: _decodeStringList(
              row['institutionCodes'] as String?,
            ),
            excludedTransactionIds: _decodeStringList(
              row['excludedTransactionIds'] as String?,
            ),
            limitMinor: row['limitMinor'] as int,
            createdAt: DateTime.parse(row['createdAt'] as String),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> upsertBudget(Budget budget) async {
    final db = await _database.database;
    await db.insert(
      'budgets',
      {
        'id': budget.id,
        'name': budget.name,
        'categoryIds': jsonEncode(budget.categoryIds),
        'institutionCodes': jsonEncode(budget.institutionCodes),
        'excludedTransactionIds': jsonEncode(budget.excludedTransactionIds),
        // Keep writing legacy column for backward compatibility.
        // Important: old upgraded databases may still enforce NOT NULL on
        // categoryId, so general budgets need a sentinel instead of null.
        'categoryId': budget.categoryIds.isEmpty
            ? _legacyGeneralCategorySentinel
            : budget.categoryIds.first,
        'limitMinor': budget.limitMinor,
        'createdAt': budget.createdAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteBudget(String id) async {
    final db = await _database.database;
    await db.delete('budgets', where: 'id = ?', whereArgs: [id]);
  }

  List<String> _decodeCategoryIds(Map<String, Object?> row) {
    final encoded = row['categoryIds'] as String?;
    if (encoded != null && encoded.trim().isNotEmpty) {
      final dynamic parsed = jsonDecode(encoded);
      if (parsed is List) {
        return parsed
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
      }
    }
    final legacy = (row['categoryId'] as String?)?.trim();
    if (legacy == null || legacy.isEmpty) return const <String>[];
    if (legacy == _legacyGeneralCategorySentinel) return const <String>[];
    return <String>[legacy];
  }

  List<String> _decodeStringList(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) return const <String>[];
    final dynamic parsed = jsonDecode(encoded);
    if (parsed is! List) return const <String>[];
    return parsed
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }
}
