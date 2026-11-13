import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/skeleton.dart';
import '../../dashboard/data/dashboard_models.dart';
import '../data/history_models.dart';
import '../providers.dart';
import '../widgets/history_charts.dart';

/// Transaction intelligence — server stats plus a client-side aggregation
/// of the merged feed: spend curve, category pictograph, delivery outcomes,
/// failure reasons and generated guidance.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  /// 0 = money out curve, 1 = money in curve.
  int _curveTab = 0;

  Future<void> _refresh() => ref.refresh(historyAnalyticsProvider.future);

  @override
  Widget build(BuildContext context) {
    final analytics = ref.watch(historyAnalyticsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: topInset + 68,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: _AnalyticsHero(
                topInset: topInset,
                onBack: () => Navigator.of(context).maybePop(),
                analytics: analytics.valueOrNull,
              ),
            ),
            analytics.when(
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      AppSkeleton(height: 210, borderRadius: 22),
                      SizedBox(height: 14),
                      AppSkeleton(height: 160, borderRadius: 22),
                      SizedBox(height: 14),
                      AppSkeleton(height: 140, borderRadius: 22),
                    ],
                  ),
                ),
              ),
              error: (error, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorView(message: error.toString(), onRetry: _refresh),
              ),
              data: (data) => SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _FlowCurveCard(
                      analytics: data,
                      tab: _curveTab,
                      onTabChanged: (i) => setState(() => _curveTab = i),
                      isDark: isDark,
                    ),
                    const SizedBox(height: 14),
                    _OutcomesCard(analytics: data, isDark: isDark),
                    if (data.failureReasons.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _FailuresCard(analytics: data, isDark: isDark),
                    ],
                    const SizedBox(height: 14),
                    _CategoryCard(analytics: data, isDark: isDark),
                    const SizedBox(height: 14),
                    _Card(
                      title: 'When you transact',
                      subtitle: 'by weekday',
                      icon: Icons.bar_chart_rounded,
                      isDark: isDark,
                      child: WeekdayActivityBars(
                        counts: data.weekdayCounts,
                      ),
                    ),
                    if (data.stats.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _ServerStatsCard(analytics: data, isDark: isDark),
                    ],
                    const SizedBox(height: 14),
                    _InsightsCard(analytics: data, isDark: isDark),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsHero extends StatelessWidget {
  const _AnalyticsHero({
    required this.topInset,
    required this.onBack,
    required this.analytics,
  });

  final double topInset;
  final VoidCallback onBack;
  final HistoryAnalytics? analytics;

  @override
  Widget build(BuildContext context) {
    final a = analytics;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topInset + 10, 20, 22),
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Insights',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeroPill(
                  label: 'Success rate',
                  value: a == null ? '—' : '${(a.successRate * 100).round()}%',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroPill(
                  label: 'Money out',
                  value: a == null ? '—' : Formatters.money(a.moneyOut),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroPill(
                  label: 'Money in',
                  value: a == null ? '—' : Formatters.money(a.moneyIn),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.icon,
    required this.child,
    required this.isDark,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFEDEAF3),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF241E33),
                  ),
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white38 : const Color(0xFF9B95A8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _FlowCurveCard extends StatelessWidget {
  const _FlowCurveCard({
    required this.analytics,
    required this.tab,
    required this.onTabChanged,
    required this.isDark,
  });

  final HistoryAnalytics analytics;
  final int tab;
  final ValueChanged<int> onTabChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final values = tab == 0 ? analytics.dailyOut : analytics.dailyIn;
    final color = tab == 0 ? AppColors.primary : AppColors.success;
    return _Card(
      title: 'Cash flow — last 30 days',
      subtitle: 'GHS',
      icon: Icons.show_chart_rounded,
      isDark: isDark,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFF1EEF6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [_curveTab('Spending', 0), _curveTab('Received', 1)],
            ),
          ),
          const SizedBox(height: 12),
          SpendCurve(values: values, color: color),
        ],
      ),
    );
  }

  Widget _curveTab(String label, int index) {
    final selected = tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTabChanged(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: selected
                  ? Colors.white
                  : (isDark ? Colors.white54 : const Color(0xFF7A728C)),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutcomesCard extends StatelessWidget {
  const _OutcomesCard({required this.analytics, required this.isDark});

  final HistoryAnalytics analytics;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Delivery outcomes',
      icon: Icons.pie_chart_rounded,
      isDark: isDark,
      child: OutcomeBreakdown(outcomes: analytics.outcomes),
    );
  }
}

class _FailuresCard extends StatelessWidget {
  const _FailuresCard({required this.analytics, required this.isDark});

  final HistoryAnalytics analytics;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final maxCount = analytics.failureReasons.first.value;
    return _Card(
      title: 'Why transactions fail',
      subtitle: 'top reasons',
      icon: Icons.report_problem_outlined,
      isDark: isDark,
      child: Column(
        children: [
          for (final e in analytics.failureReasons.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.key,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF241E33),
                          ),
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: e.value / maxCount,
                            minHeight: 6,
                            backgroundColor: isDark
                                ? Colors.white10
                                : const Color(0xFFF0EDF5),
                            valueColor: const AlwaysStoppedAnimation(
                              AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '×${e.value}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.analytics, required this.isDark});

  final HistoryAnalytics analytics;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Where the money goes',
      subtitle: 'GHS spend',
      icon: Icons.donut_small_rounded,
      isDark: isDark,
      child: CategoryBars(
        totals: analytics.categoryTotals,
        counts: analytics.categoryCounts,
      ),
    );
  }
}

class _ServerStatsCard extends StatelessWidget {
  const _ServerStatsCard({required this.analytics, required this.isDark});

  final HistoryAnalytics analytics;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // Server buckets grouped by type for readability.
    final byType = <String, List<TransactionStat>>{};
    for (final s in analytics.stats) {
      byType.putIfAbsent(s.type.label, () => []).add(s);
    }
    final fmt = DateFormat.yMMMd();

    return _Card(
      title: 'Server aggregates',
      subtitle: 'stats endpoint',
      icon: Icons.query_stats_rounded,
      isDark: isDark,
      child: Column(
        children: [
          for (final entry in byType.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white60 : const Color(0xFF7A728C),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
            for (final s in entry.value)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      switch (s.status) {
                        TransactionStatus.success =>
                          Icons.check_circle_outline_rounded,
                        TransactionStatus.pending => Icons.schedule_rounded,
                        TransactionStatus.failed => Icons.cancel_outlined,
                      },
                      size: 15,
                      color: switch (s.status) {
                        TransactionStatus.success => AppColors.success,
                        TransactionStatus.pending => const Color(0xFFF2A33C),
                        TransactionStatus.failed => AppColors.error,
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${s.status.name[0].toUpperCase()}'
                        '${s.status.name.substring(1)} · ×${s.count}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF4A4458),
                        ),
                      ),
                    ),
                    Text(
                      '${Formatters.money(s.totalAmount)} '
                      '(avg ${Formatters.money(s.avgAmount)})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Colors.white54
                            : const Color(0xFF9B95A8),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'As of ${fmt.format(DateTime.now())} — from the transactions '
              'stats endpoint.',
              style: TextStyle(
                fontSize: 10.5,
                color: isDark ? Colors.white30 : const Color(0xFFB7B1C4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.analytics, required this.isDark});

  final HistoryAnalytics analytics;
  final bool isDark;

  Color _tone(InsightTone tone) => switch (tone) {
    InsightTone.good => AppColors.success,
    InsightTone.info => AppColors.primary,
    InsightTone.warn => const Color(0xFFF2A33C),
  };

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'What this means for you',
      icon: Icons.lightbulb_outline_rounded,
      isDark: isDark,
      child: analytics.insights.isEmpty
          ? Text(
              'Make a few transactions and your activity intelligence will '
              'appear here.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : const Color(0xFF7A728C),
              ),
            )
          : Column(
              children: [
                for (final insight in analytics.insights)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _tone(insight.tone).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            insight.icon,
                            size: 18,
                            color: _tone(insight.tone),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                insight.title,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF241E33),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                insight.body,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: isDark
                                      ? Colors.white54
                                      : const Color(0xFF6E667E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
