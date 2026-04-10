import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/category.dart';
import '../theme/app_theme.dart';

class CategoryPieChartWidget extends StatelessWidget {
  final Map<String, double> categoryTotals;

  const CategoryPieChartWidget({super.key, required this.categoryTotals});

  @override
  Widget build(BuildContext context) {
    if (categoryTotals.isEmpty) {
      return const Center(child: Text('No data', style: TextStyle(color: AppColors.textMuted)));
    }

    final total = categoryTotals.values.fold<double>(0, (s, v) => s + v);
    final sorted = categoryTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 36,
                sections: sorted.map((entry) {
                  final cat = getCategoryById(entry.key);
                  final pct = total > 0 ? entry.value / total * 100 : 0.0;
                  return PieChartSectionData(
                    color: cat.color,
                    value: entry.value,
                    title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
                    radius: 42,
                    titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: sorted.take(5).map((entry) {
              final cat = getCategoryById(entry.key);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: cat.color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(cat.name, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
