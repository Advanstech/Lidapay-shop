import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../dashboard/data/dashboard_models.dart';

/// Interactive cash-flow curve over daily buckets (oldest → newest).
/// Touch/drag to inspect a day's total; the crosshair, dot and tooltip
/// follow the finger like the platform finance charts do.
class SpendCurve extends StatefulWidget {
  const SpendCurve({super.key, required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  State<SpendCurve> createState() => _SpendCurveState();
}

class _SpendCurveState extends State<SpendCurve> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gridColor = isDark ? Colors.white10 : const Color(0xFFEDE9F4);
    final labelColor = isDark ? Colors.white38 : const Color(0xFF9B95A8);
    final values = widget.values;
    if (values.isEmpty) return const SizedBox(height: 180);

    final maxV = values.reduce(math.max);
    // All-zero series still gets a baseline so the axes/tooltip work.
    final top = maxV <= 0 ? 1.0 : maxV * 1.15;
    final firstDay = DateTime.now().subtract(Duration(days: values.length - 1));

    String dayLabel(int i) {
      final d = firstDay.add(Duration(days: i));
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[d.month - 1]} ${d.day}';
    }

    return SizedBox(
      height: 200,
      width: double.infinity,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: top,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: top / 3,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: gridColor, strokeWidth: 1, dashArray: [4, 6]),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                interval: top / 3,
                getTitlesWidget: (value, meta) => Text(
                  Formatters.compact(value),
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: math.max(1, (values.length / 4).floorToDouble()),
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= values.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      dayLabel(i),
                      style: TextStyle(
                        color: labelColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchSpotThreshold: 24,
            getTouchedSpotIndicator: (bar, indexes) => indexes
                .map(
                  (_) => TouchedSpotIndicatorData(
                    FlLine(
                      color: widget.color.withValues(alpha: 0.35),
                      strokeWidth: 2,
                      dashArray: [3, 4],
                    ),
                    FlDotData(
                      show: true,
                      getDotPainter: (spot, _, _, _) =>
                          FlDotCirclePainter(
                            radius: 5,
                            color: widget.color,
                            strokeWidth: 2.5,
                            strokeColor: isDark
                                ? AppColors.darkSurface
                                : Colors.white,
                          ),
                    ),
                  ),
                )
                .toList(),
            touchTooltipData: LineTouchTooltipData(
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipColor: (_) =>
                  isDark ? const Color(0xFF2C2440) : const Color(0xFF241E33),
              tooltipBorderRadius: BorderRadius.circular(12),
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              getTooltipItems: (spots) => spots
                  .map(
                    (s) => LineTooltipItem(
                      '${dayLabel(s.x.round())}\n${Formatters.money(s.y)}',
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < values.length; i++)
                  FlSpot(i.toDouble(), values[i]),
              ],
              isCurved: true,
              curveSmoothness: 0.28,
              preventCurveOverShooting: true,
              color: widget.color,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    widget.color.withValues(alpha: 0.32),
                    widget.color.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

/// Delivery-outcomes donut. Slices expand on touch and the centre shows the
/// touched slice's share; legend rows below double as touch targets.
class OutcomeBreakdown extends StatefulWidget {
  const OutcomeBreakdown({super.key, required this.outcomes});

  final Map<TransactionStatus, int> outcomes;

  @override
  State<OutcomeBreakdown> createState() => _OutcomeBreakdownState();
}

class _OutcomeBreakdownState extends State<OutcomeBreakdown> {
  int _touched = -1;

  static const _meta =
      <TransactionStatus, ({Color color, IconData icon, String label})>{
        TransactionStatus.success: (
          color: AppColors.success,
          icon: Icons.check_circle_rounded,
          label: 'Delivered',
        ),
        TransactionStatus.pending: (
          color: Color(0xFFF2A33C),
          icon: Icons.schedule_rounded,
          label: 'Pending',
        ),
        TransactionStatus.failed: (
          color: AppColors.error,
          icon: Icons.cancel_rounded,
          label: 'Failed',
        ),
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statuses = _meta.keys.toList();
    final counts = [
      for (final s in statuses) widget.outcomes[s] ?? 0,
    ];
    final total = counts.fold<int>(0, (a, b) => a + b);

    Widget legendRow(int index) {
      final s = statuses[index];
      final meta = _meta[s]!;
      final count = counts[index];
      final share = total == 0 ? 0.0 : count / total;
      final selected = _touched == index;
      return GestureDetector(
        onTap: () => setState(() => _touched = selected ? -1 : index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? meta.color.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? meta.color.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(meta.icon, size: 17, color: meta.color),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  meta.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : const Color(0xFF4A4458),
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF241E33),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                child: Text(
                  '${(share * 100).round()}%',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white54 : const Color(0xFF9B95A8),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 190,
          child: total == 0
              ? Center(
                  child: Icon(
                    Icons.donut_large_rounded,
                    size: 56,
                    color: isDark ? Colors.white12 : const Color(0xFFE8E4EF),
                  ),
                )
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        pieTouchData: PieTouchData(
                          touchCallback: (event, response) {
                            if (!event.isInterestedForInteractions ||
                                response?.touchedSection == null) {
                              if (_touched != -1) {
                                setState(() => _touched = -1);
                              }
                              return;
                            }
                            final idx = response!
                                .touchedSection!
                                .touchedSectionIndex;
                            if (idx != _touched) setState(() => _touched = idx);
                          },
                        ),
                        sectionsSpace: 3,
                        centerSpaceRadius: 52,
                        centerSpaceColor: Colors.transparent,
                        sections: [
                          for (var i = 0; i < statuses.length; i++)
                            if (counts[i] > 0)
                              PieChartSectionData(
                                value: counts[i].toDouble(),
                                color: _meta[statuses[i]]!.color,
                                radius: _touched == i ? 30 : 22,
                                showTitle: false,
                              ),
                        ],
                      ),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    ),
                    // Centre readout: total, or the touched slice's share.
                    IgnorePointer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _touched >= 0 && counts[_touched] > 0
                                ? '${(counts[_touched] / total * 100).round()}%'
                                : '$total',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: _touched >= 0
                                  ? _meta[statuses[_touched]]!.color
                                  : (isDark
                                        ? Colors.white
                                        : const Color(0xFF241E33)),
                            ),
                          ),
                          Text(
                            _touched >= 0
                                ? _meta[statuses[_touched]]!.label
                                : 'transactions',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white38
                                  : const Color(0xFF9B95A8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        for (var i = 0; i < statuses.length; i++) legendRow(i),
      ],
    );
  }
}

/// Transaction-count bars by weekday — the "when are you active" pictograph.
/// Touch a bar for its count; your peak day is highlighted.
class WeekdayActivityBars extends StatelessWidget {
  const WeekdayActivityBars({super.key, required this.counts});

  /// Mon → Sun transaction counts.
  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    if (counts.length < 7) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxV = counts.reduce(math.max);
    if (maxV <= 0) return const SizedBox.shrink();
    final peak = counts.indexOf(maxV);
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final labelColor = isDark ? Colors.white38 : const Color(0xFF9B95A8);
    final barColor = AppColors.primary;

    return SizedBox(
      height: 170,
      width: double.infinity,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxV * 1.25,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i > 6) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      days[i],
                      style: TextStyle(
                        color: i == peak ? barColor : labelColor,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: BarTouchTooltipData(
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipColor: (_) =>
                  isDark ? const Color(0xFF2C2440) : const Color(0xFF241E33),
              tooltipBorderRadius: BorderRadius.circular(10),
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${rod.toY.round()} transactions',
                const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < 7; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: counts[i].toDouble(),
                    width: 20,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(7),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: i == peak
                          ? [barColor, barColor.withValues(alpha: 0.65)]
                          : [
                              barColor.withValues(alpha: 0.35),
                              barColor.withValues(alpha: 0.15),
                            ],
                    ),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: maxV * 1.25,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : const Color(0xFFF4F1F8),
                    ),
                  ),
                ],
              ),
          ],
        ),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

/// Category spend pictograph — one row per type: icon, proportional bar,
/// count and amount. Sorted biggest-first.
class CategoryBars extends StatelessWidget {
  const CategoryBars({super.key, required this.totals, required this.counts});

  final Map<TransactionType, double> totals;
  final Map<TransactionType, int> counts;

  static const _meta = <TransactionType, ({IconData icon, Color color})>{
    TransactionType.airtime: (
      icon: Icons.phone_iphone_rounded,
      color: Color(0xFF7B4FE0),
    ),
    TransactionType.data: (icon: Icons.wifi_rounded, color: Color(0xFF2E9BD6)),
    TransactionType.shopOrder: (
      icon: Icons.shopping_bag_rounded,
      color: Color(0xFFE2608F),
    ),
    TransactionType.lidaValue: (
      icon: Icons.diamond_rounded,
      color: AppColors.violet,
    ),
    TransactionType.walletTopUp: (
      icon: Icons.account_balance_wallet_rounded,
      color: Color(0xFF2BA98E),
    ),
    TransactionType.other: (
      icon: Icons.receipt_long_rounded,
      color: Color(0xFF8A8299),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final maxV = entries.first.value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: (_meta[e.key]?.color ?? AppColors.primary)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _meta[e.key]?.icon ?? Icons.receipt_long_rounded,
                    size: 17,
                    color: _meta[e.key]?.color ?? AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.key.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF241E33),
                              ),
                            ),
                          ),
                          Text(
                            Formatters.money(e.value),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF241E33),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TweenAnimationBuilder<double>(
                        tween: Tween(
                          begin: 0,
                          end: maxV <= 0 ? 0 : e.value / maxV,
                        ),
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: v,
                            minHeight: 7,
                            backgroundColor: isDark
                                ? Colors.white10
                                : const Color(0xFFEDE9F3),
                            valueColor: AlwaysStoppedAnimation(
                              _meta[e.key]?.color ?? AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${counts[e.key] ?? 0} transactions',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.white38
                              : const Color(0xFF9B95A8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
