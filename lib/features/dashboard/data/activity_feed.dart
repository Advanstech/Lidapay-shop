import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_payload.dart';
import 'dashboard_models.dart';

/// Aggregates every activity source into one feed: the main transaction
/// ledger (airtime, data, MoMo, top-ups), the Lida Value wallet history,
/// shop orders and Lida Points activity. Each source fails independently so
/// a dead endpoint never blanks the feed; duplicates are removed by
/// reference and the result is sorted newest-first.
class ActivityFeed {
  ActivityFeed(this._api, this._userId);

  final ApiClient _api;
  final String _userId;

  Future<List<Transaction>> fetch({int ledgerLimit = 50}) async {
    final results = await Future.wait<List<Transaction>>([
      _ledger(ledgerLimit),
      _accountActivity(),
      _lidaValue(),
      _shopOrders(),
      _points(),
    ]);
    final seen = <String>{};
    final merged = <Transaction>[];
    for (final list in results) {
      for (final t in list) {
        final key = t.reference.isNotEmpty
            ? 'ref:${t.reference}'
            : 'id:${t.id.isNotEmpty ? t.id : t.createdAt.microsecondsSinceEpoch}';
        if (seen.add(key)) merged.add(t);
      }
    }
    merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged;
  }

  /// GET /api/v1/transactions/user/{userId} — the primary ledger.
  Future<List<Transaction>> _ledger(int limit) async {
    final id = _userId.trim();
    if (id.isEmpty || id == 'undefined' || id == 'null') return const [];
    try {
      final raw = await _api.getRaw(
        ApiEndpoints.userTransactions(id),
        queryParameters: {'page': 1, 'limit': limit},
      );
      final rows = _extractListRows(
        raw,
        const ['transactions', 'data', 'items', 'results', 'records'],
      );
      return rows.map(Transaction.fromApiJson).toList();
    } catch (_) {
      return const [];
    }
  }

  /// GET /api/v1/users/account — the account document embeds its own
  /// transaction list ({id, amount, date, type: DEPOSIT|…}) which covers
  /// wallet deposits/withdrawals the shared ledger may miss.
  Future<List<Transaction>> _accountActivity() async {
    try {
      final raw = await _api.getRaw(ApiEndpoints.userAccount);
      final rows = _extractListRows(raw, const ['transactions']);
      if (rows.isEmpty) return const [];
      return rows.map((map) {
        final pool = payloadPool(map);
        final rawType =
            stringField(pool, const [
              'type',
              'transType',
              'kind',
              'entryType',
            ]) ??
            '';
        final upper = rawType.toUpperCase();
        final isCredit =
            upper.contains('DEPOSIT') ||
            upper.contains('CREDIT') ||
            upper.contains('TOPUP') ||
            upper == 'IN';
        final date =
            dateField(pool, const [
              'initiatedAt',
              'date',
              'createdAt',
              'timestamp',
              'created_at',
            ]) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return Transaction(
          id:
              stringField(pool, const ['_id', 'id', 'transId']) ??
              'acct-${date.microsecondsSinceEpoch}',
          reference:
              stringField(pool, const [
                'reference',
                'ref',
                'transRef',
                '_id',
                'id',
              ]) ??
              '',
          type:
              upper.contains('DEPOSIT') ||
                  upper.contains('WITHDRAW') ||
                  upper.contains('TOPUP') ||
                  upper.contains('TOP_UP')
              ? TransactionType.walletTopUp
              : TransactionType.fromApi(rawType),
          status: TransactionStatus.fromApi(
            stringField(pool, const ['status', 'state']) ?? 'completed',
          ),
          amount:
              numberField(pool, const [
                'amount',
                'transAmount',
                'value',
                'total',
              ]) ??
              0,
          currency:
              stringField(pool, const ['currency', 'currencyCode']) ?? 'GHS',
          createdAt: date,
          description: _pretty(rawType.isEmpty ? 'Wallet activity' : rawType),
          isCredit: isCredit,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Extracts a list of map rows from either a top-level List or a named
  /// list field inside a response Map, avoiding wrapping bare metadata objects.
  static List<Map<String, dynamic>> _extractListRows(
    Object? raw,
    List<String> keys,
  ) {
    if (raw is List) return rowsOf(raw);
    if (raw is Map) {
      final pool = payloadPool(asMap(raw));
      for (final key in keys) {
        final value = pool[key];
        if (value is List) return rowsOf(value);
      }
    }
    return const [];
  }

  /// GET /api/v1/lida-value/history — wallet actions that may never reach
  /// the shared ledger (use/send/sell/convert, value received).
  Future<List<Transaction>> _lidaValue() async {
    try {
      final raw = await _api.getRaw(
        ApiEndpoints.lidaValueHistory,
        queryParameters: {
          'limit': 50,
          'page': 1,
          if (_userId.trim().isNotEmpty) 'userId': _userId.trim(),
        },
      );
      return rowsOf(raw)
          .map((row) => _rewardRow(row, TransactionType.lidaValue, 'LV'))
          .whereType<Transaction>()
          .toList();
    } on ApiException {
      return const [];
    }
  }

  /// GET /api/v1/lidapoints/history — points earned/redeemed.
  Future<List<Transaction>> _points() async {
    try {
      final raw = await _api.getRaw(
        ApiEndpoints.lidapointsHistory,
        queryParameters: {
          'limit': 50,
          'page': 1,
          if (_userId.trim().isNotEmpty) 'userId': _userId.trim(),
        },
      );
      return rowsOf(raw)
          .map(
            (row) => _rewardRow(
              row,
              TransactionType.other,
              'PTS',
              fallbackTitle: 'Lida Points',
            ),
          )
          .whereType<Transaction>()
          .toList();
    } on ApiException {
      return const [];
    }
  }

  /// GET /api/v1/shop/orders — shop checkouts placed through the app.
  Future<List<Transaction>> _shopOrders() async {
    try {
      final raw = await _api.getRaw(
        ApiEndpoints.shopOrders,
        queryParameters: const {'limit': 50, 'page': 1},
      );
      return rowsOf(raw)
          .map((row) {
            final pool = payloadPool(row);
            final reference = stringField(pool, const [
              'orderNumber',
              'orderRef',
              'reference',
              'transId',
              'ref',
              '_id',
              'id',
            ]);
            if (reference == null) return null;
            final itemName = stringField(pool, const [
              'productName',
              'title',
              'name',
            ]);
            return Transaction(
              id: stringField(pool, const ['_id', 'id']) ?? reference,
              reference: reference,
              type: TransactionType.shopOrder,
              status: TransactionStatus.fromApi(
                stringField(pool, const ['status', 'orderStatus', 'state']),
              ),
              amount:
                  numberField(pool, const [
                    'total',
                    'grandTotal',
                    'totalAmount',
                    'amount',
                    'paidAmount',
                  ]) ??
                  0,
              currency:
                  stringField(pool, const ['currency', 'currencyCode']) ??
                  'GHS',
              createdAt:
                  _dateOf(pool) ?? DateTime.fromMillisecondsSinceEpoch(0),
              counterparty:
                  stringField(pool, const ['merchant', 'vendor', 'seller']) ??
                  'Lidapay Shop',
              description: itemName ?? 'Shop order · $reference',
              isCredit: false,
            );
          })
          .whereType<Transaction>()
          .toList();
    } on ApiException {
      return const [];
    }
  }

  /// Shared mapper for the Lida Value / Lida Points history rows — both
  /// endpoints return loosely shaped action logs.
  Transaction? _rewardRow(
    Map<String, dynamic> row,
    TransactionType type,
    String unit, {
    String? fallbackTitle,
  }) {
    final pool = payloadPool(row);
    final reference = stringField(pool, const [
      'transactionReference',
      'transId',
      'trxn',
      'reference',
      'ref',
      'transRef',
      '_id',
      'id',
    ]);
    if (reference == null) return null;
    final rawTitle =
        stringField(pool, const [
          'type',
          'transactionType',
          'action',
          'title',
          'category',
        ]) ??
        fallbackTitle ??
        type.label;
    final message =
        stringField(pool, const [
          'description',
          'message',
          'remarks',
          'narration',
        ]) ??
        '';
    final isCredit = switch (stringField(pool, const [
      'direction',
      'entryType',
    ])?.toLowerCase()) {
      'credit' || 'accrual' => true,
      'debit' || 'redemption' => false,
      _ => _looksLikeCredit('$rawTitle $message'),
    };
    return Transaction(
      id: stringField(pool, const ['_id', 'id']) ?? reference,
      reference: reference,
      type: type,
      // Points/LV ledger lines only exist once settled — the backend only
      // marks *truly* pending rows with an explicit status field, so an
      // absent one means success, not "pending forever".
      status: switch (stringField(pool, const ['status', 'state'])) {
        null => TransactionStatus.success,
        final raw => TransactionStatus.fromApi(raw),
      },
      amount:
          numberField(pool, [
            if (unit == 'PTS') 'points',
            'amount',
            'valueUnits',
            'points',
            'total',
            'value',
          ]) ??
          0,
      currency: unit,
      createdAt: _dateOf(pool) ?? DateTime.fromMillisecondsSinceEpoch(0),
      counterparty: stringField(pool, const [
        'recipient',
        'recipientPhone',
        'receiver',
        'sender',
        'destination',
      ]),
      description: message.isNotEmpty
          ? '${_pretty(rawTitle)} — $message'
          : _pretty(rawTitle),
      isCredit: isCredit,
    );
  }

  /// SAVE/ACCEPT/EARN/RECEIVE-style actions move units into the wallet;
  /// everything else (use/send/sell/convert/redeem) is a debit.
  static bool _looksLikeCredit(String text) {
    final upper = text.toUpperCase();
    return upper.contains('SAVE') ||
        upper.contains('ACCEPT') ||
        upper.contains('CREDIT') ||
        upper.contains('EARN') ||
        upper.contains('RECEIV') ||
        upper.contains('REFUND') ||
        upper.contains('BONUS') ||
        upper.contains('CASHBACK');
  }

  static String _pretty(String raw) {
    return raw
        .split(RegExp(r'[_\s]+'))
        .where((p) => p.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  static DateTime? _dateOf(Map<String, dynamic> pool) => dateField(pool, const [
    'initiatedAt',
    'createdAt',
    'date',
    'timestamp',
    'transDate',
    'updatedAt',
    'created_at',
  ]);
}
