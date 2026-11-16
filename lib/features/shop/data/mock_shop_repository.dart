import 'shop_models.dart';
import 'shop_repository.dart';

class MockShopRepository implements ShopRepository {
  final _latency = const Duration(milliseconds: 700);

  final List<ShopProduct> _products = const [
    ShopProduct(
      id: 'prod_phone',
      name: 'Nova X5 Smartphone',
      categoryId: 'electronics',
      price: 790,
      oldPrice: 850,
      currency: 'GHS',
      imageAsset: 'assets/images/shop_phone.png',
      images: [
        'assets/images/shop_phone.png',
        'assets/images/shop_earbuds.png',
      ],
      description: '6.6" HD+ display, 128GB storage, 50MP dual camera and a 5000mAh battery. Dual SIM with 4G LTE.',
      stock: 14,
      rating: 4.7,
      sold: 320,
      isFeatured: true,
      brand: 'Nova',
      partnerName: 'Melcom Shopping Centre',
      sku: 'NOV-X5-128',
      attributes: {'Color': 'Midnight Black', 'Storage': '128GB', 'RAM': '6GB'},
      weightKg: 0.19,
    ),
    ShopProduct(
      id: 'prod_earbuds',
      name: 'PulseBuds 4',
      categoryId: 'electronics',
      price: 259,
      oldPrice: 320,
      currency: 'GHS',
      imageAsset: 'assets/images/shop_earbuds.png',
      description: 'True wireless earbuds with active noise cancellation, 32-hour total battery and wireless charging case.',
      stock: 42,
      rating: 4.8,
      sold: 1180,
      isFeatured: true,
    ),
    ShopProduct(
      id: 'prod_speaker',
      name: 'BoomBox Mini Speaker',
      categoryId: 'electronics',
      price: 340,
      currency: 'GHS',
      imageAsset: 'assets/images/shop_speaker.png',
      description: 'Portable Bluetooth speaker with 12W stereo sound, IPX6 splash resistance and 18-hour playtime.',
      stock: 27,
      rating: 4.5,
      sold: 640,
    ),
    ShopProduct(
      id: 'prod_cooker',
      name: 'HomeChef Rice Cooker 1.8L',
      categoryId: 'home',
      price: 420,
      currency: 'GHS',
      imageAsset: 'assets/images/shop_cooker.png',
      description: '1.8L non-stick rice cooker with keep-warm function, steamer tray and cool-touch handles.',
      stock: 19,
      rating: 4.6,
      sold: 455,
    ),
    ShopProduct(
      id: 'prod_sneakers',
      name: 'StrideRunner Sneakers',
      categoryId: 'fashion',
      price: 510,
      oldPrice: 640,
      currency: 'GHS',
      imageAsset: 'assets/images/shop_sneakers.png',
      description: 'Lightweight knit running shoes with cushioned midsole and breathable mesh upper. Unisex, sizes 39–45.',
      stock: 33,
      rating: 4.4,
      sold: 290,
    ),
    ShopProduct(
      id: 'prod_skincare',
      name: 'GlowUp Skincare Trio',
      categoryId: 'beauty',
      price: 285,
      currency: 'GHS',
      imageAsset: 'assets/images/shop_skincare.png',
      description: 'Cleanser, vitamin-C serum and daily moisturizer set. Dermatologist tested, suits all skin types.',
      stock: 51,
      rating: 4.9,
      sold: 860,
    ),
    ShopProduct(
      id: 'prod_grocery',
      name: 'Family Market Bundle',
      categoryId: 'groceries',
      price: 640,
      currency: 'GHS',
      imageAsset: 'assets/images/shop_grocery.png',
      description: 'A two-week staple bundle: rice, oil, tomatoes, gari, sugar, tea and more, delivered to your door.',
      stock: 12,
      rating: 4.3,
      sold: 175,
    ),
    ShopProduct(
      id: 'prod_sim',
      name: '10GB Data Voucher (Telecel)',
      categoryId: 'vouchers',
      price: 49,
      oldPrice: 60,
      currency: 'GHS',
      imageAsset: 'assets/images/shop_sim.png',
      description: 'Instant 10GB Telecel bundle, delivered as a redeemable voucher code straight to your history feed.',
      stock: 999,
      rating: 4.7,
      sold: 2410,
      isFeatured: true,
    ),
  ];

  final List<ShopCategory> _categories = const [
    ShopCategory(id: 'electronics', name: 'Electronics', icon: 'devices'),
    ShopCategory(id: 'home', name: 'Home & Kitchen', icon: 'kitchen'),
    ShopCategory(id: 'fashion', name: 'Fashion', icon: 'checkroom'),
    ShopCategory(id: 'beauty', name: 'Beauty', icon: 'spa'),
    ShopCategory(id: 'groceries', name: 'Groceries', icon: 'cart'),
    ShopCategory(id: 'vouchers', name: 'Data Vouchers', icon: 'sim_card'),
  ];

  final Map<String, int> _cartQuantities = {};

  List<ShopProduct> get _catalog => List.unmodifiable(_products);

  @override
  Future<List<ShopCategory>> getCategories() async {
    await Future<void>.delayed(_latency);
    return List.unmodifiable(_categories);
  }

  @override
  Future<List<ShopProduct>> getProducts({
    String? categoryId,
    String? query,
  }) async {
    await Future<void>.delayed(_latency);
    var result = _catalog;
    if (categoryId != null) {
      result = result.where((p) => p.categoryId == categoryId).toList();
    }
    final q = query?.trim().toLowerCase();
    if (q != null && q.isNotEmpty) {
      result = result
          .where(
            (p) =>
                p.name.toLowerCase().contains(q) ||
                p.description.toLowerCase().contains(q),
          )
          .toList();
    }
    return result;
  }

  @override
  Future<List<ShopProduct>> getFeaturedProducts() async {
    await Future<void>.delayed(_latency);
    return _catalog.where((p) => p.isFeatured).toList();
  }

  @override
  Future<ShopProduct?> getProduct(String id) async {
    await Future<void>.delayed(_latency);
    for (final p in _catalog) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<Cart> getCart() async {
    await Future<void>.delayed(_latency);
    return _buildCart();
  }

  @override
  Future<Cart> addToCart(String productId, {int quantity = 1}) async {
    await Future<void>.delayed(_latency);
    _cartQuantities[productId] = (_cartQuantities[productId] ?? 0) + quantity;
    return _buildCart();
  }

  @override
  Future<Cart> updateQuantity(String productId, int quantity) async {
    await Future<void>.delayed(_latency);
    if (quantity <= 0) {
      _cartQuantities.remove(productId);
    } else {
      _cartQuantities[productId] = quantity;
    }
    return _buildCart();
  }

  @override
  Future<Cart> removeFromCart(String productId) async {
    await Future<void>.delayed(_latency);
    _cartQuantities.remove(productId);
    return _buildCart();
  }

  @override
  Future<Cart> clearCart() async {
    await Future<void>.delayed(_latency);
    _cartQuantities.clear();
    return _buildCart();
  }

  ShopOrder? _lastOrder;

  @override
  Future<ShopOrder> checkout({
    required ShippingAddress shippingAddress,
    String paymentMethod = 'momo',
    double deliveryFee = 0,
    double? deliveryDistanceKm,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final cart = _buildCart();
    if (cart.items.isEmpty) {
      throw StateError('Your cart is empty.');
    }
    final order = ShopOrder(
      id: 'ord_${DateTime.now().millisecondsSinceEpoch}',
      reference:
          'LPS${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}',
      itemCount: cart.itemCount,
      subtotal: cart.subtotal,
      discount: cart.discount,
      deliveryFee: deliveryFee,
      total: cart.total + deliveryFee,
      currency: 'GHS',
      placedAt: DateTime.now(),
      paymentStatus: 'pending',
      status: 'pending',
      paymentMethod: paymentMethod,
      shippingAddress: shippingAddress,
      items: [
        for (final item in cart.items)
          ShopOrderItem(
            productId: item.product.id,
            name: item.product.name,
            price: item.product.price,
            quantity: item.quantity,
            imageAsset: item.product.imageAsset,
            sku: item.product.sku,
            partnerId: item.product.partnerId,
            partnerName: item.product.partnerName,
            partnerLocationId: item.product.partnerLocationId,
            listPrice: item.product.oldPrice,
            weightKg: item.product.weightKg,
          ),
      ],
      deliveryUpdates: [
        TrackingTimelineEvent(
          status: 'order_placed',
          message: 'Order placed — awaiting payment confirmation',
          timestamp: DateTime.now(),
        ),
      ],
    );
    _lastOrder = order;
    _cartQuantities.clear();
    return order;
  }

  @override
  Future<List<ShopOrder>> getOrders({int page = 1, int limit = 20}) async {
    await Future<void>.delayed(_latency);
    final list = <ShopOrder>[];
    if (_lastOrder != null) list.add(_lastOrder!);
    // Pre-populate with realistic mock historical orders if none exists
    if (list.isEmpty) {
      list.add(
        ShopOrder(
          id: 'ord_demo_1',
          reference: 'ORD-22115',
          itemCount: 2,
          total: 1250.00,
          currency: 'GHS',
          placedAt: DateTime.now().subtract(const Duration(days: 2)),
          status: 'shipped',
          paymentStatus: 'paid',
          carrier: 'Ghana Post EMS',
          trackingNumber: 'GHP-TRACK-001',
          items: const [
            ShopOrderItem(
              productId: 'p1',
              name: 'Samsung Galaxy A05',
              price: 1150.00,
              quantity: 1,
            ),
            ShopOrderItem(
              productId: 'p2',
              name: 'Oraimo Fast Charger 33W',
              price: 100.00,
              quantity: 1,
            ),
          ],
        ),
      );
    }
    return list;
  }

  @override
  Future<ShopOrder?> getOrder(String id) async {
    await Future<void>.delayed(_latency);
    if (_lastOrder?.id == id) return _lastOrder;
    final orders = await getOrders();
    for (final o in orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  @override
  Future<ShopOrder?> getOrderByNumber(String orderNumber) async {
    await Future<void>.delayed(_latency);
    final orders = await getOrders();
    for (final o in orders) {
      if (o.reference == orderNumber) return o;
    }
    return null;
  }

  @override
  Future<ShopOrderTracking?> getOrderTracking(String id) async {
    await Future<void>.delayed(_latency);
    final order = await getOrder(id);
    if (order == null) return null;
    final now = DateTime.now();
    return ShopOrderTracking(
      orderId: id,
      status: order.status,
      carrier: order.carrier ?? 'Advansis Logistics',
      trackingNumber: order.trackingNumber ?? 'TRK-${order.reference}',
      events: [
        TrackingTimelineEvent(
          status: 'delivered',
          message: 'Package arrived at destination hub',
          location: 'Accra North Hub',
          timestamp: now.subtract(const Duration(hours: 1)),
        ),
        TrackingTimelineEvent(
          status: 'out_for_delivery',
          message: 'Package handed over to dispatch rider',
          location: 'Accra Distribution Center',
          timestamp: now.subtract(const Duration(hours: 4)),
        ),
        TrackingTimelineEvent(
          status: 'processing',
          message: 'Order verified and packed by merchant',
          location: 'Warehouse Osu',
          timestamp: now.subtract(const Duration(hours: 18)),
        ),
        TrackingTimelineEvent(
          status: 'placed',
          message: 'Order placed & payment settled via Mobile Money',
          location: 'LidaPay Online',
          timestamp: order.placedAt,
        ),
      ],
      lastDriverLocation: order.status == 'shipped'
          ? DriverLocation(
              latitude: 5.6037,
              longitude: -0.187,
              recordedAt: now.subtract(const Duration(seconds: 12)),
            )
          : null,
    );
  }

  @override
  Future<ShopOrder> cancelOrder(String id, {String? reason}) async {
    await Future<void>.delayed(_latency);
    final order = await getOrder(id);
    if (order == null) throw StateError('Order not found');
    final cancelled = ShopOrder(
      id: order.id,
      reference: order.reference,
      itemCount: order.itemCount,
      total: order.total,
      currency: order.currency,
      placedAt: order.placedAt,
      status: 'cancelled',
      paymentStatus: order.paymentStatus,
      items: order.items,
      shippingAddress: order.shippingAddress,
    );
    if (_lastOrder?.id == id) _lastOrder = cancelled;
    return cancelled;
  }

  Cart _buildCart() {
    final items = <CartItem>[
      for (final entry in _cartQuantities.entries)
        CartItem(
          product: _products.firstWhere((p) => p.id == entry.key),
          quantity: entry.value,
        ),
    ];
    return Cart(items: items);
  }
}
