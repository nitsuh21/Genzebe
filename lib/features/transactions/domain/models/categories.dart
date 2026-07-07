import 'package:flutter/material.dart';

/// Display metadata for a transaction category.
class CategoryInfo {
  const CategoryInfo({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
}

/// Canonical category catalog used across the app.
const Map<String, CategoryInfo> kCategoryCatalog = {
  'salary': CategoryInfo(
    id: 'salary',
    label: 'Salary',
    icon: Icons.payments_rounded,
    color: Color(0xFF2E9E6B),
  ),
  'income': CategoryInfo(
    id: 'income',
    label: 'Income',
    icon: Icons.account_balance_wallet_rounded,
    color: Color(0xFF2E9E6B),
  ),
  'transfer_in': CategoryInfo(
    id: 'transfer_in',
    label: 'Transfer In',
    icon: Icons.south_west_rounded,
    color: Color(0xFF3B8DD6),
  ),
  'groceries': CategoryInfo(
    id: 'groceries',
    label: 'Groceries',
    icon: Icons.local_grocery_store_rounded,
    color: Color(0xFFE8833A),
  ),
  'food': CategoryInfo(
    id: 'food',
    label: 'Food & Drink',
    icon: Icons.restaurant_rounded,
    color: Color(0xFFEF6C5A),
  ),
  'transport': CategoryInfo(
    id: 'transport',
    label: 'Transport',
    icon: Icons.directions_bus_rounded,
    color: Color(0xFF6C6CE5),
  ),
  'shopping': CategoryInfo(
    id: 'shopping',
    label: 'Shopping',
    icon: Icons.shopping_bag_rounded,
    color: Color(0xFFD8589E),
  ),
  'bills': CategoryInfo(
    id: 'bills',
    label: 'Bills & Utilities',
    icon: Icons.receipt_long_rounded,
    color: Color(0xFF4AA3B5),
  ),
  'airtime': CategoryInfo(
    id: 'airtime',
    label: 'Airtime & Data',
    icon: Icons.smartphone_rounded,
    color: Color(0xFF8E63D8),
  ),
  'rent': CategoryInfo(
    id: 'rent',
    label: 'Rent & Housing',
    icon: Icons.home_rounded,
    color: Color(0xFFB07C4F),
  ),
  'health': CategoryInfo(
    id: 'health',
    label: 'Health',
    icon: Icons.favorite_rounded,
    color: Color(0xFFE2557B),
  ),
  'education': CategoryInfo(
    id: 'education',
    label: 'Education',
    icon: Icons.school_rounded,
    color: Color(0xFF4F86C6),
  ),
  'entertainment': CategoryInfo(
    id: 'entertainment',
    label: 'Entertainment',
    icon: Icons.movie_rounded,
    color: Color(0xFF9B5DE5),
  ),
  'savings': CategoryInfo(
    id: 'savings',
    label: 'Savings',
    icon: Icons.savings_rounded,
    color: Color(0xFF2E9E8F),
  ),
  'fees': CategoryInfo(
    id: 'fees',
    label: 'Fees & Charges',
    icon: Icons.account_balance_rounded,
    color: Color(0xFF8A8FA3),
  ),
  'transfer_out': CategoryInfo(
    id: 'transfer_out',
    label: 'Transfer Out',
    icon: Icons.north_east_rounded,
    color: Color(0xFFD08A3E),
  ),
  'expense': CategoryInfo(
    id: 'expense',
    label: 'Other Expense',
    icon: Icons.category_rounded,
    color: Color(0xFF7A8194),
  ),
  'other': CategoryInfo(
    id: 'other',
    label: 'Uncategorized',
    icon: Icons.help_outline_rounded,
    color: Color(0xFF7A8194),
  ),
};

/// Resolve display metadata for any category id, with a safe fallback.
CategoryInfo categoryInfoFor(String id) {
  return kCategoryCatalog[id] ??
      CategoryInfo(
        id: id,
        label: _humanizeId(id),
        icon: Icons.category_rounded,
        color: const Color(0xFF7A8194),
      );
}

/// Categories that users can select when adding a manual expense.
const List<String> kExpenseCategoryIds = [
  'groceries',
  'food',
  'transport',
  'shopping',
  'bills',
  'airtime',
  'rent',
  'health',
  'education',
  'entertainment',
  'savings',
  'fees',
  'transfer_out',
  'expense',
];

/// Categories that users can select when adding manual income.
const List<String> kIncomeCategoryIds = [
  'salary',
  'income',
  'transfer_in',
];

String _humanizeId(String id) {
  if (id.isEmpty) return 'Uncategorized';
  return id
      .replaceAll('_', ' ')
      .split(' ')
      .map((word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
