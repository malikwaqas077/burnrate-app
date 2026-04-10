import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../theme/app_theme.dart';

class SpendingBarChart extends StatelessWidget {
  final List<TransactionModel> transactions;
  final String period;

  const SpendingBarChart({super.key, required this.transactions, required this.period});

  @override
  Widget build(BuildContext context) {
    final grouped = <String, double>{};

    for (final tx in transactions) {
      String key;
      if (period == 'week') {
        key = DateFormat('E').format(tx.date);
      } else if (period == 'month') {
        key = 'W${((tx.date.day - 1) ~/ 7) + 1}';
      } else {
        key = DateFormat('MMM').format(tx.date);
      }
      grouped[key] = (grouped[key] ?? 0) + tx.absAmount;
    }

    List<String> labels;
    if (period == 'week') {
      labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    } else if (period == 'month') {
      labels = ['W1', 'W2', 'W3', 'W4', 'W5'];
    } else {
      labels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    }

    final maxVal = grouped.values.isEmpty ? 100.0 : grouped.values.reduce((a, b) => a > b ? a : b) * 1.2;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: BarChart(
        BarChartData(
          maxY: maxVal,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.surfaceLight,
              getTooltipItem: (group, gIndex, rod, rIndex) {
                return BarTooltipItem(
                  '£${rod.toY.toStringAsFixed(2)}',
                  const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= labels.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(labels[idx], style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: labels.asMap().entries.map((e) {
            final val = grouped[e.value] ?? 0;
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: val,
                  color: AppColors.primary,
                  width: period == 'year' ? 14 : 24,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
