import 'package:equatable/equatable.dart';

import '../../../core/network/api_payload.dart';

/// GET /api/v1/shop/categories — category list from the shop catalog.
class ShopCategory extends Equatable {
  const ShopCategory({
    required this.id,
    required this.name,
    required this.icon,
  });

  final String id;
  final String name;

  /// Material icon key resolved in the UI layer; the API returns a name.
  final String icon;

  @override
  List<Object?> get props => [id, name];
}

/// GET /api/v1/shop/products & /api/v1/shop/products/{id}
class ShopProduct extends Equatable {
  const ShopProduct({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.price,
    required this.currency,
    required this.imageAsset,
    required this.stock,
    required this.rating,
    required this.sold,
    this.oldPrice,
    this.description = '',
    this.isFeatured = false,
    this.images = const [],
    this.brand = '',
    this.partnerName = '',
    this.partnerId,
    this.partnerLocationId,
    this.sku = '',
    this.attributes = const {},
    this.weightKg,
  });

  final String id;
  final String name;
  final String categoryId;

  /// The selling price — `discountPrice` when the product is on sale.
  final double price;

  /// Pre-discount price; null when the product is not on sale.
  final double? oldPrice;
  final String currency;

  /// Primary artwork — a remote URL or a bundled asset path. The widgets pick
  /// the loader from the string, so no reshaping happens upstream.
  final String imageAsset;

  /// Every image the API published (`images[]`), first entry = [imageAsset].
  final List<String> images;
  final String description;
  final int stock;
  final double rating;
  final int sold;
  final bool isFeatured;
  final String brand;

  /// `partnerName` from the spec — the seller shown on the detail page.
  final String partnerName;
  final String? partnerId;
  final String? partnerLocationId;
  final String sku;

  /// Free-form spec attributes (color, storage, size…).
  final Map<String, String> attributes;
  final double? weightKg;

  bool get inStock => stock > 0;

  /// SKU pill on the detail page — prefers the real `sku`, falls back to id.
  String get displaySku => sku.isNotEmpty ? sku : id;

  int get discountPercent => oldPrice == null || oldPrice! <= 0
      ? 0
      : ((1 - price / oldPrice!) * 100).round();

  @override
  List<Object?> get props => [id, name, categoryId, price, oldPrice];
}

/// GET /api/v1/shop/cart — cart with computed totals from the server.
class CartItem extends Equatable {
  const CartItem({required this.product, required this.quantity});

  final ShopProduct product;
  final int quantity;

  double get lineTotal => product.price * quantity;

  @override
  List<Object?> get props => [product.id, quantity];
}

/// `GET /cart` also publishes `itemCount`, `subtotal`, `discount` and `total`
/// at the top level with live prices — when the server supplies them they win
/// over the locally summed line totals, so the UI never recomputes pricing.
class Cart extends Equatable {
  const Cart({
    required this.items,
    int? itemCount,
    double? subtotal,
    double? discount,
    double? total,
  }) : _itemCount = itemCount,
       _subtotal = subtotal,
       _discount = discount,
       _total = total;

  final List<CartItem> items;
  final int? _itemCount;
  final double? _subtotal;
  final double? _discount;
  final double? _total;

  int get itemCount =>
      _itemCount ?? items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal =>
      _subtotal ?? items.fold(0.0, (sum, item) => sum + item.lineTotal);

  /// Promotion discount the server cart applied (0 when absent).
  double get discount => _discount ?? 0;

  /// What the customer pays before delivery fees.
  double get total => _total ?? subtotal - discount;

  CartItem? itemFor(String productId) {
    for (final item in items) {
      if (item.product.id == productId) return item;
    }
    return null;
  }

  @override
  List<Object?> get props => [items];
}

/// Shipping address per the checkout contract — required by
/// `POST /api/v1/shop/checkout`; the profile does not supply one.
class ShippingAddress extends Equatable {
  const ShippingAddress({
    required this.fullName,
    required this.phone,
    required this.addressLine1,
    required this.city,
    required this.region,
    required this.country,
    this.email = '',
    this.addressLine2 = '',
    this.postalCode = '',
    this.deliveryInstructions = '',
    this.latitude,
    this.longitude,
  });

  final String fullName;
  final String phone;
  final String addressLine1;
  final String city;
  final String region;
  final String country;
  final String email;
  final String addressLine2;
  final String postalCode;
  final String deliveryInstructions;

  /// Customer delivery-pin coordinates. The backend requires both at
  /// checkout and uses them with the branch pickup pin to compute the
  /// courier distance — never send one without the other.
  final double? latitude;
  final double? longitude;

  bool get hasDeliveryPin => latitude != null && longitude != null;

  Map<String, dynamic> toJson() => {
    'fullName': fullName,
    'phone': phone,
    'addressLine1': addressLine1,
    'city': city,
    'region': region,
    'country': country,
    if (email.isNotEmpty) 'email': email,
    if (addressLine2.isNotEmpty) 'addressLine2': addressLine2,
    if (postalCode.isNotEmpty) 'postalCode': postalCode,
    if (deliveryInstructions.isNotEmpty)
      'deliveryInstructions': deliveryInstructions,
    if (hasDeliveryPin) 'latitude': latitude, 'longitude': longitude,
  };

  /// The `shippingAddress` object persisted on an order/tracking payload.
  factory ShippingAddress.fromJson(Map<String, dynamic> json) =>
      ShippingAddress(
        fullName: stringField(json, const ['fullName', 'name']) ?? '',
        phone: stringField(json, const ['phone', 'phoneNumber', 'mobile']) ?? '',
        addressLine1:
            stringField(json, const [
              'addressLine1',
              'address',
              'street',
              'line1',
            ]) ??
            '',
        addressLine2:
            stringField(json, const ['addressLine2', 'line2']) ?? '',
        city: stringField(json, const ['city', 'town']) ?? '',
        region: stringField(json, const ['region', 'state']) ?? '',
        country: stringField(json, const ['country']) ?? '',
        email: stringField(json, const ['email']) ?? '',
        postalCode:
            stringField(json, const ['postalCode', 'postal', 'zip']) ?? '',
        deliveryInstructions:
            stringField(json, const [
              'deliveryInstructions',
              'instructions',
              'notes',
            ]) ??
            '',
        latitude: numberField(json, const ['latitude', 'lat']),
        longitude: numberField(json, const ['longitude', 'lng', 'lon']),
      );

  /// Single-line form for order summaries and tracking cards.
  String get summary => [
    addressLine1,
    addressLine2,
    city,
    region,
    postalCode,
    country,
  ].where((part) => part.trim().isNotEmpty).join(', ');

  @override
  List<Object?> get props => [fullName, phone, addressLine1, city];
}

class ShopOrderItem extends Equatable {
  const ShopOrderItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
    this.imageAsset = '',
    this.sku,
    this.partnerId,
    this.partnerName,
    this.partnerLocationId,
    this.listPrice,
    this.discountAmount,
    this.promotionReference,
    this.weightKg,
  });

  final String productId;
  final String name;
  final double price;
  final int quantity;
  final String imageAsset;
  final String? sku;
  final String? partnerId;
  final String? partnerName;
  final String? partnerLocationId;
  final double? listPrice;
  final double? discountAmount;
  final String? promotionReference;
  final double? weightKg;

  double get lineTotal => price * quantity;

  @override
  List<Object?> get props => [
    productId,
    name,
    price,
    quantity,
    sku,
    partnerId,
    partnerLocationId,
  ];
}

/// POST /api/v1/shop/checkout — the pending order the Advansis payment then
/// settles via `shopOrderNumber`. `paymentStatus`/`status` come from the
/// order lifecycle `pending → paid → processing → shipped → delivered`.
class ShopOrder extends Equatable {
  const ShopOrder({
    required this.id,
    required this.reference,
    required this.itemCount,
    required this.total,
    required this.currency,
    required this.placedAt,
    this.paymentStatus = 'pending',
    this.status = 'pending',
    this.items = const [],
    this.shippingAddress,
    this.carrier,
    this.trackingNumber,
    this.subtotal,
    this.discount,
    this.deliveryFee,
    this.paymentMethod,
    this.deliveryUpdates = const [],
  });

  final String id;
  final String reference;
  final int itemCount;
  final double total;
  final String currency;
  final DateTime placedAt;
  final String paymentStatus;
  final String status;
  final List<ShopOrderItem> items;
  final ShippingAddress? shippingAddress;
  final String? carrier;
  final String? trackingNumber;

  /// Server totals from the checkout/order payload — the cart subtotal
  /// before promotions and fees.
  final double? subtotal;
  final double? discount;
  final double? deliveryFee;

  /// `momo` | `card` | `wallet` as recorded at checkout.
  final String? paymentMethod;

  /// The order's `deliveryUpdates[]` timeline (same shape as the tracking
  /// endpoint) when the order payload includes it.
  final List<TrackingTimelineEvent> deliveryUpdates;

  bool get canBeCancelled =>
      status == 'pending' || status == 'processing' || status == 'created';

  @override
  List<Object?> get props => [
    id,
    reference,
    total,
    placedAt,
    status,
    paymentStatus,
  ];
}

class TrackingTimelineEvent extends Equatable {
  const TrackingTimelineEvent({
    required this.status,
    required this.message,
    this.location,
    this.timestamp,
  });

  final String status;
  final String message;
  final String? location;
  final DateTime? timestamp;

  @override
  List<Object?> get props => [status, message, location, timestamp];
}

/// Live driver GPS point pushed by the courier partner after pickup —
/// `lastDriverLocation` on `GET /shop/orders/{id}/tracking`.
class DriverLocation extends Equatable {
  const DriverLocation({
    required this.latitude,
    required this.longitude,
    this.recordedAt,
  });

  final double latitude;
  final double longitude;
  final DateTime? recordedAt;

  /// Coarse "how stale is this fix" label for the tracking card.
  String freshnessLabel([DateTime? now]) {
    final at = recordedAt;
    if (at == null) return '';
    final elapsed = (now ?? DateTime.now()).difference(at);
    if (elapsed.inSeconds < 60) return 'Updated just now';
    if (elapsed.inMinutes < 60) return 'Updated ${elapsed.inMinutes}m ago';
    if (elapsed.inHours < 24) return 'Updated ${elapsed.inHours}h ago';
    return 'Updated ${elapsed.inDays}d ago';
  }

  @override
  List<Object?> get props => [latitude, longitude, recordedAt];
}

class ShopOrderTracking extends Equatable {
  const ShopOrderTracking({
    required this.orderId,
    required this.status,
    this.orderNumber,
    this.carrier,
    this.trackingNumber,
    this.estimatedDeliveryDate,
    this.deliveredAt,
    this.shippingAddress,
    this.lastDriverLocation,
    this.events = const [],
  });

  final String orderId;
  final String status;
  final String? orderNumber;
  final String? carrier;
  final String? trackingNumber;
  final DateTime? estimatedDeliveryDate;
  final DateTime? deliveredAt;
  final ShippingAddress? shippingAddress;

  /// Latest courier driver GPS fix; only populated once the order is
  /// `shipped` and the partner is streaming locations.
  final DriverLocation? lastDriverLocation;
  final List<TrackingTimelineEvent> events;

  bool get isTerminal =>
      status == 'delivered' || status == 'cancelled' || status == 'refunded';

  @override
  List<Object?> get props => [
    orderId,
    status,
    carrier,
    trackingNumber,
    lastDriverLocation,
    events,
  ];
}
