import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/network/token_store.dart';
import '../auth/providers.dart';
import '../payments/data/pending_payment.dart';
import 'data/shop_models.dart';
import 'data/shop_repository.dart';
import 'data/remote_shop_repository.dart';

/// One-line swap point between the mock backend and the live shop API.
final shopRepositoryProvider = Provider<ShopRepository>((ref) {
  return RemoteShopRepository(ref.watch(apiClientProvider));
});

/// Browse filters; both feed into [shopProductsProvider].
final shopSearchQueryProvider = StateProvider<String>((ref) => '');

/// Selected category id, or null for the All chip.
final shopCategoryProvider = StateProvider<String?>((ref) => null);

final shopCategoriesProvider = FutureProvider<List<ShopCategory>>((ref) {
  return ref.watch(shopRepositoryProvider).getCategories();
});

final shopProductsProvider = FutureProvider<List<ShopProduct>>((ref) {
  final query = ref.watch(shopSearchQueryProvider);
  final category = ref.watch(shopCategoryProvider);
  return ref
      .watch(shopRepositoryProvider)
      .getProducts(categoryId: category, query: query);
});

final shopFeaturedProvider = FutureProvider<List<ShopProduct>>((ref) {
  return ref.watch(shopRepositoryProvider).getFeaturedProducts();
});

/// Cart state is mutated by [CartController]; every repo call re-reads the
/// server-shaped Cart so the UI never computes totals locally.
final cartProvider = StateNotifierProvider<CartController, AsyncValue<Cart>>((
  ref,
) {
  return CartController(ref.watch(shopRepositoryProvider));
});

/// The shop API publishes no favourite endpoint, so a loved product is a
/// device-level selection — the same shape as read notifications: persisted
/// per user, restored on launch, and shared by every surface that shows a
/// heart (the browse card and the detail sheet) so the two can never disagree.
final lovedProductsProvider =
    StateNotifierProvider<LovedProductsNotifier, Set<String>>((ref) {
      // Rebuild on session change so one account never inherits another's list.
      final userId = ref.watch(authSessionProvider)?.user.id ?? 'anon';
      return LovedProductsNotifier(ref.watch(sharedPrefsProvider), userId);
    });

class LovedProductsNotifier extends StateNotifier<Set<String>> {
  LovedProductsNotifier(this._prefs, this._userId)
    : super(_load(_prefs, _userId));

  final SharedPreferences _prefs;
  final String _userId;

  static String _key(String userId) => 'lidapay.loved_products.$userId';

  static Set<String> _load(SharedPreferences prefs, String userId) =>
      (prefs.getStringList(_key(userId)) ?? const <String>[]).toSet();

  bool isLoved(String productId) => state.contains(productId);

  /// Flips the selection and returns the resulting state, so the caller can
  /// word its confirmation without re-reading the notifier.
  Future<bool> toggle(String productId) async {
    final id = productId.trim();
    if (id.isEmpty) return false;
    final loved = !state.contains(id);
    state = loved ? {...state, id} : ({...state}..remove(id));
    await _prefs.setStringList(_key(_userId), state.toList(growable: false));
    return loved;
  }
}

/// Most recent successful checkout, consumed by the success screen.
final lastOrderProvider = StateProvider<ShopOrder?>((ref) => null);

/// Product or flash deal deep-linked into the Shop tab.
final pendingShopProductProvider = StateProvider<ShopProduct?>((ref) => null);

/// User's orders list (paginated, auto-disposing for fresh state)
final userOrdersProvider = FutureProvider.autoDispose<List<ShopOrder>>((ref) {
  return ref.watch(shopRepositoryProvider).getOrders();
});

/// Paginated orders state for the My Orders screen. Each page fetch asks the
/// server for `pageSize + 1` rows — the extra row is the has-more sentinel,
/// so an exactly-full final page doesn't produce a phantom next page.
class OrdersListState extends Equatable {
  const OrdersListState({
    this.items = const [],
    this.hasMore = false,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<ShopOrder> items;
  final bool hasMore;
  final bool loadingMore;
  final Object? loadMoreError;

  @override
  List<Object?> get props => [items, hasMore, loadingMore, loadMoreError];
}

class OrdersController extends StateNotifier<AsyncValue<OrdersListState>> {
  OrdersController(this._repo) : super(const AsyncLoading()) {
    load();
  }

  static const _pageSize = 15;

  final ShopRepository _repo;
  int _page = 0;
  int _generation = 0;

  Future<void> load() async {
    final generation = ++_generation;
    state = const AsyncLoading();
    final next = await AsyncValue.guard(
      () => _repo.getOrders(page: 1, limit: _pageSize + 1),
    );
    if (!mounted || generation != _generation) return;
    _page = 1;
    state = next.whenData(
      (rows) => OrdersListState(items: rows, hasMore: rows.length > _pageSize),
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(
      OrdersListState(items: current.items, hasMore: true, loadingMore: true),
    );
    final next = await AsyncValue.guard(
      () => _repo.getOrders(page: _page + 1, limit: _pageSize + 1),
    );
    if (!mounted || generation != _generation) return;
    state = next.when(
      data: (rows) {
        _page += 1;
        return AsyncData(
          OrdersListState(
            items: {
              for (final order in [...current.items, ...rows]) order.id: order,
            }.values.toList(),
            hasMore: rows.length > _pageSize,
          ),
        );
      },
      error: (error, _) => AsyncData(
        OrdersListState(
          items: current.items,
          hasMore: true,
          loadMoreError: error,
        ),
      ),
      loading: () => state,
    );
  }
}

final ordersControllerProvider =
    StateNotifierProvider<OrdersController, AsyncValue<OrdersListState>>((ref) {
      return OrdersController(ref.watch(shopRepositoryProvider));
    });

/// Live delivery tracking info for a specific order.
///
/// Polls `GET /shop/orders/{id}/tracking` every 8s while the order detail
/// sheet is open so courier events and the driver GPS pin stay fresh. The
/// provider is `autoDispose`, so closing the sheet stops polling; polling
/// also stops once the order reaches a terminal status. Transient fetch
/// failures keep the last good payload instead of flickering the timeline.
final orderTrackingProvider = StreamProvider.autoDispose
    .family<ShopOrderTracking?, String>((ref, orderId) async* {
      final repository = ref.watch(shopRepositoryProvider);
      var disposed = false;
      Timer? pollTimer;
      Completer<void>? wake;
      ref.onDispose(() {
        disposed = true;
        pollTimer?.cancel();
        if (wake != null && !wake.isCompleted) wake.complete();
      });

      ShopOrderTracking? last;
      var firstPoll = true;
      while (!disposed) {
        final tracking = await repository.getOrderTracking(orderId);
        if (tracking != null) {
          last = tracking;
          yield tracking;
        } else if (firstPoll) {
          yield null;
        }
        firstPoll = false;

        if ((tracking ?? last)?.isTerminal ?? false) return;

        wake = Completer<void>();
        pollTimer = Timer(const Duration(seconds: 8), () => wake?.complete());
        await wake.future;
        wake = null;
        pollTimer = null;
      }
    });

class CartController extends StateNotifier<AsyncValue<Cart>> {
  CartController(this._repository, {bool autoLoad = true})
    : super(
        autoLoad
            ? const AsyncLoading()
            : const AsyncData(Cart(items: <CartItem>[])),
      ) {
    if (autoLoad) {
      load();
    }
  }

  final ShopRepository _repository;

  /// The idempotency reference of the current checkout attempt — kept across
  /// a failed attempt so a retry reuses it, and cleared when the cart
  /// changes or an order is placed.
  String? _checkoutReference;

  Future<void> load() async {
    state = const AsyncLoading();
    final next = await AsyncValue.guard(() => _repository.getCart());
    if (!mounted) return;
    state = next;
  }

  /// Mutations keep the current cart on screen while the call runs —
  /// `AsyncLoading.copyWithPrevious` flips `isRefreshing` so buttons and
  /// quantity steppers disable/animate without skeleton-flashing.
  Future<void> _mutate(Future<Cart> Function() call) async {
    // A changed cart is a different purchase — the checkout reference must
    // not be reused for it.
    _checkoutReference = null;
    state = const AsyncLoading<Cart>().copyWithPrevious(state);
    final next = await AsyncValue.guard(call);
    if (!mounted) return;
    state = next;
  }

  Future<void> add(ShopProduct product, {int quantity = 1}) =>
      _mutate(() => _repository.addToCart(product.id, quantity: quantity));

  /// The backend rejects quantity < 1 — decrementing at 1 removes the line.
  Future<void> setQuantity(ShopProduct product, int quantity) => quantity < 1
      ? remove(product)
      : _mutate(() => _repository.updateQuantity(product.id, quantity));

  Future<void> remove(ShopProduct product) =>
      _mutate(() => _repository.removeFromCart(product.id));

  Future<void> clear() => _mutate(_repository.clearCart);

  /// Places the order and refreshes the (now empty) cart. Returns the placed
  /// order, or null on failure — the previous cart state is preserved so the
  /// caller can surface the error and let the user retry.
  ///
  /// When the request fails the order may still have been created (the
  /// backend clears the cart when it does), so the attempt is reconciled
  /// before reporting a failure: a timed-out checkout must never become two
  /// orders.
  Future<ShopOrder?> checkout(
    ShippingAddress address, {
    String paymentMethod = 'momo',
    double? deliveryDistanceKm,
    String? clientReference,
  }) async {
    // The same attempt keeps the same idempotency reference, so a retry
    // after a timeout cannot create a second order.
    final reference = clientReference ?? _checkoutReference ?? newClientReference();
    _checkoutReference = reference;
    try {
      final order = await _repository.checkout(
        shippingAddress: address,
        paymentMethod: paymentMethod,
        deliveryDistanceKm: deliveryDistanceKm,
        clientReference: reference,
      );
      _checkoutReference = null;
      final cart = await _repository.getCart();
      if (mounted) state = AsyncData(cart);
      return order;
    } catch (_) {
      final recovered = await _recoverCreatedOrder();
      if (recovered != null) {
        _checkoutReference = null;
        final cart = await _repository.getCart();
        if (mounted) state = AsyncData(cart);
        return recovered;
      }
      return null;
    }
  }

  /// Finds the order a failed checkout may already have created. The backend
  /// empties the server cart when an order is placed, so an empty cart plus
  /// a fresh unpaid order means the order exists and only the response was
  /// lost.
  Future<ShopOrder?> _recoverCreatedOrder() async {
    try {
      final cart = await _repository.getCart();
      if (cart.items.isNotEmpty) return null;
      final orders = await _repository.getOrders(page: 1, limit: 20);
      final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
      for (final order in orders) {
        if (order.placedAt.isAfter(cutoff) &&
            order.paymentStatus != 'paid' &&
            order.paymentStatus != 'success') {
          return order;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
