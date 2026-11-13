import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/features/dashboard/data/dashboard_models.dart';
import 'package:lidapay_app/features/history/data/history_models.dart';

/// Analytics + advanced-filter contract for the activity milestone:
/// server stat parsing, client-side filter matching, aggregation and
/// generated intelligence.
Transaction _tx({
  String id = 't',
  TransactionType type = TransactionType.airtime,
  TransactionStatus status = TransactionStatus.success,
  double amount = 10,
  String currency = 'GHS',
  DateTime? at,
  String? counterparty,
  String description = '',
  bool? credit,
  String? statusDetail,
}) => Transaction(
  id: id,
  reference: id,
  type: type,
  status: status,
  amount: amount,
  currency: currency,
  createdAt: at ?? DateTime.now(),
  counterparty: counterparty,
  description: description,
  isCredit: credit,
  statusDetail: statusDetail,
);

void main() {
  group('HistoryFilter', () {
    test('empty filter matches everything', () {
      const filter = HistoryFilter();
      expect(filter.isActive, isFalse);
      expect(filter.matches(_tx(status: TransactionStatus.failed)), isTrue);
    });

    test('type + status sets narrow the ledger', () {
      const filter = HistoryFilter(
        types: {TransactionType.airtime},
        statuses: {TransactionStatus.failed},
      );
      expect(filter.isActive, isTrue);
      expect(
        filter.matches(
          _tx(type: TransactionType.airtime, status: TransactionStatus.failed),
        ),
        isTrue,
      );
      expect(
        filter.matches(
          _tx(type: TransactionType.data, status: TransactionStatus.failed),
        ),
        isFalse,
      );
      expect(
        filter.matches(
          _tx(type: TransactionType.airtime, status: TransactionStatus.success),
        ),
        isFalse,
      );
    });

    test('direction honors the resolved credit flag', () {
      const out = HistoryFilter(direction: HistoryDirection.moneyOut);
      expect(out.matches(_tx(credit: false)), isTrue);
      expect(out.matches(_tx(credit: true)), isFalse);
      const inside = HistoryFilter(direction: HistoryDirection.moneyIn);
      expect(inside.matches(_tx(credit: true)), isTrue);
    });

    test('date range is inclusive of the end day', () {
      final now = DateTime.now();
      final range = DateTimeRange(
        start: DateTime(now.year, now.month, now.day - 3),
        end: DateTime(now.year, now.month, now.day - 1, 23, 59),
      );
      final filter = HistoryFilter(range: range);
      expect(filter.matches(_tx(at: now)), isFalse); // today
      expect(
        filter.matches(_tx(at: now.subtract(const Duration(days: 2)))),
        isTrue,
      );
      // Late on the end day still counts.
      expect(
        filter.matches(
          _tx(at: DateTime(now.year, now.month, now.day - 1, 23, 30)),
        ),
        isTrue,
      );
    });

    test('amount bounds filter correctly', () {
      const filter = HistoryFilter(minAmount: 10, maxAmount: 100);
      expect(filter.matches(_tx(amount: 5)), isFalse);
      expect(filter.matches(_tx(amount: 50)), isTrue);
      expect(filter.matches(_tx(amount: 200)), isFalse);
    });
  });

  group('TransactionStat', () {
    test('parses the grouped server bucket shape', () {
      final stat = TransactionStat.fromJson(const {
        '_id': {'transType': 'AIRTIME', 'status': 'COMPLETED'},
        'count': 12,
        'totalAmount': 250.5,
        'avgAmount': 20.87,
        'minAmount': 5,
        'maxAmount': 60,
      });
      expect(stat.type, TransactionType.airtime);
      expect(stat.status, TransactionStatus.success);
      expect(stat.count, 12);
      expect(stat.totalAmount, 250.5);
      expect(stat.avgAmount, 20.87);
    });

    test('flat spellings and missing group key degrade safely', () {
      final stat = TransactionStat.fromJson(const {
        'transType': 'DATA',
        'status': 'FAILED',
        'count': 2,
        'totalAmount': 30,
      });
      expect(stat.type, TransactionType.data);
      expect(stat.status, TransactionStatus.failed);
      expect(stat.avgAmount, 0);
    });
  });

  group('HistoryAnalytics.build', () {
    test('aggregates totals, outcomes and daily buckets', () {
      final now = DateTime.now();
      final tx = [
        _tx(id: 'a', amount: 50, at: now, credit: false, counterparty: '0244'),
        _tx(
          id: 'b',
          type: TransactionType.walletTopUp,
          amount: 500,
          at: now.subtract(const Duration(days: 1)),
          credit: true,
        ),
        _tx(
          id: 'c',
          type: TransactionType.data,
          status: TransactionStatus.failed,
          amount: 12,
          at: now.subtract(const Duration(days: 1)),
          credit: false,
          statusDetail: 'Provider timeout',
        ),
        _tx(
          id: 'd',
          type: TransactionType.lidaValue,
          currency: 'LV',
          amount: 40,
          at: now,
          credit: false,
        ),
      ];
      final a = HistoryAnalytics.build(tx, const [], days: 30);
      expect(a.moneyOut, 62); // LV rows excluded from GHS totals
      expect(a.moneyIn, 500);
      expect(a.outcomes[TransactionStatus.success], 3);
      expect(a.outcomes[TransactionStatus.failed], 1);
      expect(a.successRate, closeTo(0.75, 0.001));
      expect(a.categoryTotals[TransactionType.airtime], 50);
      expect(a.dailyOut.last, 50); // today lands in the last bucket
      expect(a.dailyIn.last, 0);
      expect(a.dailyIn[a.dailyIn.length - 2], 500);
      expect(a.failureReasons.single.key, 'Provider timeout');
      expect(a.topCounterparties.first.key, '0244');
    });

    test('fall back to description tail when no statusDetail exists', () {
      final tx = [
        _tx(
          status: TransactionStatus.failed,
          description: 'AT airtime — provider timeout',
        ),
      ];
      final a = HistoryAnalytics.build(tx, const []);
      expect(a.failureReasons.single.key, 'provider timeout');
    });

    test('insights flag a weak delivery rate and pending backlog', () {
      final tx = [
        _tx(status: TransactionStatus.failed, statusDetail: 'X'),
        _tx(status: TransactionStatus.failed, statusDetail: 'X'),
        _tx(status: TransactionStatus.pending),
        _tx(),
      ];
      final a = HistoryAnalytics.build(tx, const []);
      expect(a.successRate, closeTo(1 / 3, 0.01));
      expect(a.insights.any((i) => i.tone == InsightTone.warn), isTrue);
      expect(a.insights.any((i) => i.title.contains('in flight')), isTrue);
    });

    test('a perfect record earns the good-tone insight', () {
      final tx = [_tx(), _tx(id: 'b'), _tx(id: 'c')];
      final a = HistoryAnalytics.build(tx, const []);
      expect(a.successRate, 1.0);
      expect(a.insights.first.tone, InsightTone.good);
    });
  });
}
