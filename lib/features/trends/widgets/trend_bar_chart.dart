import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:junk_food_tracker/features/trends/models/trend_report.dart';
import 'package:junk_food_tracker/shared/utils/formatters.dart';

/// Stacked calorie bars: full height is total calories, the red cap is junk.
class TrendBarChart extends StatelessWidget {
  const TrendBarChart({super.key, required this.report});

  final TrendReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final buckets = report.buckets;
    final peak = buckets.fold<int>(
      0,
      (max, bucket) => bucket.totalCalories > max ? bucket.totalCalories : max,
    );
    final scale = _AxisScale.forPeak(peak);

    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = (constraints.maxWidth - 46) / buckets.length;
        final barWidth = (slotWidth * 0.58).clamp(3.0, 24.0);
        final axisStyle = theme.textTheme.labelSmall?.copyWith(
          color: colors.onSurfaceVariant,
        );

        return SizedBox(
          height: 240,
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: scale.maxY,
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => colors.inverseSurface,
                  tooltipBorderRadius: BorderRadius.circular(10),
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  maxContentWidth: 200,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final bucket = buckets[group.x];
                    final junkLine = bucket.junkCalories > 0
                        ? '\n${formatNumber(bucket.junkCalories)} kcal junk'
                        : '';
                    return BarTooltipItem(
                      '${_tooltipTitle(bucket)}\n'
                      '${formatNumber(bucket.totalCalories)} kcal total'
                      '$junkLine',
                      theme.textTheme.bodySmall?.copyWith(
                            color: colors.onInverseSurface,
                            fontWeight: FontWeight.w600,
                          ) ??
                          TextStyle(color: colors.onInverseSurface),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 46,
                    interval: scale.interval,
                    getTitlesWidget: (value, meta) {
                      if (value < 0 || value > scale.maxY + 0.01) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        child: Text(
                          formatNumber(value.round()),
                          style: axisStyle,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 || index >= buckets.length) {
                        return const SizedBox.shrink();
                      }
                      final bucket = buckets[index];
                      if (!_showBottomLabel(bucket)) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        child: Text(_bottomLabel(bucket), style: axisStyle),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: scale.interval,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: [
                for (var index = 0; index < buckets.length; index++)
                  BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: buckets[index].totalCalories.toDouble(),
                        width: barWidth,
                        color: colors.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                        rodStackItems: [
                          if (buckets[index].nonJunkCalories > 0)
                            BarChartRodStackItem(
                              0,
                              buckets[index].nonJunkCalories.toDouble(),
                              colors.primary,
                            ),
                          if (buckets[index].junkCalories > 0)
                            BarChartRodStackItem(
                              buckets[index].nonJunkCalories.toDouble(),
                              buckets[index].totalCalories.toDouble(),
                              colors.error,
                            ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
            duration: const Duration(milliseconds: 350),
          ),
        );
      },
    );
  }

  bool _showBottomLabel(TrendBucket bucket) {
    switch (report.period.range) {
      case TrendRange.day:
        return bucket.date.hour % 3 == 0;
      case TrendRange.week:
        return true;
      case TrendRange.month:
        final day = bucket.date.day;
        final lastDay = report.period.end.day;
        return day == 1 || (day - 1) % 5 == 0 || day == lastDay;
    }
  }

  String _bottomLabel(TrendBucket bucket) {
    switch (report.period.range) {
      case TrendRange.day:
        final hour = bucket.date.hour;
        final displayHour = hour % 12 == 0 ? 12 : hour % 12;
        return '$displayHour${hour < 12 ? 'a' : 'p'}';
      case TrendRange.week:
        return DateFormat('E').format(bucket.date);
      case TrendRange.month:
        return '${bucket.date.day}';
    }
  }

  String _tooltipTitle(TrendBucket bucket) {
    switch (report.period.range) {
      case TrendRange.day:
        return DateFormat('h a').format(bucket.date);
      case TrendRange.week:
        return DateFormat('EEE, MMM d').format(bucket.date);
      case TrendRange.month:
        return DateFormat('MMM d').format(bucket.date);
    }
  }
}

class _AxisScale {
  const _AxisScale(this.maxY, this.interval);

  factory _AxisScale.forPeak(int peak) {
    if (peak <= 0) return const _AxisScale(100, 25);

    final padded = peak * 1.08;
    final rawInterval = padded / 5;
    final exponent = (math.log(rawInterval) / math.ln10).floor();
    final magnitude = math.pow(10, exponent).toDouble();
    final normalized = rawInterval / magnitude;
    final nice = normalized <= 1
        ? 1.0
        : normalized <= 2
        ? 2.0
        : normalized <= 5
        ? 5.0
        : 10.0;
    // Calories are whole numbers; avoid fractional axis labels for tiny peaks.
    final interval = math.max(nice * magnitude, 1.0);
    final maxY = (padded / interval).ceil() * interval;

    return _AxisScale(maxY.toDouble(), interval);
  }

  final double maxY;
  final double interval;
}
