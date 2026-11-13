import '../../dashboard/data/dashboard_models.dart';
import 'history_models.dart';
import 'history_repository.dart';

class MockHistoryRepository implements HistoryRepository {
  final _latency = const Duration(milliseconds: 700);

  List<Transaction> get _all {
    final now = DateTime.now();
    return <Transaction>[
      Transaction(
        id: 'h01',
        reference: 'TRX-904112',
        type: TransactionType.airtime,
        status: TransactionStatus.success,
        amount: 50,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(minutes: 22)),
        counterparty: '0244 588 584',
        description: 'MTN airtime to Ama',
      ),
      Transaction(
        id: 'h02',
        reference: 'TRX-904087',
        type: TransactionType.data,
        status: TransactionStatus.pending,
        amount: 99,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(hours: 3)),
        counterparty: '020 811 4422',
        description: 'Telecel 5GB bundle',
      ),
      Transaction(
        id: 'h03',
        reference: 'ORD-22115',
        type: TransactionType.shopOrder,
        status: TransactionStatus.success,
        amount: 790,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(hours: 9)),
        description: 'Melcom — Samsung Galaxy A05',
      ),
      Transaction(
        id: 'h04',
        reference: 'TRX-903901',
        type: TransactionType.lidaValue,
        status: TransactionStatus.success,
        amount: 25,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 1)),
        description: 'Lida Value accepted from Kofi',
      ),
      Transaction(
        id: 'h05',
        reference: 'TOP-4471',
        type: TransactionType.walletTopUp,
        status: TransactionStatus.success,
        amount: 500,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 2)),
        description: 'MoMo top up — MTN',
      ),
      Transaction(
        id: 'h06',
        reference: 'TRX-903812',
        type: TransactionType.airtime,
        status: TransactionStatus.failed,
        amount: 10,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 2, hours: 6)),
        counterparty: '027 100 3390',
        description: 'AT airtime — provider timeout',
      ),
      Transaction(
        id: 'h07',
        reference: 'ORD-22098',
        type: TransactionType.shopOrder,
        status: TransactionStatus.success,
        amount: 259,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 3)),
        description: 'Lidapay Shop — PulseBuds 4',
      ),
      Transaction(
        id: 'h08',
        reference: 'TRX-903655',
        type: TransactionType.data,
        status: TransactionStatus.success,
        amount: 49,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 4)),
        counterparty: '0244 588 584',
        description: 'Telecel 10GB bundle',
      ),
      Transaction(
        id: 'h09',
        reference: 'LV-77812',
        type: TransactionType.lidaValue,
        status: TransactionStatus.success,
        amount: 40,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 5)),
        description: 'Lida Value sent to Efua',
      ),
      Transaction(
        id: 'h10',
        reference: 'TRX-903501',
        type: TransactionType.airtime,
        status: TransactionStatus.success,
        amount: 20,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 6)),
        counterparty: '055 210 8890',
        description: 'Telecel airtime — Kwame',
      ),
      Transaction(
        id: 'h11',
        reference: 'TOP-4402',
        type: TransactionType.walletTopUp,
        status: TransactionStatus.success,
        amount: 1000,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 7)),
        description: 'MoMo top up — Telecel',
      ),
      Transaction(
        id: 'h12',
        reference: 'ORD-22041',
        type: TransactionType.shopOrder,
        status: TransactionStatus.pending,
        amount: 640,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 8)),
        description: 'Lidapay Shop — Family Market Bundle',
      ),
      Transaction(
        id: 'h13',
        reference: 'TRX-903301',
        type: TransactionType.data,
        status: TransactionStatus.failed,
        amount: 12,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 9)),
        counterparty: '0244 588 584',
        description: 'MTN 1GB bundle — reversed',
      ),
      Transaction(
        id: 'h14',
        reference: 'TRX-903244',
        type: TransactionType.airtime,
        status: TransactionStatus.success,
        amount: 100,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 10)),
        counterparty: '020 811 4422',
        description: 'AT airtime — office line',
      ),
      Transaction(
        id: 'h15',
        reference: 'LV-77501',
        type: TransactionType.lidaValue,
        status: TransactionStatus.failed,
        amount: 60,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 11)),
        description: 'Lida Value send failed — retry',
      ),
      Transaction(
        id: 'h16',
        reference: 'TRX-903101',
        type: TransactionType.data,
        status: TransactionStatus.success,
        amount: 145,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 12)),
        counterparty: '055 210 8890',
        description: 'Telecel 15GB bundle',
      ),
      Transaction(
        id: 'h17',
        reference: 'TOP-4355',
        type: TransactionType.walletTopUp,
        status: TransactionStatus.success,
        amount: 250,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 13)),
        description: 'MoMo top up — AT',
      ),
      Transaction(
        id: 'h18',
        reference: 'ORD-21990',
        type: TransactionType.shopOrder,
        status: TransactionStatus.success,
        amount: 285,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 15)),
        description: 'Lidapay Shop — GlowUp Skincare Trio',
      ),
      Transaction(
        id: 'h19',
        reference: 'TRX-902877',
        type: TransactionType.airtime,
        status: TransactionStatus.success,
        amount: 5,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 17)),
        counterparty: '0244 588 584',
        description: 'MTN airtime — self',
      ),
      Transaction(
        id: 'h20',
        reference: 'TRX-902800',
        type: TransactionType.data,
        status: TransactionStatus.success,
        amount: 65,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 19)),
        counterparty: '020 811 4422',
        description: 'AT 8GB bundle',
      ),
      Transaction(
        id: 'h21',
        reference: 'LV-77102',
        type: TransactionType.lidaValue,
        status: TransactionStatus.success,
        amount: 15,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 20)),
        description: 'Lida Value accepted from Yaw',
      ),
      Transaction(
        id: 'h22',
        reference: 'TRX-902655',
        type: TransactionType.airtime,
        status: TransactionStatus.success,
        amount: 30,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 21)),
        counterparty: '027 100 3390',
        description: 'AT airtime — Mama',
      ),
    ];
  }

  @override
  Future<List<Transaction>> getTransactions({
    int page = 1,
    int pageSize = 10,
    HistoryFilter? filter,
  }) async {
    await Future<void>.delayed(_latency);
    var result = _all;
    if (filter != null && filter.isActive) {
      result = result.where(filter.matches).toList();
    }
    final start = (page - 1) * pageSize;
    if (start >= result.length) return const [];
    final end = start + pageSize > result.length
        ? result.length
        : start + pageSize;
    return result.sublist(start, end);
  }

  @override
  Future<List<TransactionStat>> getStats() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final buckets = <(TransactionType, TransactionStatus), List<Transaction>>{};
    for (final t in _all) {
      buckets.putIfAbsent((t.type, t.status), () => []).add(t);
    }
    return buckets.entries
        .map(
          (e) => TransactionStat(
            type: e.key.$1,
            status: e.key.$2,
            count: e.value.length,
            totalAmount: e.value.fold(0.0, (s, t) => s + t.amount),
            avgAmount:
                e.value.fold(0.0, (s, t) => s + t.amount) / e.value.length,
            minAmount: e.value
                .map((t) => t.amount)
                .reduce((a, b) => a < b ? a : b),
            maxAmount: e.value
                .map((t) => t.amount)
                .reduce((a, b) => a > b ? a : b),
          ),
        )
        .toList();
  }

  @override
  Future<List<Transaction>> getByDateRange({
    required DateTime start,
    required DateTime end,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return _all
        .where((t) => !t.createdAt.isBefore(start) && !t.createdAt.isAfter(end))
        .toList();
  }
}
