import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/core/network/api_client.dart';
import 'package:lidapay_app/core/network/api_exception.dart';
import 'package:lidapay_app/core/network/token_store.dart';
import 'package:lidapay_app/features/auth/data/auth_models.dart';
import 'package:lidapay_app/features/auth/data/remote_auth_repository.dart';
import 'package:lidapay_app/features/dashboard/data/dashboard_models.dart';
import 'package:lidapay_app/features/dashboard/data/remote_dashboard_repository.dart';
import 'package:lidapay_app/features/history/data/remote_history_repository.dart';
import 'package:lidapay_app/features/notifications/data/notification_models.dart';
import 'package:lidapay_app/features/services/data/remote_services_repository.dart';
import 'package:lidapay_app/features/services/data/service_models.dart';
import 'package:lidapay_app/features/shop/data/remote_shop_repository.dart';
import 'package:lidapay_app/features/shop/data/shop_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The live endpoints document request bodies but almost never response
/// bodies, so these tests pin the tolerant parsing against realistic payload
/// variants instead of depending on a running backend.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.respond, {this.status});

  final Object? Function(RequestOptions options) respond;
  final int Function(RequestOptions options)? status;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(respond(options)),
      status?.call(options) ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<(ApiClient, _StubAdapter)> _client(
  Object? Function(RequestOptions options) respond, {
  int Function(RequestOptions options)? status,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final adapter = _StubAdapter(respond, status: status);
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
    ..httpClientAdapter = adapter;
  final refreshDio = Dio(BaseOptions(baseUrl: 'https://api.test'))
    ..httpClientAdapter = adapter;
  return (
    ApiClient(dio: dio, refreshDio: refreshDio, tokenStore: TokenStore(prefs)),
    adapter,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundlelist array parses codes, prices and volumes', () async {
    final (api, adapter) = await _client(
      (_) => [
        {
          'dataCode': 'DATA_1GB',
          'bundleName': 'Starter',
          'price': 12,
          'dataAmount': '1GB',
        },
        {
          'code': 'MTN-5GB',
          'name': 'Everyday',
          'amount': '48',
          'volume': '5GB',
        },
      ],
    );
    final bundles = await RemoteServicesRepository(api)
        .getDataBundles(networkId: '4');

    expect(bundles, hasLength(2));
    expect(bundles.first.id, 'DATA_1GB');
    expect(bundles.first.name, 'Starter');
    expect(bundles.first.price, 12);
    expect(bundles.first.dataAmount, '1GB');
    expect(bundles[1].id, 'MTN-5GB');
    expect(bundles[1].price, 48);
    expect(adapter.requests.single.path, '/api/v1/internet/bundlelist');
    expect(adapter.requests.single.data, {'network': 4});
  });

  test(
    'country catalogue keeps dial codes for destination number entry',
    () async {
      final (api, _) = await _client(
        (_) => {
          'countries': [
            {
              'isoName': 'GH',
              'name': 'Ghana',
              'currencyCode': 'GHS',
              'callingCodes': ['+233'],
            },
          ],
        },
      );

      final countries = await RemoteServicesRepository(api).getCountries();

      expect(countries, hasLength(1));
      expect(countries.single.id, 'GH');
      expect(countries.single.meta, 'GHS');
      expect(countries.single.dialCode, '+233');
    },
  );

  test('airtime topup builds a receipt from wrapped response keys', () async {
    final (api, _) = await _client(
      (_) => {
        'success': true,
        'data': {
          'transactionId': 'AIR-9001',
          'status': 'SUBMITTED',
          'amount': 5,
        },
      },
    );
    final receipt = await RemoteServicesRepository(api).buyLocalAirtime(
      recipientNumber: '0241234567',
      amount: 5,
      networkId: '4',
      saveToLidaValue: false,
    );

    expect(receipt.reference, 'AIR-9001');
    expect(receipt.message, contains('SUBMITTED'));
    expect(receipt.amount, 5);
    expect(receipt.title, 'Airtime sent');
  });

  test(
    'global airtime normalises MSISDN and surfaces the pending decision',
    () async {
      final (api, adapter) = await _client((options) {
        if (options.path.contains('phone-lookup')) {
          return {'operatorId': 1234, 'name': 'MTN NG'};
        }
        return {
          'topupOrderId': 'TP-77',
          'decisionId': 'DEC-9',
          'status': 'PENDING',
          'expiresAt': '2026-10-20T10:00:00.000Z',
        };
      });
      final receipt = await RemoteServicesRepository(api).buyGlobalAirtime(
        recipientNumber: '0803 456 7890',
        amount: 20,
        countryCode: 'NG',
        recipientDialCode: '+234',
        currency: 'NGN',
      );

      expect(receipt.reference, 'TP-77');
      expect(receipt.message, contains('recipient now chooses'));
      expect(receipt.message, contains('before'));
      final lookup = adapter.requests.firstWhere(
        (request) => request.path.contains('phone-lookup'),
      );
      expect(lookup.data['phone'], '2348034567890');
      expect(lookup.data['countryCode'], 'NG');
      final recharge = adapter.requests.firstWhere(
        (request) => request.path.contains('recharge'),
      );
      expect(recharge.data['operatorId'], 1234);
      expect(recharge.data['recipientNumber'], '2348034567890');
      expect(recharge.data['recipientCountryCode'], 'NG');
      expect(recharge.data['senderCountryCode'], 'GH');
      expect(recharge.data['enableRecipientChoice'], true);
      expect(recharge.data['isSelfTopup'], false);
    },
  );

  test('global airtime never touches Reloadly lookup for Ghana', () async {
    final (api, adapter) = await _client((_) => {'operatorId': 1});
    expect(
      () => RemoteServicesRepository(api).buyGlobalAirtime(
        recipientNumber: '0241234567',
        amount: 5,
        countryCode: 'GH',
      ),
      throwsA(isA<ApiException>()),
    );
    await pumpEventQueue();
    expect(
      adapter.requests.where((r) => r.path.contains('reload')).toList(),
      isEmpty,
    );
  });

  test('local topup sends Prymo body with self-topup flag', () async {
    final (api, adapter) = await _client(
      (_) => {
        'data': {'transId': 'AIR-1', 'status': 'SUCCESS'},
      },
    );
    await RemoteServicesRepository(
      api,
      userId: 'u-1',
      userName: 'Kofi',
    ).buyLocalAirtime(
      recipientNumber: '0241234567',
      amount: 5,
      networkId: '6',
      saveToLidaValue: false,
      isSelfTopup: true,
    );
    final request = adapter.requests.single;
    expect(request.path, '/api/v1/airtime/topup');
    expect(request.data['network'], 6);
    expect(request.data['isSelfTopup'], true);
    expect(request.data['userId'], 'u-1');
    expect(request.data['userName'], 'Kofi');
    expect(request.data, isNot(contains('operatorId')));
  });

  test('explicit operator id skips the phone lookup', () async {
    final (api, adapter) = await _client(
      (_) => {'transactionId': 'RLD-55', 'status': 'SUCCESS'},
    );
    final receipt = await RemoteServicesRepository(api).buyGlobalAirtime(
      recipientNumber: '8034567890',
      amount: 10,
      countryCode: 'NG',
      operatorId: '341',
      recipientDialCode: '+234',
      senderNumber: '0244588584',
    );
    expect(receipt.reference, 'RLD-55');
    expect(
      adapter.requests.where((r) => r.path.contains('phone-lookup')),
      isEmpty,
    );
    final recharge = adapter.requests.single;
    expect(recharge.path, '/api/v1/reload-airtime/recharge');
    expect(recharge.data['operatorId'], 341);
    expect(recharge.data['senderNumber'], '0244588584');
    expect(recharge.data['recipientNumber'], '2348034567890');
  });

  test('missing operator from lookup fails without recharging', () async {
    final (api, adapter) = await _client((_) => {});
    expect(
      () => RemoteServicesRepository(api).buyGlobalAirtime(
        recipientNumber: '8034567890',
        amount: 10,
        countryCode: 'NG',
        recipientDialCode: '+234',
      ),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('No operator found'),
        ),
      ),
    );
    await pumpEventQueue();
    expect(adapter.requests.where((r) => r.path.contains('recharge')), isEmpty);
  });

  test(
    'international operators parse the Reloadly operator envelope',
    () async {
      final (api, adapter) = await _client(
        (_) => {
          'operators': [
            {
              'operatorId': 341,
              'name': 'MTN Nigeria',
              'country': {'isoName': 'NG'},
              'minAmount': 1,
              'maxAmount': 500,
            },
            {'operatorId': 342, 'name': 'Airtel Nigeria'},
          ],
        },
      );
      final operators = await RemoteServicesRepository(api)
          .getInternationalOperators('NG');
      expect(operators, hasLength(2));
      expect(operators.first.id, '341');
      expect(operators.first.name, 'MTN Nigeria');
      expect(operators.first.meta, contains('1–500'));
      // `network-operators` with `countryIsoCode` is the documented discovery
      // route for a destination — it leads the fallback chain.
      final request = adapter.requests.single;
      expect(request.path, '/api/v1/reloadly/network-operators');
      expect(request.data['countryIsoCode'], 'NG');
      expect(request.data['includeData'], isTrue);
    },
  );

  test(
    'operator discovery falls back to the next route when one fails',
    () async {
      final (api, adapter) = await _client(
        (options) => {
          'operators': [
            {'operatorId': 341, 'name': 'MTN Nigeria'},
          ],
        },
        status: (options) =>
            options.path.contains('network-operators') ? 500 : 200,
      );
      final operators = await RemoteServicesRepository(api)
          .getInternationalOperators('NG');

      expect(operators.single.name, 'MTN Nigeria');
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.first.path, '/api/v1/reloadly/network-operators');
      expect(
        adapter.requests.last.path,
        '/api/v1/reloadly/get-operator-by-code',
      );
    },
  );

  test('a global operator page is narrowed to the selected country', () async {
    final (api, _) = await _client(
      (_) => {
        'content': [
          {
            'operatorId': 341,
            'name': 'MTN Nigeria',
            'country': {'isoName': 'NG'},
          },
          {
            'operatorId': 150,
            'name': 'MTN Ghana',
            'country': {'isoName': 'GH'},
          },
        ],
        'totalPages': 1,
      },
    );
    final operators = await RemoteServicesRepository(api)
        .getInternationalOperators('NG');

    expect(operators.single.name, 'MTN Nigeria');
  });

  test('GH operator request falls back to the Prymo networks', () async {
    final (api, adapter) = await _client((_) => {});
    final operators = await RemoteServicesRepository(api)
        .getInternationalOperators('GH');
    expect(operators.first.name, 'MTN Ghana');
    expect(adapter.requests, isEmpty);
  });

  test('global data auto-detects then posts the reloadly-data body', () async {
    final (api, adapter) = await _client((options) {
      if (options.path.contains('auto-detect')) {
        return {'operatorId': 341, 'name': 'MTN Nigeria'};
      }
      return {'transactionId': 'DAT-9', 'status': 'SUCCESS'};
    });
    final receipt =
        await RemoteServicesRepository(
          api,
          userId: 'u-1',
          userPhone: '0244588584',
        ).buyGlobalDataBundle(
          recipientNumber: '08034567890',
          amount: 20,
          countryCode: 'NG',
          recipientDialCode: '+234',
          currency: 'NGN',
        );

    expect(receipt.reference, 'DAT-9');
    final detect = adapter.requests.firstWhere(
      (r) => r.path.contains('auto-detect'),
    );
    expect(detect.method, 'GET');
    expect(detect.uri.queryParameters['msisdn'], '2348034567890');
    expect(detect.uri.queryParameters['countryCode'], 'NG');
    final buy = adapter.requests.firstWhere((r) => r.path.contains('buy-data'));
    expect(buy.data['operatorId'], 341);
    expect(buy.data['operatorName'], 'MTN Nigeria');
    expect(buy.data['recipientNumber'], '2348034567890');
    expect(buy.data['recipientCountryCode'], 'NG');
    expect(buy.data['senderNumber'], '0244588584');
    expect(buy.data['senderCountryCode'], 'GH');
    expect(buy.data['currency'], 'NGN');
    expect(buy.data['isSelfTopup'], false);
    expect(buy.data['userId'], 'u-1');
  });

  test('global data never touches Reloadly for Ghana', () async {
    final (api, adapter) = await _client((_) => {});
    expect(
      () => RemoteServicesRepository(api).buyGlobalDataBundle(
        recipientNumber: '0241234567',
        amount: 10,
        countryCode: 'GH',
      ),
      throwsA(isA<ApiException>()),
    );
    await pumpEventQueue();
    expect(
      adapter.requests.where((r) => r.path.contains('reloadly-data')),
      isEmpty,
    );
  });

  test('explicit operator skips data auto-detect', () async {
    final (api, adapter) = await _client(
      (_) => {'transId': 'DAT-1', 'status': 'PENDING'},
    );
    await RemoteServicesRepository(api).buyGlobalDataBundle(
      recipientNumber: '8034567890',
      amount: 15,
      countryCode: 'NG',
      operatorId: '344',
      recipientDialCode: '+234',
    );
    expect(
      adapter.requests.where((r) => r.path.contains('auto-detect')),
      isEmpty,
    );
    expect(adapter.requests.single.path, '/api/v1/reloadly-data/buy-data');
    expect(adapter.requests.single.data['operatorId'], 344);
  });

  test('data operator list posts the country filter', () async {
    final (api, adapter) = await _client(
      (_) => {
        'operators': [
          {'operatorId': 341, 'name': 'MTN Nigeria', 'data': true},
        ],
      },
    );
    final operators = await RemoteServicesRepository(api)
        .getInternationalDataOperators('NG');
    expect(operators.single.id, '341');
    expect(operators.single.name, 'MTN Nigeria');
    final request = adapter.requests.single;
    expect(request.path, '/api/v1/reloadly-data/list-operators');
    expect(request.data['countryCode'], 'NG');
  });

  test('Lida Value balance accepts object keys and history items', () async {
    final (api, _) = await _client((options) {
      if (options.path.contains('balance')) {
        return {'totalValueUnits': 324.5, 'pendingValueUnits': 12};
      }
      return {
        'items': [
          {
            'id': 'LV-1',
            'type': 'Accepted value',
            'description': 'Saved from recipient choice',
            'amount': 25,
            'createdAt': '2026-10-18T09:00:00.000Z',
          },
        ],
      };
    });
    final wallet = await RemoteServicesRepository(api).getLidaValueWallet();

    expect(wallet.balance, 324.5);
    expect(wallet.pending, 12);
    expect(wallet.history, hasLength(1));
    expect(wallet.history.first.reference, 'LV-1');
    expect(wallet.history.first.title, 'Accepted value');
  });

  test('Lida Value history preserves API reference and direction', () async {
    final (api, _) = await _client((options) {
      if (options.path.contains('balance')) return {'totalValueUnits': 10.76};
      return {
        'data': [
          {
            '_id': 'row-1',
            'transactionReference': 'SEND-1792243484595-5bi1zzpwl',
            'direction': 'debit',
            'type': 'save_reversal',
            'valueUnits': 1,
            'unit': 'value',
            'productType': 'mixed',
            'destinationRegistered': false,
            'createdAt': '2026-10-17T13:24:44.679Z',
          },
        ],
      };
    });
    final wallet = await RemoteServicesRepository(api).getLidaValueWallet();
    final item = wallet.history.single;
    expect(item.reference, 'SEND-1792243484595-5bi1zzpwl');
    expect(item.amount, 1);
    expect(item.isCredit, isFalse);
    expect(item.createdAt, DateTime.parse('2026-10-17T13:24:44.679Z'));
  });

  test('dashboard and Points page use the same live points balance', () async {
    final (api, adapter) = await _client((options) {
      if (options.path == '/api/v1/lidapoints/balance') return {'balance': 78};
      if (options.path == '/api/v1/users/points') return 15;
      if (options.path == '/api/v1/lidapoints/history') return [];
      if (options.path == '/api/v1/lida-value/balance')
        return {'totalValueUnits': 10.76};
      return {'balance': 0};
    });
    final summary = await RemoteDashboardRepository(
      api,
      'u-1',
    ).getWalletSummary();
    final points = await RemoteServicesRepository(api).getLidaPointsWallet();
    expect(summary.lidaPoints, 78);
    expect(points.balance, 78);
    expect(
      adapter.requests.where((r) => r.path == '/api/v1/users/points'),
      isEmpty,
    );
  });

  test('points history uses points and accrual direction', () async {
    final (api, _) = await _client((options) {
      if (options.path.contains('balance')) return {'balance': 78};
      return {
        'data': [
          {
            '_id': 'points-row',
            'transactionReference': 'TXN-MVCFHWNN-2CE6BEA9',
            'role': 'sender',
            'points': 3,
            'valueUnits': 1,
            'type': 'commission_share',
            'entryType': 'accrual',
            'transType': 'AIRTIME',
            'provider': 'PRYMO',
            'createdAt': '2026-10-17T13:24:44.679Z',
          },
        ],
      };
    });
    final wallet = await RemoteServicesRepository(api).getLidaPointsWallet();
    expect(wallet.history.single.reference, 'TXN-MVCFHWNN-2CE6BEA9');
    expect(wallet.history.single.amount, 3);
    expect(wallet.history.single.isCredit, isTrue);
  });

  test('Lidapoint balance accepts a bare number', () async {
    final (api, _) = await _client((options) {
      if (options.path.contains('balance')) return 18450;
      return [];
    });
    final wallet = await RemoteServicesRepository(api).getLidaPointsWallet();

    expect(wallet.balance, 18450);
    expect(wallet.redeemableValue, 92.25);
    expect(wallet.history, isEmpty);
  });

  test('convert rejects a destination that breaks the spec pattern', () async {
    final (api, adapter) = await _client((_) => {'status': 'QUEUED'});
    final repo = RemoteServicesRepository(api);

    expect(
      () => repo.convertLidaValue(amount: 10, destination: 'mtn-money'),
      throwsA(isA<ApiException>()),
    );
    expect(adapter.requests, isEmpty);

    await repo.convertLidaValue(amount: 10, destination: 'momo:0241234567');
    expect(adapter.requests.single.data['destination'], 'momo:0241234567');
  });

  test('shop products map nested category, images and discounts', () async {
    final (api, _) = await _client(
      (_) => {
        'products': [
          {
            '_id': 'p1',
            'name': 'Galaxy A05',
            'price': 850,
            'compareAtPrice': 900,
            'category': {'_id': 'electronics', 'name': 'Electronics'},
            'images': ['https://cdn.test/p1.jpg'],
            'stock': 14,
            'rating': 4.6,
            'soldCount': 12,
            'featured': true,
            'description': '128GB phone',
          },
        ],
      },
    );
    final products = await RemoteShopRepository(api).getProducts();

    expect(products, hasLength(1));
    final product = products.single;
    expect(product.id, 'p1');
    expect(product.categoryId, 'electronics');
    expect(product.price, 850);
    expect(product.oldPrice, 900);
    expect(product.imageAsset, 'https://cdn.test/p1.jpg');
    expect(product.stock, 14);
    expect(product.rating, 4.6);
    expect(product.sold, 12);
    expect(product.isFeatured, true);
  });

  test('shop discountPrice becomes the selling price per the spec', () async {
    final (api, _) = await _client(
      (_) => {
        'products': [
          {
            '_id': 'p9',
            'name': 'Seasoning 52g',
            'price': 24.0,
            'discountPrice': 21.99,
            'brand': 'Bayara',
            'partnerName': 'Melcom',
            'sku': 'BAY-52G',
            'images': [
              {'url': 'https://cdn.test/a.jpg'},
              'https://cdn.test/b.jpg',
            ],
            'attributes': {'Weight': '52g', 'Flavour': 'Spicy'},
            'stock': 40,
          },
          {'_id': 'p10', 'name': 'Full price item', 'price': 100, 'stock': 5},
        ],
      },
    );
    final products = await RemoteShopRepository(api).getProducts();

    expect(products, hasLength(2));
    final sale = products.first;
    expect(sale.price, 21.99);
    expect(sale.oldPrice, 24.0);
    expect(sale.discountPercent, 8);
    expect(sale.brand, 'Bayara');
    expect(sale.partnerName, 'Melcom');
    expect(sale.sku, 'BAY-52G');
    expect(sale.images, ['https://cdn.test/a.jpg', 'https://cdn.test/b.jpg']);
    expect(sale.attributes['Weight'], '52g');

    final full = products.last;
    expect(full.price, 100);
    expect(full.oldPrice, isNull);
    expect(full.discountPercent, 0);
  });

  test('shop cart totals come from nested line items', () async {
    final (api, _) = await _client(
      (_) => {
        'items': [
          {
            'quantity': 2,
            'product': {'_id': 'p1', 'name': 'Phone', 'price': 850},
          },
          {
            'quantity': 1,
            'product': {'_id': 'p2', 'name': 'Case', 'price': 100},
          },
        ],
      },
    );
    final cart = await RemoteShopRepository(api).getCart();

    expect(cart.items, hasLength(2));
    expect(cart.itemCount, 3);
    expect(cart.subtotal, 1800);
    expect(cart.itemFor('p2')?.quantity, 1);
  });

  test('shop checkout reads the order envelope', () async {
    final (api, adapter) = await _client(
      (_) => {
        'order': {
          '_id': 'o1',
          'orderNumber': 'LPS260912482913',
          'itemCount': 3,
          'totalAmount': 1800,
          'currency': 'GHS',
          'createdAt': '2026-10-19T08:00:00.000Z',
        },
      },
    );
    final order = await RemoteShopRepository(api).checkout(
      shippingAddress: const ShippingAddress(
        fullName: 'Ama Mensah',
        phone: '0244588584',
        addressLine1: '12 Osu Avenue',
        city: 'Accra',
        region: 'Greater Accra',
        country: 'Ghana',
        latitude: 5.6037,
        longitude: -0.187,
      ),
    );

    expect(order.id, 'o1');
    expect(order.reference, 'LPS260912482913');
    expect(order.itemCount, 3);
    expect(order.total, 1800);
    expect(order.currency, 'GHS');

    // The checkout contract requires the delivery-pin coordinates so the
    // backend can compute the courier distance from the branch pickup.
    final sent = adapter.requests.single.data as Map<String, dynamic>;
    final address = sent['shippingAddress'] as Map<String, dynamic>;
    expect(address['latitude'], 5.6037);
    expect(address['longitude'], -0.187);
  });

  test(
    'shop order preserves SKU, partner and discount snapshot fields',
    () async {
      final (api, _) = await _client(
        (_) => {
          'order': {
            '_id': 'o2',
            'orderNumber': 'LPS260912482914',
            'items': [
              {
                'quantity': 2,
                'unitPrice': 69.29,
                'unitListPrice': 76.99,
                'unitDiscountAmount': 7.70,
                'promotionReference': 'MELCOM-PROMO-123',
                'product': {
                  '_id': 'p1',
                  'name': 'Long Mountain Ruby Cabernet 75cl',
                  'sku': '18339',
                  'weight': 0.8,
                  'partner': {'_id': 'partner-1', 'name': 'Melcom Ghana'},
                  'fulfilmentLocation': {'_id': 'melcom-accra-01'},
                },
              },
            ],
          },
        },
      );
      final order = await RemoteShopRepository(api).checkout(
        shippingAddress: const ShippingAddress(
          fullName: 'Ama Mensah',
          phone: '0244588584',
          addressLine1: '12 Osu Avenue',
          city: 'Accra',
          region: 'Greater Accra',
          country: 'Ghana',
        ),
      );

      final item = order.items.single;
      expect(item.productId, 'p1');
      expect(item.sku, '18339');
      expect(item.partnerId, 'partner-1');
      expect(item.partnerName, 'Melcom Ghana');
      expect(item.partnerLocationId, 'melcom-accra-01');
      expect(item.price, 69.29);
      expect(item.listPrice, 76.99);
      expect(item.discountAmount, 7.70);
      expect(item.promotionReference, 'MELCOM-PROMO-123');
      expect(item.quantity, 2);
      expect(item.weightKg, 0.8);
      expect(item.lineTotal, 138.58);
    },
  );

  test(
    'shop cart parses snapshot line items and server summary fields',
    () async {
      final (api, _) = await _client(
        (_) => {
          'items': [
            {
              // Mongoose emits a per-line _id — productId must win as the
              // product key or cart remove/update mutations miss.
              '_id': 'cart-line-1',
              'productId': 'p1',
              'name': 'Long Mountain Ruby Cabernet 75cl',
              'price': 76.99,
              'discountPrice': 69.29,
              'image': ['https://cdn.test/18339.webp'],
              'quantity': 2,
            },
            {
              '_id': 'cart-line-2',
              'productId': 'p2',
              'name': 'Full price item',
              'price': 100,
              'image': 'https://cdn.test/p2.jpg',
              'quantity': 1,
            },
          ],
          'itemCount': 3,
          'subtotal': 253.98,
          'discount': 15.40,
          'total': 238.58,
          'cart': {'_id': 'cart-1'},
        },
      );
      final cart = await RemoteShopRepository(api).getCart();

      expect(cart.items, hasLength(2));
      final wine = cart.items.first;
      expect(wine.product.id, 'p1');
      expect(wine.product.name, 'Long Mountain Ruby Cabernet 75cl');
      // Effective price = discountPrice when > 0.
      expect(wine.product.price, 69.29);
      expect(wine.product.oldPrice, 76.99);
      expect(wine.product.imageAsset, 'https://cdn.test/18339.webp');
      expect(cart.items.last.product.imageAsset, 'https://cdn.test/p2.jpg');

      // Server summary fields win over locally summed line totals.
      expect(cart.itemCount, 3);
      expect(cart.subtotal, 253.98);
      expect(cart.discount, 15.40);
      expect(cart.total, 238.58);
      expect(cart.itemFor('p2')?.quantity, 1);
    },
  );

  test('shop checkout sends address, payment method and redirect', () async {
    final (api, adapter) = await _client(
      (_) => {
        '_id': 'o3',
        'orderNumber': 'LPS260912482915',
        'subtotal': 153.98,
        'discount': 15.40,
        'deliveryFee': 20,
        'total': 158.58,
        'paymentMethod': 'momo',
        'status': 'pending',
        'paymentStatus': 'pending',
        'shippingAddress': {
          'fullName': 'Kofi Mensah',
          'phone': '0241120481',
          'addressLine1': '12 Osu Avenue',
          'city': 'Accra',
          'region': 'Greater Accra',
          'country': 'Ghana',
        },
        'items': [
          {
            'productId': 'p1',
            'name': 'Long Mountain Ruby Cabernet 75cl',
            'sku': '18339',
            'partnerId': 'partner-1',
            'partnerName': 'Melcom Ghana',
            'partnerLocationId': 'MELCOM-ACCRA-01',
            'price': 69.29,
            'listPrice': 76.99,
            'discountAmount': 7.70,
            'quantity': 2,
            'weightKg': 0.8,
            'images': ['https://cdn.test/18339.webp'],
          },
        ],
        'deliveryUpdates': [
          {
            'status': 'order_placed',
            'message': 'Order placed',
            'timestamp': '2026-10-19T08:00:00.000Z',
          },
        ],
      },
    );
    final order = await RemoteShopRepository(api).checkout(
      shippingAddress: const ShippingAddress(
        fullName: 'Kofi Mensah',
        phone: '0241120481',
        addressLine1: '12 Osu Avenue',
        addressLine2: 'Flat 4B',
        city: 'Accra',
        region: 'Greater Accra',
        country: 'Ghana',
        postalCode: 'GA-001',
        deliveryInstructions: 'Call first',
      ),
    );

    final request = adapter.requests.single;
    expect(request.path, '/api/v1/shop/checkout');
    final body = request.data as Map<String, dynamic>;
    expect(body['paymentMethod'], 'momo');
    expect(body['redirectUrl'], 'lidapay://shop/checkout/callback');
    final address = body['shippingAddress'] as Map<String, dynamic>;
    expect(address['fullName'], 'Kofi Mensah');
    expect(address['addressLine1'], '12 Osu Avenue');
    expect(address['addressLine2'], 'Flat 4B');
    expect(address['postalCode'], 'GA-001');
    expect(address['deliveryInstructions'], 'Call first');
    // No invented keys beyond the contract's address fields.
    expect(
      address.keys,
      containsAll([
        'fullName',
        'phone',
        'addressLine1',
        'city',
        'region',
        'country',
      ]),
    );

    expect(order.reference, 'LPS260912482915');
    expect(order.subtotal, 153.98);
    expect(order.discount, 15.40);
    expect(order.deliveryFee, 20);
    expect(order.total, 158.58);
    expect(order.paymentMethod, 'momo');
    expect(order.shippingAddress?.summary, contains('Osu Avenue'));

    final item = order.items.single;
    expect(item.productId, 'p1');
    expect(item.sku, '18339');
    expect(item.partnerLocationId, 'MELCOM-ACCRA-01');
    expect(item.price, 69.29);
    expect(item.listPrice, 76.99);
    expect(item.discountAmount, 7.70);
    expect(item.imageAsset, 'https://cdn.test/18339.webp');

    expect(order.deliveryUpdates.single.status, 'order_placed');
  });

  test('shop tracking reads deliveryUpdates with dates and address', () async {
    final (api, _) = await _client(
      (_) => {
        'orderNumber': 'LPS260912482913',
        'status': 'shipped',
        'trackingNumber': 'TRK-1',
        'carrier': 'SpeedAf',
        'estimatedDeliveryDate': '2026-10-25T00:00:00.000Z',
        'deliveredAt': null,
        'lastDriverLocation': {
          'latitude': 5.6037,
          'longitude': -0.187,
          'recordedAt': '2026-10-21T09:05:00.000Z',
        },
        'shippingAddress': {
          'fullName': 'Kofi Mensah',
          'addressLine1': '12 Osu Avenue',
          'city': 'Accra',
          'country': 'Ghana',
        },
        'deliveryUpdates': [
          {
            'status': 'order_placed',
            'message': 'Order placed',
            'timestamp': '2026-10-19T08:00:00.000Z',
          },
          {
            'status': 'shipped',
            'message': 'Handed to courier',
            'location': 'Accra Hub',
            'timestamp': '2026-10-21T09:00:00.000Z',
          },
        ],
      },
    );
    final tracking = await RemoteShopRepository(api)
        .getOrderTracking('o1');

    expect(tracking, isNotNull);
    expect(tracking!.orderNumber, 'LPS260912482913');
    expect(tracking.carrier, 'SpeedAf');
    expect(tracking.trackingNumber, 'TRK-1');
    expect(
      tracking.estimatedDeliveryDate,
      DateTime.parse('2026-10-25T00:00:00.000Z'),
    );
    expect(tracking.shippingAddress?.city, 'Accra');
    expect(tracking.lastDriverLocation, isNotNull);
    expect(tracking.lastDriverLocation!.latitude, 5.6037);
    expect(tracking.lastDriverLocation!.longitude, -0.187);
    expect(
      tracking.lastDriverLocation!.recordedAt,
      DateTime.parse('2026-10-21T09:05:00.000Z'),
    );
    expect(tracking.events, hasLength(2));
    // Newest first for the timeline UI.
    expect(tracking.events.first.status, 'shipped');
    expect(tracking.events.first.location, 'Accra Hub');
    expect(tracking.events.last.status, 'order_placed');
  });

  test('shop order number lookup hits the public route', () async {
    final (api, adapter) = await _client(
      (_) => {
        '_id': 'o9',
        'orderNumber': 'LPS260912482999',
        'total': 42,
        'currency': 'GHS',
      },
    );
    final order = await RemoteShopRepository(api)
        .getOrderByNumber('LPS260912482999');

    expect(
      adapter.requests.single.path,
      '/api/v1/shop/orders/number/LPS260912482999',
    );
    expect(order?.id, 'o9');
    expect(order?.reference, 'LPS260912482999');
  });

  test('GTPay verifies the customer then pays with an exact amount', () async {
    final (api, adapter) = await _client((options) {
      if (options.path.contains('/gtpay/query')) return {'CustomerName': 'Ama'};
      return {'PartnerTransId': 'GT-1', 'status': 'SUCCESS'};
    });
    final repo = RemoteServicesRepository(
      api,
      userId: 'user-1',
      userName: 'Kofi Owusu',
    );
    final receipt = await repo.payGtPayService(
      serviceName: 'airtime',
      serviceNumber: '0241120481',
      amount: 10,
      remarks: 'Wallet top-up',
    );

    expect(receipt.reference, 'GT-1');
    final pay = adapter.requests.firstWhere(
      (request) => request.path.contains('/gtpay/pay'),
    );
    expect(pay.data['userId'], 'user-1');
    final details = pay.data['ServiceDetails'] as Map<String, dynamic>;
    expect(details['Amount'], '10.00');
    expect(details['PaidBy'], 'Kofi Owusu');
    expect(details['PayeeName'], 'Ama');
    expect(details['Remarks'], 'Wallet top-up');
  });

  test('GTPay services parse the bank/service catalogue', () async {
    final (api, _) = await _client(
      (_) => {
        'services': [
          {
            'ServiceName': 'creditwallet',
            'friendlyName': 'Wallet Top-up',
            'description': 'Fund a wallet',
          },
          {'serviceName': 'banktrf', 'name': 'Bank Transfer'},
        ],
      },
    );
    final services = await RemoteServicesRepository(api).getGtPayServices();

    expect(services, hasLength(2));
    expect(services.first.id, 'creditwallet');
    expect(services.first.name, 'Wallet Top-up');
    expect(services.last.id, 'banktrf');
  });

  test('direct login parses tokens + user and persists the session', () async {
    final (api, adapter) = await _client(
      (_) => {
        'access_token': 'access-1',
        'refresh_token': 'refresh-1',
        'user': {
          '_id': 'u-1',
          'username': '0244588584',
          'email': 'ama@example.com',
          'firstName': 'Ama',
          'lastName': 'Mensah',
          'phoneNumber': '0244588584',
          'country': 'Ghana',
          'status': 'ACTIVE',
        },
      },
    );
    final session = await RemoteAuthRepository(
      api,
      api.tokenStore,
    ).login(const LoginRequest(username: '0244588584', password: 'secret1'));

    final login = adapter.requests.single;
    expect(login.path, '/api/v1/users/login');
    expect(login.data, {'username': '0244588584', 'password': 'secret1'});
    expect(session.tokens.accessToken, 'access-1');
    expect(session.tokens.refreshToken, 'refresh-1');
    expect(session.user.id, 'u-1');
    expect(session.user.fullName, 'Ama Mensah');
    expect(api.tokenStore.accessToken, 'access-1');
    expect(api.tokenStore.refreshToken, 'refresh-1');
    expect(api.tokenStore.profileJson?['email'], 'ama@example.com');
  });

  test('password reset sends email or phoneNumber by identifier shape', () async {
    final (api, adapter) = await _client((_) => {});
    final repo = RemoteAuthRepository(api, api.tokenStore);

    await repo.requestPasswordReset('ama@example.com');
    await repo.requestPasswordReset('0244588584');
    await repo.requestPasswordReset('+233244588584');

    expect(adapter.requests, hasLength(3));
    for (final request in adapter.requests) {
      expect(request.method, 'POST');
      expect(request.path, '/api/v1/users/reset-password');
    }
    expect(adapter.requests[0].data, {'email': 'ama@example.com'});
    expect(adapter.requests[1].data, {'phoneNumber': '0244588584'});
    expect(adapter.requests[2].data, {'phoneNumber': '+233244588584'});
  });

  test('confirm reset posts token and new password', () async {
    final (api, adapter) = await _client((_) => {});
    await RemoteAuthRepository(api, api.tokenStore).confirmPasswordReset(
      token: 'tok-123',
      newPassword: 'newSecret1',
    );

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/api/v1/users/confirm-reset-password');
    expect(request.data, {'token': 'tok-123', 'newPassword': 'newSecret1'});
  });

  test('change password PUTs current and new password with auth', () async {
    final (api, adapter) = await _client(
      (_) => {'access_token': 'a', 'refresh_token': 'r', 'user': {}},
    );
    final repo = RemoteAuthRepository(api, api.tokenStore);
    // Establish a session so the Bearer interceptor attaches.
    await repo.login(
      const LoginRequest(username: '0244588584', password: 'secret1'),
    );

    await repo.requestPasswordChange(
      currentPassword: 'secret1',
      newPassword: 'newSecret1',
    );

    final request = adapter.requests.last;
    expect(request.method, 'PUT');
    expect(request.path, '/api/v1/users/change-password');
    expect(request.data, {
      'currentPassword': 'secret1',
      'newPassword': 'newSecret1',
    });
    expect(request.headers['Authorization'], 'Bearer a');
  });

  test('confirm password change posts the link token', () async {
    final (api, adapter) = await _client((_) => {});
    await RemoteAuthRepository(
      api,
      api.tokenStore,
    ).confirmPasswordChange(token: 'vtok-9');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/api/v1/users/confirm-password-change');
    expect(request.data, {'token': 'vtok-9'});
  });

  test('registration sends the live contract fields', () async {
    final (api, adapter) = await _client((_) => {});
    await RemoteAuthRepository(api, api.tokenStore).register(
      const RegisterRequest(
        firstName: 'Peprah',
        lastName: 'Crayaman',
        email: 'pp.crayaman@outlook.com',
        phoneNumber: '0244588584',
        country: 'GHANA',
        password: 'V9DTesfRBjgh',
      ),
    );

    final request = adapter.requests.single;
    expect(request.path, '/api/v1/users/register');
    expect(request.data['firstName'], 'Peprah');
    expect(request.data['phoneNumber'], '0244588584');
    expect(request.data['country'], 'GHANA');
    expect(request.data['roles'], ['user']);
    expect(request.data.containsKey('password'), isTrue);
  });

  test(
    'profile update merges the response and keeps the session tokens',
    () async {
      final (api, adapter) = await _client(
        (_) => {
          'user': {
            '_id': 'u-1',
            'username': '0244588584',
            'firstName': 'Kofi',
            'lastName': 'Annan',
            'email': 'kofi@example.com',
            'phoneNumber': '0241111111',
            'emailVerified': true,
            'phoneVerified': false,
            'status': 'ACTIVE',
          },
        },
      );
      await api.tokenStore.saveSession(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        profile: {
          '_id': 'u-1',
          'firstName': 'Ama',
          'lastName': 'Mensah',
          'email': 'ama@example.com',
          'phoneNumber': '0244588584',
          'country': 'GHANA',
          'status': 'ACTIVE',
        },
      );

      final user = await RemoteAuthRepository(api, api.tokenStore)
          .updateProfile(
            const ProfileUpdateRequest(
              firstName: 'Kofi',
              lastName: 'Annan',
              email: 'kofi@example.com',
              phoneNumber: '0241111111',
            ),
          );

      final request = adapter.requests.single;
      expect(request.method, 'PUT');
      expect(request.path, '/api/v1/users/profile/update');
      expect(request.data, {
        'firstName': 'Kofi',
        'lastName': 'Annan',
        'email': 'kofi@example.com',
        'phoneNumber': '0241111111',
      });
      expect(user.fullName, 'Kofi Annan');
      expect(user.emailVerified, isTrue);
      expect(user.phoneVerified, isFalse);
      expect(api.tokenStore.accessToken, 'access-1');
      expect(api.tokenStore.refreshToken, 'refresh-1');
      expect(api.tokenStore.profileJson?['email'], 'kofi@example.com');
      expect(api.tokenStore.profileJson?['country'], 'GHANA');
    },
  );

  test(
    'wallet 500 degrades to unavailable without blocking points/value',
    () async {
      final (api, adapter) = await _client(
        (options) {
          if (options.path.contains('/users/wallet/user') ||
              options.path.contains('/users/account')) {
            return {
              'statusCode': 500,
              'message': 'Internal server error',
              'error': 'Internal Server Error',
            };
          }
          if (options.path.contains('/lidapoints/balance'))
            return {'balance': 18450};
          return {'totalValueUnits': 125.5};
        },
        status: (options) =>
            options.path.contains('/users/wallet/user') ||
                options.path.contains('/users/account')
            ? 500
            : 200,
      );

      final summary = await RemoteDashboardRepository(
        api,
        'u-1',
      ).getWalletSummary();

      expect(summary.walletAvailable, isFalse);
      expect(summary.balance, 0);
      expect(summary.currency, 'GHS');
      expect(summary.lidaPoints, 18450);
      expect(summary.lidaValueUnits, 125.5);
      expect(adapter.requests, hasLength(4));
    },
  );

  test('wallet 500 falls back to the users/account balance', () async {
    final (api, adapter) = await _client(
      (options) {
        if (options.path.contains('/users/wallet/user')) {
          return {
            'statusCode': 500,
            'message': 'Internal server error',
            'error': 'Internal Server Error',
          };
        }
        if (options.path.contains('/users/account')) {
          return {
            'id': 'acct-1',
            'userId': 'u-1',
            'balance': 120,
            'transactions': const [],
          };
        }
        if (options.path.contains('/lidapoints/balance'))
          return {'balance': 18450};
        return {'totalValueUnits': 125.5};
      },
      status: (options) =>
          options.path.contains('/users/wallet/user') ? 500 : 200,
    );

    final summary = await RemoteDashboardRepository(
      api,
      'u-1',
    ).getWalletSummary();

    expect(summary.walletAvailable, isTrue);
    expect(summary.balance, 120);
    expect(summary.lidaPoints, 18450);
    expect(summary.lidaValueUnits, 125.5);
    expect(adapter.requests, hasLength(4));
  });

  test('401 refresh retries once with the new access token', () async {
    var protectedCalls = 0;
    final (api, adapter) = await _client(
      (options) {
        if (options.path == '/api/v1/auth/refresh') {
          return {
            'access_token': 'fresh-access',
            'refresh_token': 'fresh-refresh',
          };
        }
        return {'balance': 120};
      },
      status: (options) {
        if (options.path == '/api/v1/auth/refresh') return 200;
        protectedCalls++;
        return protectedCalls == 1 ? 401 : 200;
      },
    );
    await api.tokenStore.saveSession(
      accessToken: 'expired',
      refreshToken: 'refresh-old',
    );

    final wallet = await api.get('/api/v1/users/wallet/user');

    expect(wallet['balance'], 120);
    expect(protectedCalls, 2);
    final refresh = adapter.requests.firstWhere(
      (request) => request.path == '/api/v1/auth/refresh',
    );
    expect(refresh.data['refreshToken'], 'refresh-old');
    expect(
      adapter.requests.last.headers['Authorization'],
      'Bearer fresh-access',
    );
    expect(api.tokenStore.accessToken, 'fresh-access');
    expect(api.tokenStore.refreshToken, 'fresh-refresh');
  });

  test('a second 401 stops retrying and clears the session', () async {
    final (api, adapter) = await _client(
      (_) => {'access_token': 'fresh', 'refresh_token': 'rotated'},
      status: (options) => options.path == '/api/v1/auth/refresh' ? 200 : 401,
    );
    await api.tokenStore.saveSession(
      accessToken: 'expired',
      refreshToken: 'old',
    );

    await expectLater(
      api.get('/api/v1/users/profile'),
      throwsA(isA<ApiException>()),
    );
    expect(adapter.requests, hasLength(3));
    expect(api.tokenStore.hasSession, isFalse);
  });

  test('purchase POST is not replayed after refreshing auth', () async {
    final (api, adapter) = await _client(
      (_) => {'access_token': 'fresh', 'refresh_token': 'rotated'},
      status: (options) => options.path == '/api/v1/auth/refresh' ? 200 : 401,
    );
    await api.tokenStore.saveSession(
      accessToken: 'expired',
      refreshToken: 'old',
    );

    await expectLater(
      api.post('/api/v1/airtime/topup', body: {'amount': 10}),
      throwsA(isA<ApiException>()),
    );
    expect(
      adapter.requests.where((r) => r.path == '/api/v1/airtime/topup'),
      hasLength(1),
    );
    expect(api.tokenStore.accessToken, 'fresh');
  });

  test('401 without refresh token clears the stale session', () async {
    final (api, adapter) = await _client((_) => {}, status: (_) => 401);
    await api.tokenStore.saveSession(accessToken: 'expired');

    await expectLater(
      api.get('/api/v1/users/profile'),
      throwsA(isA<ApiException>()),
    );
    expect(adapter.requests, hasLength(1));
    expect(api.tokenStore.hasSession, isFalse);
  });

  test(
    'unintegrated live services never return mock success receipts',
    () async {
      final (api, adapter) = await _client((_) => {});
      final repo = RemoteServicesRepository(api, userId: 'u-1');
      final actions = <Future<dynamic> Function()>[
        () => repo.payQr(merchantCode: 'merchant', amount: 10),
      ];
      for (final action in actions) {
        await expectLater(
          action(),
          throwsA(
            isA<ApiException>().having(
              (error) => error.message,
              'message',
              contains('No transaction was submitted'),
            ),
          ),
        );
      }
      expect(adapter.requests, isEmpty);
    },
  );

  test(
    'OTP challenge and verify-otp persist session only after verification',
    () async {
      final (api, adapter) = await _client((options) {
        if (options.path == '/api/v1/auth/login/request-otp') {
          return {
            'message': 'Login verification code sent to your email',
            'challengeToken': 'challenge-jwt-123',
            'expiresAt': '2026-03-18T16:00:00.000Z',
          };
        }
        return {
          'access_token': 'verified-access',
          'refresh_token': 'verified-refresh',
          'user': {
            '_id': '673ba0e3f2c001e4dcee976e',
            'username': '0244000000',
            'email': 'user@example.com',
            'firstName': 'Kofi',
            'lastName': 'Mensah',
          },
        };
      });
      final repo = RemoteAuthRepository(api, api.tokenStore);

      final challenge = await repo.requestLoginOtp(
        const OtpChallengeRequest(username: '0244000000'),
      );
      expect(challenge.challengeToken, 'challenge-jwt-123');
      expect(api.tokenStore.hasSession, isFalse);

      final session = await repo.verifyLoginOtp(
        OtpVerifyRequest(
          challengeToken: challenge.challengeToken,
          otpCode: '123456',
          username: '0244000000',
        ),
      );
      expect(session.tokens.accessToken, 'verified-access');
      expect(session.user.id, '673ba0e3f2c001e4dcee976e');
      expect(api.tokenStore.accessToken, 'verified-access');
      expect(api.tokenStore.refreshToken, 'verified-refresh');
      expect(adapter.requests.last.path, '/api/v1/auth/login/verify-otp');
      expect(adapter.requests.last.data['challengeToken'], 'challenge-jwt-123');
      expect(adapter.requests.last.data['otpCode'], '123456');
    },
  );

  test('failed refresh clears the stored session', () async {
    final (api, _) = await _client(
      (_) => {
        'statusCode': 401,
        'message': 'Unauthorized',
        'error': 'Unauthorized',
      },
      status: (_) => 401,
    );
    await api.tokenStore.saveSession(
      accessToken: 'expired',
      refreshToken: 'stale',
    );

    await expectLater(
      () => api.get('/api/v1/users/wallet/user'),
      throwsA(isA<ApiException>()),
    );
    expect(api.tokenStore.hasSession, isFalse);
    expect(api.tokenStore.refreshToken, isNull);
  });

  test('notification parses the documented channel-dispatch shape', () {
    final n = AppNotification.fromApiJson(const {
      '_id': '67e15e8e6f57f8f7f6db8e11',
      'userId': 'recipient@example.com',
      'type': 'email',
      'subject': 'Recipient Decision Update',
      'message': 'Airtime transfer decision is pending your action.',
      'status': 'sent',
      'createdAt': '2026-02-21T03:05:40.000Z',
    });
    expect(n.id, '67e15e8e6f57f8f7f6db8e11');
    expect(n.channel, 'email');
    expect(n.displayTitle, 'Recipient Decision Update');
    expect(n.displayMessage, contains('pending your action'));
  });

  test('notification treats an event name in type as a push event', () {
    final n = AppNotification.fromApiJson(const {
      '_id': 'abc',
      'type': 'recipient_topup_decision',
      'message': 'Airtime transfer decision is pending your action.',
      'status': 'sent',
      'createdAt': '2026-02-21T03:05:40.000Z',
    });
    expect(n.channel, 'push');
    expect(n.eventType, 'recipient_topup_decision');
    expect(n.kind, 'decision');
    expect(n.needsAction, isTrue);
    expect(n.displayTitle, 'Top-up needs your choice');
  });

  test('decision notification composes a body from the push payload', () {
    final n = AppNotification.fromApiJson(const {
      '_id': 'abc',
      'type': 'push',
      'eventType': 'recipient_topup_decision',
      'data': {
        'decisionId': 'd1',
        'topupOrderId': 't9',
        'serviceType': 'AIRTIME',
        'amount': 50,
        'currency': 'GHS',
        'senderName': 'Kofi',
      },
      'status': 'sent',
    });
    expect(n.needsAction, isTrue);
    expect(
      n.displayMessage,
      'Kofi sent you GH₵50.00 airtime. '
      'Tap to choose where to receive it.',
    );
    expect(n.data['decisionId'], 'd1');
  });

  test('notification strips embedded JSON payload from message text', () {
    // Backend sometimes appends the raw entity — password hash and base64
    // avatar included — after the prose. None of it may reach the UI.
    final n = AppNotification.fromApiJson(const {
      '_id': 'n1',
      'type': 'email',
      'subject': 'Profile updated',
      'message':
          'Your profile has been updated successfully. Details: '
          '{"_id":"696d454f","password":"\$2b\$10\$xyz","gravatar":"data:image/png;base64,iVBOR"}',
      'status': 'sent',
      'createdAt': '2026-02-21T03:05:40.000Z',
    });
    expect(n.displayMessage, 'Your profile has been updated successfully.');
    expect(n.displayMessage, isNot(contains('password')));
    expect(n.displayMessage, isNot(contains('base64')));
  });

  test('notification that is only a JSON blob shows no prose', () {
    final n = AppNotification.fromApiJson(const {
      '_id': 'n2',
      'type': 'push',
      'message': '{"topupOrderId":"t1","status":"PARKED"}',
      'status': 'sent',
    });
    expect(n.displayMessage, isNot(contains('{')));
  });

  test('resolved notification keeps the resolved kind', () {
    final n = AppNotification.fromApiJson(const {
      '_id': 'abc',
      'type': 'push',
      'eventType': 'recipient_topup_resolved',
      'data': {'selectedChoice': 'WALLET', 'finalDisposition': 'DELIVERED'},
      'status': 'sent',
    });
    expect(n.kind, 'resolved');
    expect(n.needsAction, isFalse);
    expect(n.displayTitle, 'Top-up completed');
  });

  test('airtime autodetect posts msisdn and parses the operator', () async {
    final (api, adapter) = await _client(
      (_) => {
        'operatorId': 341,
        'name': 'MTN Nigeria',
        'minAmount': 1,
        'maxAmount': 200,
        'suggestedAmounts': [50, 10, 25],
        'senderCurrencyCode': 'USD',
        'senderCurrencySymbol': '\$',
        'destinationCurrencyCode': 'NGN',
        'fx': {'rate': 0.004, 'currencyCode': 'GHS'},
        'logoUrl': 'https://cdn.test/mtn.png',
      },
    );
    final op = await RemoteServicesRepository(api).detectAirtimeOperator(
      phone: '08034567890',
      countryIsoCode: 'NG',
      recipientDialCode: '+234',
    );

    final request = adapter.requests.single;
    expect(request.path, '/api/v1/reloadly/operator/autodetect');
    final body = request.data as Map<String, dynamic>;
    expect(body['phone'], '2348034567890');
    expect(body['countryIsoCode'], 'NG');
    expect(body['suggestedAmountsMap'], isTrue);

    expect(op.id, 341);
    expect(op.name, 'MTN Nigeria');
    expect(op.suggestedAmounts, [10, 25, 50]);
    expect(op.accepts(150), isTrue);
    expect(op.accepts(500), isFalse);
    expect(op.paymentAmount(100), 0.4);
    expect(op.fxCurrencyCode, 'GHS');
    expect(op.logoUrl, 'https://cdn.test/mtn.png');
  });

  test('data autodetect sends msisdn query params', () async {
    final (api, adapter) = await _client(
      (_) => {
        'operatorId': 265,
        'name': 'Safaricom',
        'suggestedAmountsMap': {'a': 5, 'b': 20},
      },
    );
    final op = await RemoteServicesRepository(api).detectDataOperator(
      phone: '0712345678',
      countryIsoCode: 'KE',
      recipientDialCode: '+254',
    );

    final request = adapter.requests.firstWhere(
      (r) => r.path == '/api/v1/reloadly-data/auto-detect',
    );
    expect(request.uri.queryParameters['msisdn'], '254712345678');
    expect(request.uri.queryParameters['countryCode'], 'KE');
    // No `fx` in the payload → the repository consults Reloadly's per-operator
    // fx-rate route for the USD→local conversion.
    expect(
      adapter.requests.any(
        (r) =>
            r.path == '/api/v1/reloadly/operators/265/fx-rate' &&
            r.uri.queryParameters['amount'] == '1' &&
            r.uri.queryParameters['currencyCode'] == 'USD',
      ),
      isTrue,
    );
    expect(op.id, 265);
    expect(op.suggestedAmounts, [5, 20]);
  });

  test('autodetect without an operator match throws', () async {
    final (api, _) = await _client((_) => {'success': false});
    await expectLater(
      RemoteServicesRepository(api)
          .detectAirtimeOperator(phone: '0000', countryIsoCode: 'NG'),
      throwsA(isA<ApiException>()),
    );
  });

  group('OTP session identity hardening', () {
    // The live verify-otp `user` object arrived with literal 'undefined'
    // strings for identity fields; those poisoned every downstream call
    // that requires a real user id (internet/buydata 500s on them).
    test('profile parsing treats literal undefined/null ids as missing', () {
      expect(
        UserProfile.fromJson({'id': 'undefined'}).id,
        '',
      );
      expect(
        UserProfile.fromJson({'_id': 'null'}).id,
        '',
      );
      expect(
        UserProfile.fromJson({'userId': '694abae'}).id,
        '694abae',
      );
    });

    test(
      'otp verify with undefined user id recovers it from the JWT sub',
      () async {
        // {"alg":"none"}.{"sub":"694abae5d474016f3985cdaf"}.sig — the token's
        // sub is the same user id the backend uses as user._id.
        final payload = base64UrlEncode(
          utf8.encode(jsonEncode({'sub': '694abae5d474016f3985cdaf'})),
        ).replaceAll('=', '');
        final token = 'e30.$payload.sig';
        final (api, _) = await _client(
          (_) => {
            'access_token': token,
            'refresh_token': 'refresh-1',
            'user': {'id': 'undefined', 'userName': 'undefined'},
          },
        );
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = RemoteAuthRepository(api, TokenStore(prefs));

        final session = await repo.verifyLoginOtp(
          const OtpVerifyRequest(
            challengeToken: 'challenge-1',
            otpCode: '123456',
            username: '0593998216',
          ),
        );

        expect(session.user.id, '694abae5d474016f3985cdaf');
      },
    );

    test(
      'ghana buydata never sends undefined identity — real ids pass through',
      () async {
        final (api, adapter) = await _client(
          (_) => {'success': true, 'transactionId': 'DAT-1'},
        );
        const bundle = DataBundle(
          id: 'BDLHRBOOST2',
          name: '1GB',
          price: 1,
          dataAmount: '1GB',
        );

        await RemoteServicesRepository(
          api,
          userId: 'undefined',
          userName: '',
          userPhone: 'undefined',
        ).buyDataBundle(
          recipientNumber: '0208234608',
          networkId: '6',
          bundle: bundle,
          saveToLidaValue: false,
        );

        final bad = adapter.requests.last.data as Map;
        expect(bad.containsKey('id'), isFalse);
        expect(bad.containsKey('userId'), isFalse);
        expect(bad.containsKey('userName'), isFalse);

        await RemoteServicesRepository(
          api,
          userId: '694abae5d474016f3985cdaf',
          userName: '0244588584',
        ).buyDataBundle(
          recipientNumber: '0244588584',
          networkId: '4',
          bundle: bundle,
          saveToLidaValue: false,
          isSelfTopup: true,
        );

        final good = adapter.requests.last.data as Map;
        expect(good['id'], '694abae5d474016f3985cdaf');
        expect(good['userId'], '694abae5d474016f3985cdaf');
        expect(good['userName'], '0244588584');
      },
    );

    test('userName falls back to the account phone when names are empty', () async {
      final (api, adapter) = await _client(
        (_) => {'success': true, 'transactionId': 'AIR-1'},
      );

      await RemoteServicesRepository(
        api,
        userName: '',
        userPhone: '0593998216',
      ).buyLocalAirtime(
        recipientNumber: '0241234567',
        amount: 5,
        networkId: '4',
        saveToLidaValue: false,
      );

      final body = adapter.requests.last.data as Map;
      expect(body['userName'], '0593998216');
    });

    test(
      'otp verify skips undefined JWT sub and recovers userId claim',
      () async {
        final payload = base64UrlEncode(
          utf8.encode(
            jsonEncode({'sub': 'undefined', 'userId': '694abae5d474016f3985cdaf'}),
          ),
        ).replaceAll('=', '');
        final token = 'e30.$payload.sig';
        final (api, _) = await _client(
          (_) => {
            'access_token': token,
            'refresh_token': 'refresh-1',
            'user': {'id': 'undefined'},
          },
        );
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = RemoteAuthRepository(api, TokenStore(prefs));

        final session = await repo.verifyLoginOtp(
          const OtpVerifyRequest(
            challengeToken: 'challenge-1',
            otpCode: '123456',
            username: '0593998216',
          ),
        );

        expect(session.user.id, '694abae5d474016f3985cdaf');
      },
    );

    test(
      'restoreSession clears cached pre-fix OTP sessions with undefined sub',
      () async {
        final payload = base64UrlEncode(
          utf8.encode(jsonEncode({'sub': 'undefined'})),
        ).replaceAll('=', '');
        final token = 'e30.$payload.sig';
        final (api, _) = await _client((_) => {});
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = TokenStore(prefs);
        await store.saveSession(
          accessToken: token,
          refreshToken: 'refresh-1',
          profile: {'id': 'undefined', 'username': '0593998216'},
        );
        await store.saveBiometricSession();

        final restored = await RemoteAuthRepository(api, store).restoreSession();

        expect(restored, isNull);
        expect(store.hasSession, isFalse);
        expect(await store.hasBiometricSession, isFalse);
      },
    );

    test(
      'history loads JWT-scoped feeds when userId is empty and survives 500s',
      () async {
        final (api, adapter) = await _client(
          (options) {
            if (options.path == '/api/v1/users/account') {
              return {'message': 'Internal server error'};
            }
            if (options.path == '/api/v1/lida-value/history') {
              return {
                'data': [
                  {
                    '_id': 'lv-1',
                    'transactionReference': 'LV-REF-1',
                    'type': 'save',
                    'valueUnits': 5,
                    'direction': 'credit',
                    'createdAt': '2026-10-18T12:00:00.000Z',
                  },
                ],
              };
            }
            if (options.path == '/api/v1/shop/orders') {
              return <Object>[];
            }
            if (options.path == '/api/v1/lidapoints/history') {
              return <Object>[];
            }
            return {};
          },
          status: (options) =>
              options.path == '/api/v1/users/account' ? 500 : 200,
        );

        final items = await RemoteHistoryRepository(api, '').getTransactions();

        expect(items, hasLength(1));
        expect(items.single.reference, 'LV-REF-1');
        expect(items.single.type, TransactionType.lidaValue);
        expect(
          adapter.requests.any((r) => r.path.contains('/transactions/user/')),
          isFalse,
        );
      },
    );

    test(
      'Lida Value and Lida Points wallets fall back cleanly on 500 errors',
      () async {
        final (valueApi, _) = await _client(
          (_) => {'message': 'Internal server error'},
          status: (options) =>
              options.path.contains('balance') ? 500 : 200,
        );
        final lvWallet = await RemoteServicesRepository(
          valueApi,
        ).getLidaValueWallet();
        expect(lvWallet.balance, 0);
        expect(lvWallet.pending, 0);

        final (pointsApi, _) = await _client(
          (options) {
            if (options.path == '/api/v1/users/points') return 42;
            if (options.path == '/api/v1/lidapoints/history') return <Object>[];
            return {'message': 'Internal server error'};
          },
          status: (options) =>
              options.path == '/api/v1/lidapoints/balance' ? 500 : 200,
        );
        final lpWallet = await RemoteServicesRepository(
          pointsApi,
        ).getLidaPointsWallet();
        expect(lpWallet.balance, 42);
      },
    );
  });
}
