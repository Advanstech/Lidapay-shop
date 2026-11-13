import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_payload.dart';
import 'shop_models.dart';
import 'shop_repository.dart';

/// Live shop catalog, cart and checkout. None of the shop endpoints publish a
/// response example in the spec, so every field is read through a candidate
/// key list and absent values fall back to a safe default.
class RemoteShopRepository implements ShopRepository {
  RemoteShopRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<ShopCategory>> getCategories() async {
    final rows = rowsOf(
      await _api.getRaw(
        ApiEndpoints.shopCategories,
        queryParameters: const {'activeOnly': true},
      ),
    );
    return rows
        .map((row) {
          final pool = payloadPool(row);
          final id = stringField(pool, const ['id', '_id', 'slug', 'code']);
          final name = stringField(pool, const ['name', 'title', 'label']);
          if (id == null || name == null) return null;
          return ShopCategory(
            id: id,
            name: name,
            icon:
                stringField(pool, const ['icon', 'iconName', 'image']) ??
                'category',
          );
        })
        .whereType<ShopCategory>()
        .toList();
  }

  @override
  Future<List<ShopProduct>> getProducts({
    String? categoryId,
    String? query,
  }) async {
    final search = query?.trim();
    final params = <String, dynamic>{'page': 1, 'limit': 40};
    if (categoryId != null && categoryId.isNotEmpty)
      params['category'] = categoryId;
    if (search != null && search.isNotEmpty) params['search'] = search;
    return _products(
      await _api.getRaw(ApiEndpoints.shopProducts, queryParameters: params),
    );
  }

  @override
  Future<List<ShopProduct>> getFeaturedProducts() async =>
      _products(await _api.getRaw(ApiEndpoints.shopFeatured));

  @override
  Future<ShopProduct?> getProduct(String id) async {
    try {
      final row = payloadPool(
        asMap(await _api.getRaw(ApiEndpoints.shopProduct(id))),
      );
      return _product(row);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Cart> getCart() async =>
      _cart(await _api.getRaw(ApiEndpoints.shopCart));

  @override
  Future<Cart> addToCart(String productId, {int quantity = 1}) async => _cart(
    await _api.postRaw(
      ApiEndpoints.shopCartAdd,
      body: {'productId': productId, 'quantity': quantity},
    ),
  );

  @override
  Future<Cart> updateQuantity(String productId, int quantity) async => _cart(
    await _api.putRaw(
      ApiEndpoints.shopCartUpdate,
      body: {'productId': productId, 'quantity': quantity},
    ),
  );

  @override
  Future<Cart> removeFromCart(String productId) async => _cart(
    await _api.postRaw(
      ApiEndpoints.shopCartRemove,
      body: {'productId': productId},
    ),
  );

  @override
  Future<Cart> clearCart() async =>
      _cart(await _api.deleteRaw(ApiEndpoints.shopCartClear));

  @override
  Future<ShopOrder> checkout({
    required ShippingAddress shippingAddress,
    String paymentMethod = 'momo',
    double deliveryFee = 0,
  }) async {
    final pool = payloadPool(
      asMap(
        await _api.postRaw(
          ApiEndpoints.shopCheckout,
          body: {
            'shippingAddress': shippingAddress.toJson(),
            'paymentMethod': paymentMethod,
            if (deliveryFee > 0) 'deliveryFee': deliveryFee,
            'redirectUrl': AppConstants.shopCheckoutRedirectUrl,
          },
        ),
      ),
    );
    return _order(pool);
  }

  @override
  Future<List<ShopOrder>> getOrders({int page = 1, int limit = 20}) async {
    try {
      final raw = await _api.getRaw(
        ApiEndpoints.shopOrders,
        queryParameters: {'page': page, 'limit': limit},
      );
      return rowsOf(raw).map((r) => _order(payloadPool(r))).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<ShopOrder?> getOrder(String id) async {
    try {
      final pool = payloadPool(
        asMap(await _api.getRaw(ApiEndpoints.shopOrderById(id))),
      );
      return _order(pool);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ShopOrder?> getOrderByNumber(String orderNumber) async {
    try {
      final pool = payloadPool(
        asMap(await _api.getRaw(ApiEndpoints.shopOrderByNumber(orderNumber))),
      );
      return _order(pool);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ShopOrderTracking?> getOrderTracking(String id) async {
    try {
      final raw = await _api.getRaw(ApiEndpoints.shopOrderTracking(id));
      final pool = payloadPool(asMap(raw));
      final events = _timelineEvents(
        pool['deliveryUpdates'] ??
            pool['events'] ??
            pool['timeline'] ??
            pool['history'],
      );

      return ShopOrderTracking(
        orderId: id,
        orderNumber: stringField(pool, const [
          'orderNumber',
          'reference',
        ]),
        status:
            stringField(pool, const ['status', 'deliveryStatus']) ?? 'pending',
        carrier: stringField(pool, const ['carrier', 'courier', 'provider']),
        trackingNumber: stringField(pool, const [
          'trackingNumber',
          'trackingCode',
          'waybill',
        ]),
        estimatedDeliveryDate: dateField(pool, const [
          'estimatedDeliveryDate',
          'estimatedDelivery',
          'eta',
        ]),
        deliveredAt: dateField(pool, const ['deliveredAt', 'delivered']),
        shippingAddress: _addressOf(pool['shippingAddress']),
        lastDriverLocation: _driverLocationOf(pool['lastDriverLocation']),
        events: events,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ShopOrder> cancelOrder(String id, {String? reason}) async {
    final raw = await _api.postRaw(
      ApiEndpoints.shopOrderCancel(id),
      body: {if (reason != null && reason.isNotEmpty) 'reason': reason},
    );
    return _order(payloadPool(asMap(raw)));
  }

  ShopOrder _order(Map<String, dynamic> pool) {
    final items = rowsOf(
      pool['items'] ?? pool['lineItems'] ?? pool['products'],
    );
    final orderItems = items.map((i) {
      final ip = payloadPool(i);
      final prod = ip['product'] is Map
          ? payloadPool(asMap(ip['product']))
          : ip;
      final rawPartner = ip['partner'] ?? prod['partner'];
      final partner = rawPartner is Map
          ? payloadPool(asMap(rawPartner))
          : const <String, dynamic>{};
      final rawLocation =
          ip['fulfilmentLocation'] ??
          ip['fulfillmentLocation'] ??
          prod['fulfilmentLocation'] ??
          prod['fulfillmentLocation'];
      final location = rawLocation is Map
          ? payloadPool(asMap(rawLocation))
          : const <String, dynamic>{};
      final quantity = numberField(ip, const ['quantity', 'qty'])?.round() ?? 1;
      final images = _imagesOf(prod);
      final unitPrice =
          numberField(ip, const ['unitPrice', 'price', 'sellingPrice']) ??
          numberField(prod, const ['discountPrice', 'price']) ??
          0;
      final listPrice =
          numberField(ip, const [
            'unitListPrice',
            'listPrice',
            'regularPrice',
            'originalPrice',
            'mrp',
          ]) ??
          numberField(prod, const [
            'unitListPrice',
            'listPrice',
            'regularPrice',
            'originalPrice',
            'price',
          ]);
      final discountAmount =
          numberField(ip, const [
            'unitDiscountAmount',
            'discountAmount',
            'discount',
          ]) ??
          (listPrice != null && listPrice > unitPrice
              ? listPrice - unitPrice
              : null);
      return ShopOrderItem(
        productId: stringField(prod, const ['id', '_id', 'productId']) ?? '',
        name:
            stringField(prod, const ['name', 'title', 'productName']) ??
            'Product',
        price: unitPrice,
        quantity: quantity,
        imageAsset: images.isNotEmpty ? images.first : '',
        sku:
            stringField(ip, const ['sku', 'productSku']) ??
            stringField(prod, const ['sku', 'productSku', 'productCode']),
        partnerId:
            stringField(ip, const [
              'partnerId',
              'sellerId',
              'vendorId',
              'merchantId',
            ]) ??
            stringField(partner, const ['id', '_id', 'partnerId']) ??
            stringField(prod, const [
              'partnerId',
              'sellerId',
              'vendorId',
              'merchantId',
            ]),
        partnerName:
            stringField(ip, const [
              'partnerName',
              'sellerName',
              'vendorName',
            ]) ??
            stringField(partner, const ['name', 'partnerName']) ??
            stringField(prod, const ['partnerName', 'seller', 'vendor']),
        partnerLocationId:
            stringField(ip, const [
              'partnerLocationId',
              'fulfilmentLocationId',
              'fulfillmentLocationId',
              'locationId',
              'storeId',
            ]) ??
            stringField(location, const [
              'id',
              '_id',
              'locationId',
              'storeId',
            ]) ??
            stringField(prod, const [
              'partnerLocationId',
              'fulfilmentLocationId',
              'fulfillmentLocationId',
              'locationId',
              'storeId',
            ]),
        listPrice: listPrice,
        discountAmount: discountAmount,
        promotionReference: stringField(ip, const [
          'promotionReference',
          'promotionId',
          'couponCode',
          'promoCode',
        ]),
        weightKg:
            numberField(ip, const ['weightKg', 'weight']) ??
            numberField(prod, const ['weightKg', 'weight']),
      );
    }).toList();

    return ShopOrder(
      id: stringField(pool, const ['id', '_id', 'orderId']) ?? '',
      reference:
          stringField(pool, const ['orderNumber', 'reference', 'receipt']) ??
          stringField(pool, const ['id', '_id']) ??
          '',
      itemCount:
          numberField(pool, const [
            'itemCount',
            'totalItems',
            'quantity',
          ])?.round() ??
          items.fold(
            0,
            (sum, item) =>
                sum +
                (numberField(payloadPool(item), const [
                      'quantity',
                      'qty',
                    ])?.round() ??
                    1),
          ),
      total:
          numberField(pool, const [
            'total',
            'totalAmount',
            'grandTotal',
            'amount',
          ]) ??
          0,
      currency: stringField(pool, const ['currency', 'currencyCode']) ?? 'GHS',
      paymentStatus:
          stringField(pool, const ['paymentStatus', 'payment_state']) ??
          'pending',
      status:
          stringField(pool, const ['status', 'orderStatus', 'state']) ??
          'pending',
      carrier: stringField(pool, const ['carrier', 'courier']),
      trackingNumber: stringField(pool, const [
        'trackingNumber',
        'trackingCode',
      ]),
      subtotal: numberField(pool, const [
        'subtotal',
        'subTotal',
        'itemsTotal',
      ]),
      discount: numberField(pool, const [
        'discount',
        'discountTotal',
        'totalDiscount',
      ]),
      deliveryFee: numberField(pool, const [
        'deliveryFee',
        'shippingFee',
        'deliveryCharge',
      ]),
      paymentMethod: stringField(pool, const [
        'paymentMethod',
        'payment_method',
        'paymentChannel',
      ]),
      shippingAddress: _addressOf(pool['shippingAddress']),
      deliveryUpdates: _timelineEvents(pool['deliveryUpdates']),
      items: orderItems,
      placedAt:
          dateField(pool, const [
            'placedAt',
            'createdAt',
            'created_at',
            'date',
            'orderDate',
          ]) ??
          DateTime.now(),
    );
  }

  List<ShopProduct> _products(Object? raw) =>
      rowsOf(raw).map(_product).whereType<ShopProduct>().toList();

  ShopProduct? _product(Map<String, dynamic> row) {
    final pool = payloadPool(row);
    // Cart line items snapshot the product as `productId` and carry their
    // own `_id` (the cart-line subdoc id) — so `productId` must win over
    // `id`/`_id` or cart mutations (remove/update) hit a bogus key.
    final id = stringField(pool, const [
      'productId',
      'id',
      '_id',
      'sku',
      'slug',
    ]);
    final name = stringField(pool, const ['name', 'title', 'productName']);
    if (id == null || name == null) return null;

    // Per the spec `price` is the regular price and `discountPrice` is the
    // discounted selling price — so a product on sale shows `discountPrice`
    // as the price and `price` as the struck-through old price.
    final listPrice =
        numberField(pool, const [
          'price',
          'regularPrice',
          'mrp',
          'listPrice',
          'cost',
        ]) ??
        0;
    final discounted = numberField(pool, const [
      'discountPrice',
      'salePrice',
      'sellingPrice',
      'promoPrice',
    ]);
    final explicitOld = numberField(pool, const [
      'oldPrice',
      'compareAtPrice',
      'wasPrice',
    ]);
    final double price;
    final double? oldPrice;
    if (discounted != null && discounted > 0 && discounted < listPrice) {
      price = discounted;
      oldPrice = listPrice;
    } else {
      price = discounted != null && discounted > 0 && listPrice <= 0
          ? discounted
          : listPrice;
      oldPrice = explicitOld != null && explicitOld > price
          ? explicitOld
          : null;
    }

    final images = _imagesOf(pool);
    final category = row['category'];
    return ShopProduct(
      id: id,
      name: name,
      categoryId: category is Map
          ? stringField(Map<String, dynamic>.from(category), const [
                  'id',
                  '_id',
                  'slug',
                ]) ??
                stringField(pool, const ['categoryId', 'category']) ??
                ''
          : stringField(pool, const ['categoryId', 'category']) ??
                category?.toString() ??
                '',
      price: price,
      currency: stringField(pool, const ['currency', 'currencyCode']) ?? 'GHS',
      imageAsset: images.isNotEmpty ? images.first : '',
      images: images,
      stock:
          numberField(pool, const [
            'stock',
            'stockQuantity',
            'quantity',
            'inventory',
            'count',
          ])?.round() ??
          0,
      rating:
          numberField(pool, const ['rating', 'averageRating', 'stars']) ?? 0,
      sold:
          numberField(pool, const [
            'sold',
            'salesCount',
            'soldCount',
            'ordersCount',
            'reviewsCount',
            'reviewCount',
          ])?.round() ??
          0,
      isFeatured: pool['featured'] == true || pool['isFeatured'] == true,
      description:
          stringField(pool, const ['description', 'summary', 'details']) ?? '',
      brand: stringField(pool, const ['brand', 'manufacturer']) ?? '',
      partnerName:
          stringField(pool, const ['partnerName', 'seller', 'vendor']) ?? '',
      partnerId: stringField(pool, const [
        'partnerId',
        'sellerId',
        'vendorId',
        'merchantId',
      ]),
      partnerLocationId: stringField(pool, const [
        'partnerLocationId',
        'fulfilmentLocationId',
        'fulfillmentLocationId',
        'locationId',
        'storeId',
      ]),
      sku: stringField(pool, const ['sku', 'productCode']) ?? '',
      attributes: _attributesOf(pool['attributes'] ?? pool['specs']),
      weightKg: numberField(pool, const ['weight', 'weightKg']),
      oldPrice: oldPrice,
    );
  }

  /// `attributes` arrives as a loose key-value map — normalise to strings.
  Map<String, String> _attributesOf(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value != null) entry.key.toString(): entry.value.toString(),
    };
  }

  /// Collects every image the row exposes — strings, `{url: …}` map entries
  /// and comma/bracket-joined strings all flatten into one ordered list.
  List<String> _imagesOf(Map<String, dynamic> pool) {
    final out = <String>[];
    void add(Object? value) {
      if (value is List) {
        for (final item in value) {
          add(item);
        }
        return;
      }
      if (value is Map) {
        add(
          value['url'] ?? value['src'] ?? value['imageUrl'] ?? value['image'],
        );
        return;
      }
      if (value is! String) return;
      var clean = value.trim();
      if (clean.startsWith('[') && clean.endsWith(']')) {
        clean = clean.substring(1, clean.length - 1);
      }
      for (final part in clean.split(',')) {
        final url = part
            .trim()
            .replaceAll(RegExp('^[\'"\\[]+|[\'"\\]]+\$'), '')
            .trim();
        if (url.isNotEmpty && !out.contains(url)) out.add(url);
      }
    }

    for (final key in const [
      'imageAsset',
      'image',
      'imageUrl',
      'thumbnail',
      'photo',
      'images',
      'imageUrls',
      'gallery',
    ]) {
      add(pool[key]);
    }
    return out;
  }

  Cart _cart(Object? raw) {
    final source = raw is Map ? payloadPool(asMap(raw)) : raw;
    final items = rowsOf(source)
        .map((row) {
          final pool = payloadPool(row);
          final productRow = pool['product'] is Map
              ? Map<String, dynamic>.from(pool['product'] as Map)
              : pool;
          final product = _product(productRow);
          if (product == null) return null;
          final quantity =
              numberField(pool, const ['quantity', 'qty', 'count'])?.round() ??
              1;
          if (quantity <= 0) return null;
          return CartItem(product: product, quantity: quantity);
        })
        .whereType<CartItem>()
        .toList();
    // The GET /cart envelope also publishes itemCount/subtotal/discount/total
    // with live prices — keep them when present so the UI mirrors the server
    // cart rather than a locally recomputed one.
    final pool = source is Map<String, dynamic>
        ? source
        : const <String, dynamic>{};
    return Cart(
      items: items,
      itemCount: numberField(pool, const [
        'itemCount',
        'totalItems',
        'totalQuantity',
      ])?.round(),
      subtotal: numberField(pool, const [
        'subtotal',
        'subTotal',
        'itemsTotal',
      ]),
      discount: numberField(pool, const [
        'discount',
        'discountTotal',
        'promoDiscount',
      ]),
      total: numberField(pool, const ['total', 'grandTotal', 'totalAmount']),
    );
  }

  /// `deliveryUpdates[]` (orders + tracking) and the older events shapes all
  /// map onto the same timeline row. The server appends updates
  /// chronologically, so the list is flipped newest-first for the timeline.
  List<TrackingTimelineEvent> _timelineEvents(Object? raw) {
    final events = rowsOf(raw).map((e) {
      final ep = payloadPool(e);
      return TrackingTimelineEvent(
        status: stringField(ep, const ['status', 'state']) ?? 'updated',
        message:
            stringField(ep, const ['message', 'description', 'note']) ?? '',
        location: stringField(ep, const ['location', 'hub', 'city']),
        timestamp: dateField(ep, const [
          'timestamp',
          'createdAt',
          'time',
          'date',
        ]),
      );
    }).toList();
    events.sort((a, b) {
      final at = a.timestamp;
      final bt = b.timestamp;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return events;
  }

  DriverLocation? _driverLocationOf(Object? raw) {
    if (raw is! Map) return null;
    final p = payloadPool(asMap(raw));
    final latitude = numberField(p, const ['latitude', 'lat']);
    final longitude = numberField(p, const ['longitude', 'lng', 'lon']);
    if (latitude == null || longitude == null) return null;
    return DriverLocation(
      latitude: latitude,
      longitude: longitude,
      recordedAt: dateField(p, const [
        'recordedAt',
        'timestamp',
        'updatedAt',
        'createdAt',
      ]),
    );
  }

  ShippingAddress? _addressOf(Object? raw) {
    if (raw is! Map) return null;
    final address = ShippingAddress.fromJson(Map<String, dynamic>.from(raw));
    return address.summary.isEmpty && address.fullName.isEmpty ? null : address;
  }
}
