import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_payload.dart';
import '../../dashboard/data/dashboard_models.dart';

/// Advanced filter for the activity ledger. Applied client-side over the
/// merged feed so Lida Value, points and shop rows stay in scope; the
/// ledger endpoints only expose a date-range query server-side.
class HistoryFilter extends Equatable {
  const HistoryFilter({
    this.types = const {},
    this.statuses = const {},
    this.direction = HistoryDirection.all,
    this.range,
    this.minAmount,
    this.maxAmount,
  });

  /// Empty = every type.
  final Set<TransactionType> types;

  /// Empty = every status.
  final Set<TransactionStatus> statuses;
  final HistoryDirection direction;
  final DateTimeRange? range;
  final double? minAmount;
  final double? maxAmount;

  bool get isActive =>
      types.isNotEmpty ||
      statuses.isNotEmpty ||
      direction != HistoryDirection.all ||
      range != null ||
      minAmount != null ||
      maxAmount != null;

  bool matches(Transaction t) {
    if (types.isNotEmpty && !types.contains(t.type)) return false;
    if (statuses.isNotEmpty && !statuses.contains(t.status)) return false;
    if (direction == HistoryDirection.moneyIn && !t.isMoneyIn) return false;
    if (direction == HistoryDirection.moneyOut && t.isMoneyIn) return false;
    final r = range;
    if (r != null) {
      // Day-granularity comparison — pickers return midnight boundaries but
      // presets may carry a 23:59 end; either way the end day is inclusive.
      final local = t.createdAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      final startDay = DateTime(r.start.year, r.start.month, r.start.day);
      final endDay = DateTime(r.end.year, r.end.month, r.end.day);
      if (day.isBefore(startDay) || day.isAfter(endDay)) return false;
    }
    if (minAmount != null && t.amount < minAmount!) return false;
    if (maxAmount != null && t.amount > maxAmount!) return false;
    return true;
  }

  HistoryFilter copyWith({
    Set<TransactionType>? types,
    Set<TransactionStatus>? statuses,
    HistoryDirection? direction,
    DateTimeRange? range,
    double? minAmount,
    double? maxAmount,
    bool clearRange = false,
    bool clearAmount = false,
  }) {
    return HistoryFilter(
      types: types ?? this.types,
      statuses: statuses ?? this.statuses,
      direction: direction ?? this.direction,
      range: clearRange ? null : (range ?? this.range),
      minAmount: clearAmount ? null : (minAmount ?? this.minAmount),
      maxAmount: clearAmount ? null : (maxAmount ?? this.maxAmount),
    );
  }

  /// Preserves the quick-chip behavior: a single-type filter.
  static HistoryFilter onlyType(TransactionType? type) =>
      HistoryFilter(types: type == null ? const {} : {type});

  @override
  List<Object?> get props => [
    types,
    statuses,
    direction,
    range,
    minAmount,
    maxAmount,
  ];
}

enum HistoryDirection { all, moneyIn, moneyOut }

/// One bucket from `GET /api/v1/transactions/stats/{userId}` — the server
/// groups rows by `{transType, status}` and aggregates count/total/avg/
/// min/max amounts.
class TransactionStat extends Equatable {
  const TransactionStat({
    required this.type,
    required this.status,
    required this.count,
    required this.totalAmount,
    required this.avgAmount,
    required this.minAmount,
    required this.maxAmount,
  });

  final TransactionType type;
  final TransactionStatus status;
  final int count;
  final double totalAmount;
  final double avgAmount;
  final double minAmount;
  final double maxAmount;

  factory TransactionStat.fromJson(Map<String, dynamic> json) {
    final pool = payloadPool(json);
    // The group key arrives nested under `_id: {transType, status}` but
    // flat spellings are also tolerated.
    final idGroup = json['_id'] is Map
        ? Map<String, dynamic>.from(json['_id'] as Map)
        : const <String, dynamic>{};
    final idPool = payloadPool(idGroup);
    final rawType =
        stringField(idPool, const ['transType', 'type']) ??
        stringField(pool, const ['transType', 'type']) ??
        '';
    final rawStatus =
        stringField(idPool, const ['status', 'state']) ??
        stringField(pool, const ['status', 'state']);
    return TransactionStat(
      type: TransactionType.fromApi(rawType),
      status: TransactionStatus.fromApi(rawStatus),
      count: (numberField(pool, const ['count', 'total', 'n']) ?? 0).round(),
      totalAmount:
          numberField(pool, const ['totalAmount', 'total', 'sum']) ?? 0,
      avgAmount: numberField(pool, const ['avgAmount', 'average']) ?? 0,
      minAmount: numberField(pool, const ['minAmount', 'min']) ?? 0,
      maxAmount: numberField(pool, const ['maxAmount', 'max']) ?? 0,
    );
  }

  @override
  List<Object?> get props => [
    type,
    status,
    count,
    totalAmount,
    avgAmount,
    minAmount,
    maxAmount,
  ];
}

/// One generated insight for the analytics page — icon + tone + copy.
class TransactionInsight extends Equatable {
  const TransactionInsight({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final InsightTone tone;
  final String title;
  final String body;

  @override
  List<Object?> get props => [icon, tone, title, body];
}

enum InsightTone { good, info, warn }

/// Aggregated view of the ledger for the analytics page. Built entirely
/// from the merged [Transaction] list plus optional server stat buckets,
/// so every chart degrades gracefully when a source is missing.
class HistoryAnalytics extends Equatable {
  const HistoryAnalytics({
    required this.transactions,
    required this.stats,
    required this.dailyOut,
    required this.dailyIn,
    required this.categoryTotals,
    required this.categoryCounts,
    required this.outcomes,
    required this.failureReasons,
    required this.topCounterparties,
    required this.moneyIn,
    required this.moneyOut,
    required this.successRate,
    required this.insights,
    required this.weekdayCounts,
  });

  final List<Transaction> transactions;
  final List<TransactionStat> stats;

  /// Daily totals for the curve — index-aligned, oldest first.
  final List<double> dailyOut;
  final List<double> dailyIn;

  /// Type → total money-out (GHS rows only).
  final Map<TransactionType, double> categoryTotals;

  /// Type → row count (all statuses).
  final Map<TransactionType, int> categoryCounts;

  /// Status → count.
  final Map<TransactionStatus, int> outcomes;

  /// Normalized failure-reason → count, most common first.
  final List<MapEntry<String, int>> failureReasons;

  /// Counterparty → count, most frequent first.
  final List<MapEntry<String, int>> topCounterparties;

  final double moneyIn;
  final double moneyOut;

  /// 0..1 fraction of terminal transactions that succeeded.
  final double successRate;

  /// Transaction counts Monday → Sunday, for the activity bar chart.
  final List<int> weekdayCounts;

  final List<TransactionInsight> insights;

  static HistoryAnalytics build(
    List<Transaction> transactions,
    List<TransactionStat> stats, {
    int days = 30,
  }) {
    double moneyIn = 0;
    double moneyOut = 0;
    final outcomes = <TransactionStatus, int>{};
    final categoryTotals = <TransactionType, double>{};
    final categoryCounts = <TransactionType, int>{};
    final reasons = <String, int>{};
    final counterparties = <String, int>{};
    final weekdayCounts = List<int>.filled(7, 0);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dailyOut = List<double>.filled(days, 0);
    final dailyIn = List<double>.filled(days, 0);

    for (final t in transactions) {
      outcomes[t.status] = (outcomes[t.status] ?? 0) + 1;
      categoryCounts[t.type] = (categoryCounts[t.type] ?? 0) + 1;
      weekdayCounts[t.createdAt.toLocal().weekday - 1] += 1;

      final cp = t.counterparty?.trim();
      if (cp != null && cp.isNotEmpty) {
        counterparties[cp] = (counterparties[cp] ?? 0) + 1;
      }

      if (t.status == TransactionStatus.failed) {
        final reason = _failureReasonOf(t);
        reasons[reason] = (reasons[reason] ?? 0) + 1;
      }

      // Backend currency codes aren't always normalized — rows parsed as
      // 'ghs', 'GHS ' or missing the field must still count toward GHS
      // spend, otherwise every money chart reads zero.
      final isGhs = t.currency.trim().toUpperCase() == 'GHS';
      if (isGhs) {
        if (t.isMoneyIn) {
          moneyIn += t.amount;
        } else {
          moneyOut += t.amount;
          categoryTotals[t.type] = (categoryTotals[t.type] ?? 0) + t.amount;
        }
      }

      final day = DateTime(
        t.createdAt.toLocal().year,
        t.createdAt.toLocal().month,
        t.createdAt.toLocal().day,
      );
      final offset = today.difference(day).inDays;
      if (offset >= 0 && offset < days && isGhs) {
        final slot = days - 1 - offset;
        if (t.isMoneyIn) {
          dailyIn[slot] += t.amount;
        } else {
          dailyOut[slot] += t.amount;
        }
      }
    }

    final succeeded = outcomes[TransactionStatus.success] ?? 0;
    final failed = outcomes[TransactionStatus.failed] ?? 0;
    final pending = outcomes[TransactionStatus.pending] ?? 0;
    final terminal = succeeded + failed;
    final successRate = terminal == 0 ? 1.0 : succeeded / terminal;

    final reasonEntries = reasons.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final cpEntries = counterparties.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return HistoryAnalytics(
      transactions: transactions,
      stats: stats,
      dailyOut: dailyOut,
      dailyIn: dailyIn,
      categoryTotals: categoryTotals,
      categoryCounts: categoryCounts,
      outcomes: outcomes,
      failureReasons: reasonEntries,
      topCounterparties: cpEntries,
      moneyIn: moneyIn,
      moneyOut: moneyOut,
      successRate: successRate,
      weekdayCounts: weekdayCounts,
      insights: _buildInsights(
        transactions: transactions,
        successRate: successRate,
        succeeded: succeeded,
        failed: failed,
        pending: pending,
        categoryTotals: categoryTotals,
        reasonEntries: reasonEntries,
        cpEntries: cpEntries,
        weekdayCounts: weekdayCounts,
        moneyOut: moneyOut,
      ),
    );
  }

  /// Server stat buckets rarely carry a reason string; the row-level
  /// status detail (parsed from failedReason/reason/errorMessage fields)
  /// is the primary source, with the description as fallback.
  static String _failureReasonOf(Transaction t) {
    final detail = t.statusDetail?.trim();
    if (detail != null && detail.isNotEmpty) return detail;
    final desc = t.description.trim();
    // Descriptions like "AT airtime — provider timeout" carry the reason
    // after the dash; otherwise the whole line is the closest we have.
    final dash = desc.lastIndexOf('—');
    if (dash != -1 && dash + 1 < desc.length) {
      return desc.substring(dash + 1).trim();
    }
    return desc.isNotEmpty ? desc : 'Reason not provided';
  }

  static List<TransactionInsight> _buildInsights({
    required List<Transaction> transactions,
    required double successRate,
    required int succeeded,
    required int failed,
    required int pending,
    required Map<TransactionType, double> categoryTotals,
    required List<MapEntry<String, int>> reasonEntries,
    required List<MapEntry<String, int>> cpEntries,
    required List<int> weekdayCounts,
    required double moneyOut,
  }) {
    final insights = <TransactionInsight>[];
    if (transactions.isEmpty) return insights;

    // 1. Success-rate verdict.
    if (successRate >= 0.95) {
      insights.add(
        const TransactionInsight(
          icon: Icons.verified_rounded,
          tone: InsightTone.good,
          title: 'Excellent delivery rate',
          body:
              'Almost every top-up is landing. Keep funding the wallet ahead '
              'of big purchases to stay this smooth.',
        ),
      );
    } else if (successRate >= 0.8) {
      insights.add(
        TransactionInsight(
          icon: Icons.thumb_up_alt_rounded,
          tone: InsightTone.info,
          title: 'Solid success rate',
          body:
              '${(successRate * 100).round()}% of completed transactions '
              'delivered. The failures below show what to watch.',
        ),
      );
    } else {
      insights.add(
        TransactionInsight(
          icon: Icons.warning_amber_rounded,
          tone: InsightTone.warn,
          title: 'Deliveries need attention',
          body:
              'Only ${(successRate * 100).round()}% of completed transactions '
              'succeeded. Check the top failure reasons before retrying.',
        ),
      );
    }

    // 2. Dominant failure reason → actionable guidance.
    if (reasonEntries.isNotEmpty) {
      final top = reasonEntries.first;
      insights.add(
        TransactionInsight(
          icon: Icons.troubleshoot_rounded,
          tone: InsightTone.warn,
          title: 'Top failure reason',
          body:
              '"${top.key}" appears on ${top.value} failed transaction'
              '${top.value == 1 ? '' : 's'}. ${_failureAdvice(top.key)}',
        ),
      );
    }

    // 3. Pending backlog.
    if (pending > 0) {
      insights.add(
        TransactionInsight(
          icon: Icons.hourglass_top_rounded,
          tone: InsightTone.info,
          title: '$pending still in flight',
          body:
              'These include top-ups waiting on a recipient choice. '
              'Unanswered requests settle to the recipient\'s Lida Value '
              'automatically.',
        ),
      );
    }

    // 4. Spend concentration.
    if (categoryTotals.isNotEmpty && moneyOut > 0) {
      final topCat = categoryTotals.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      final share = (topCat.value / moneyOut * 100).round();
      insights.add(
        TransactionInsight(
          icon: _typeIcon(topCat.key),
          tone: InsightTone.info,
          title: '${topCat.key.label} leads your spend',
          body:
              '$share% of your money-out goes to '
              '${topCat.key.label.toLowerCase()}.',
        ),
      );
    }

    // 5. Favorite counterparty.
    if (cpEntries.isNotEmpty && cpEntries.first.value >= 2) {
      final top = cpEntries.first;
      insights.add(
        TransactionInsight(
          icon: Icons.person_pin_circle_rounded,
          tone: InsightTone.info,
          title: 'Frequent recipient',
          body:
              'You transact with ${top.key} most often (${top.value} times). '
              'Double-check the number before each send.',
        ),
      );
    }

    // 6. Peak activity weekday.
    final peakIdx = weekdayCounts.indexOf(
      weekdayCounts.reduce((a, b) => a >= b ? a : b),
    );
    if (weekdayCounts[peakIdx] > 0) {
      const names = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      insights.add(
        TransactionInsight(
          icon: Icons.calendar_month_rounded,
          tone: InsightTone.info,
          title: '${names[peakIdx]} is your busiest day',
          body:
              'Most of your activity lands on ${names[peakIdx]}s — plan '
              'wallet top-ups ahead of it.',
        ),
      );
    }

    return insights;
  }

  static IconData _typeIcon(TransactionType type) => switch (type) {
    TransactionType.airtime => Icons.phone_iphone_rounded,
    TransactionType.data => Icons.wifi_rounded,
    TransactionType.shopOrder => Icons.shopping_bag_rounded,
    TransactionType.lidaValue => Icons.diamond_rounded,
    TransactionType.walletTopUp => Icons.account_balance_wallet_rounded,
    TransactionType.other => Icons.receipt_long_rounded,
  };

  static String _failureAdvice(String reason) {
    final r = reason.toLowerCase();
    if (r.contains('insufficient') || r.contains('balance')) {
      return 'Fund your wallet first, then retry.';
    }
    if (r.contains('timeout') || r.contains('timed out')) {
      return 'Provider timeouts usually resolve on a retry — verify the '
          'payment first, then redeliver from the pending record.';
    }
    if (r.contains('network') ||
        r.contains('operator') ||
        r.contains('provider')) {
      return 'Confirm the destination network/operator before retrying.';
    }
    if (r.contains('expired') || r.contains('decision')) {
      return 'The recipient missed the response window — resend when '
          'they\'re available.';
    }
    if (r.contains('reject') || r.contains('declin') || r.contains('invalid')) {
      return 'Recheck the destination details — the provider refused '
          'the request.';
    }
    return 'Open the transaction for the full status before retrying.';
  }

  @override
  List<Object?> get props => [transactions, stats, moneyIn, moneyOut];
}
