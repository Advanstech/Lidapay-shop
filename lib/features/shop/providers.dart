import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/network/token_store.dart';
import '../auth/providers.dart';
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
///
/// Scoped to the active user id so logging out or switching accounts never
/// leaks the previous session's cart.
final cartProvider = StateNotifierProvider<CartController, AsyncValue<Cart>>((
  ref,
) {
  final userId = ref.watch(authSessionProvider.select((s) => s?.user.id));
  return CartController(
    ref.watch(shopRepositoryProvider),
    autoLoad: userId != null && userId.isNotEmpty,
  );
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

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repository.getCart());
  }

  /// Mutations keep the current cart on screen while the call runs —
  /// `AsyncLoading.copyWithPrevious` flips `isRefreshing` so buttons and
  /// quantity steppers disable/animate without skeleton-flashing.
  Future<void> _mutate(Future<Cart> Function() call) async {
    state = const AsyncLoading<Cart>().copyWithPrevious(state);
    state = await AsyncValue.guard(call);
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
  Future<ShopOrder?> checkout(
    ShippingAddress address, {
    String paymentMethod = 'momo',
    double? deliveryDistanceKm,
  }) async {
    try {
      final order = await _repository.checkout(
        shippingAddress: address,
        paymentMethod: paymentMethod,
        deliveryDistanceKm: deliveryDistanceKm,
      );
      state = AsyncData(await _repository.getCart());
      return order;
    } catch (_) {
      return null;
    }
  }
}
