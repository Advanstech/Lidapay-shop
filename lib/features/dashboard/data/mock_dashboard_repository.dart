import 'dashboard_models.dart';
import 'dashboard_repository.dart';

class MockDashboardRepository implements DashboardRepository {
  final _latency = const Duration(milliseconds: 700);

  @override
  Future<WalletSummary> getWalletSummary() async {
    await Future<void>.delayed(_latency);
    return const WalletSummary(
      balance: 1842.50,
      currency: 'GHS',
      lidaValueUnits: 125.5,
      lidaPoints: 340,
    );
  }

  @override
  Future<List<Transaction>> getRecentTransactions({int limit = 5}) async {
    await Future<void>.delayed(_latency);
    final now = DateTime.now();
    final all = <Transaction>[
      Transaction(
        id: 't1',
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
        id: 't2',
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
        id: 't3',
        reference: 'ORD-22115',
        type: TransactionType.shopOrder,
        status: TransactionStatus.success,
        amount: 790,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(hours: 9)),
        description: 'Melcom — Samsung Galaxy A05',
      ),
      Transaction(
        id: 't4',
        reference: 'TRX-903901',
        type: TransactionType.lidaValue,
        status: TransactionStatus.success,
        amount: 25,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 1)),
        description: 'Lida Value accepted from Kofi',
      ),
      Transaction(
        id: 't5',
        reference: 'TRX-903812',
        type: TransactionType.airtime,
        status: TransactionStatus.failed,
        amount: 10,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 1, hours: 4)),
        counterparty: '027 100 3390',
        description: 'AT airtime — provider timeout',
      ),
      Transaction(
        id: 't6',
        reference: 'TOP-4471',
        type: TransactionType.walletTopUp,
        status: TransactionStatus.success,
        amount: 500,
        currency: 'GHS',
        createdAt: now.subtract(const Duration(days: 2)),
        description: 'MoMo top up — MTN',
      ),
    ];
    return all.take(limit).toList();
  }

  @override
  Future<List<FlashDeal>> getFlashDeals() async {
    await Future<void>.delayed(_latency);
    final now = DateTime.now();
    return [
      FlashDeal(
        id: 'd1',
        partnerName: 'Melcom Ghana',
        title: 'Samsung Galaxy A05 — 128GB',
        imageUrl: 'https://picsum.photos/seed/lida-a05/600/400',
        originalPrice: 850,
        dealPrice: 790,
        currency: 'GHS',
        endsAt: now.add(const Duration(hours: 2, minutes: 14, seconds: 9)),
        productId: 'prod_a05',
      ),
      FlashDeal(
        id: 'd2',
        partnerName: 'Melcom Ghana',
        title: 'Oraimo FreePods 4',
        imageUrl: 'https://picsum.photos/seed/lida-pods/600/400',
        originalPrice: 320,
        dealPrice: 259,
        currency: 'GHS',
        endsAt: now.add(const Duration(hours: 19, minutes: 45)),
        productId: 'prod_pods4',
      ),
      FlashDeal(
        id: 'd3',
        partnerName: 'Lidapay Shop',
        title: '10GB Telecel bundle voucher',
        imageUrl: 'https://picsum.photos/seed/lida-data/600/400',
        originalPrice: 60,
        dealPrice: 49,
        currency: 'GHS',
        endsAt: now.add(const Duration(minutes: 40)),
        productId: 'prod_10gb',
      ),
    ];
  }
}
