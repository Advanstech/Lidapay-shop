import 'shop_models.dart';

abstract class ShopRepository {
  /// GET /api/v1/shop/categories
  Future<List<ShopCategory>> getCategories();

  /// GET /api/v1/shop/products — supports pagination, search and filters
  /// (category_id, min/max price, sort) per the spec.
  Future<List<ShopProduct>> getProducts({String? categoryId, String? query});

  /// GET /api/v1/shop/products/featured — curated row for the browse screen.
  Future<List<ShopProduct>> getFeaturedProducts();

  /// GET /api/v1/shop/products/{id}
  Future<ShopProduct?> getProduct(String id);

  /// GET /api/v1/shop/cart
  Future<Cart> getCart();

  /// POST /api/v1/shop/cart/add
  Future<Cart> addToCart(String productId, {int quantity = 1});

  /// PUT /api/v1/shop/cart/update
  Future<Cart> updateQuantity(String productId, int quantity);

  /// POST /api/v1/shop/cart/remove
  Future<Cart> removeFromCart(String productId);

  /// DELETE /api/v1/shop/cart/clear
  Future<Cart> clearCart();

  /// POST /api/v1/shop/checkout — creates a pending order from the server
  /// cart and calculates the server-side `deliveryFee` and `total`.
  /// The mobile client must not send a client-computed delivery fee.
  ///
  /// [clientReference] is the idempotency key for this checkout attempt —
  /// the same reference must be reused when the same attempt is retried so
  /// the backend returns the same order instead of creating a second one.
  Future<ShopOrder> checkout({
    required ShippingAddress shippingAddress,
    String paymentMethod = 'momo',
    double deliveryFee = 0,
    double? deliveryDistanceKm,
    String? clientReference,
  });

  /// GET /api/v1/shop/orders — list current user's orders (paginated).
  Future<List<ShopOrder>> getOrders({int page = 1, int limit = 20});

  /// GET /api/v1/shop/orders/{id} — refreshed order state after payment.
  Future<ShopOrder?> getOrder(String id);

  /// GET /api/v1/shop/orders/number/{orderNumber} — public lookup by the
  /// shareable `LPS…` order number.
  Future<ShopOrder?> getOrderByNumber(String orderNumber);

  /// GET /api/v1/shop/orders/{id}/tracking — delivery timeline & status.
  Future<ShopOrderTracking?> getOrderTracking(String id);

  /// POST /api/v1/shop/orders/{id}/cancel — cancel a pending order.
  Future<ShopOrder> cancelOrder(String id, {String? reason});
}
