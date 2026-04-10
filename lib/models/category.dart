import 'package:flutter/material.dart';

class SpendCategory {
  final String id;
  final String name;
  final IconData icon;
  final Color color;

  const SpendCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
  });
}

const defaultCategories = [
  SpendCategory(
    id: 'income',
    name: 'Income',
    icon: Icons.trending_up,
    color: Color(0xFF89DCEB),
  ),
  SpendCategory(
    id: 'groceries',
    name: 'Groceries',
    icon: Icons.shopping_cart,
    color: Color(0xFFA6E3A1),
  ),
  SpendCategory(
    id: 'eating_out',
    name: 'Eating Out',
    icon: Icons.restaurant,
    color: Color(0xFFF9E2AF),
  ),
  SpendCategory(
    id: 'transport',
    name: 'Transport',
    icon: Icons.directions_car,
    color: Color(0xFF89B4FA),
  ),
  SpendCategory(
    id: 'shopping',
    name: 'Shopping',
    icon: Icons.shopping_bag,
    color: Color(0xFFCBA6F7),
  ),
  SpendCategory(
    id: 'bills',
    name: 'Bills & Utilities',
    icon: Icons.receipt_long,
    color: Color(0xFFF38BA8),
  ),
  SpendCategory(
    id: 'entertainment',
    name: 'Entertainment',
    icon: Icons.movie,
    color: Color(0xFFFAB387),
  ),
  SpendCategory(
    id: 'health',
    name: 'Health',
    icon: Icons.favorite,
    color: Color(0xFF94E2D5),
  ),
  SpendCategory(
    id: 'subscriptions',
    name: 'Subscriptions',
    icon: Icons.repeat,
    color: Color(0xFF74C7EC),
  ),
  SpendCategory(
    id: 'rent',
    name: 'Rent & Housing',
    icon: Icons.home,
    color: Color(0xFFF5C2E7),
  ),
  SpendCategory(
    id: 'transfer',
    name: 'Transfer',
    icon: Icons.swap_horiz,
    color: Color(0xFF9399B2),
  ),
  SpendCategory(
    id: 'other',
    name: 'Other',
    icon: Icons.more_horiz,
    color: Color(0xFFBAC2DE),
  ),
];

SpendCategory getCategoryById(String id) {
  return defaultCategories.firstWhere(
    (c) => c.id == id,
    orElse: () => defaultCategories.last,
  );
}
