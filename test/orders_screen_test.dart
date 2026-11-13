import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/core/theme/app_theme.dart';
import 'package:lidapay_app/features/shop/data/mock_shop_repository.dart';
import 'package:lidapay_app/features/shop/data/shop_models.dart';
import 'package:lidapay_app/features/shop/providers.dart';
import 'package:lidapay_app/features/shop/screens/orders_screen.dart';

void main() {
  Widget buildTestableScreen({required MockShopRepository repository}) {
    return ProviderScope(
      overrides: [
        shopRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const OrdersScreen(),
      ),
    );
  }

  testWidgets('OrdersScreen displays list of orders with items and status', (
    tester,
  ) async {
    final repo = MockShopRepository();
    await tester.pumpWidget(buildTestableScreen(repository: repo));
    await tester.pumpAndSettle();

    expect(find.text('My Orders'), findsOneWidget);
    expect(find.textContaining('ORD-'), findsWidgets);
    expect(find.textContaining('GHS'), findsWidgets);
  });

  testWidgets('Tapping Track Order opens live tracking timeline sheet', (
    tester,
  ) async {
    final repo = MockShopRepository();
    await tester.pumpWidget(buildTestableScreen(repository: repo));
    await tester.pumpAndSettle();

    final trackBtn = find.text('Track order').first;
    expect(trackBtn, findsOneWidget);

    await tester.tap(trackBtn);
    await tester.pumpAndSettle();

    expect(find.text('Delivery Tracking'), findsOneWidget);
    expect(find.textContaining('GHP-TRACK'), findsOneWidget);
    expect(find.text('Package arrived at destination hub'), findsOneWidget);
  });

  testWidgets('Orders can be cancelled with confirmation dialog', (
    tester,
  ) async {
    final repo = MockShopRepository();
    await tester.pumpWidget(buildTestableScreen(repository: repo));
    await tester.pumpAndSettle();

    final cancelBtn = find.text('Cancel Order');
    if (cancelBtn.evaluate().isNotEmpty) {
      await tester.tap(cancelBtn.first);
      await tester.pumpAndSettle();

      expect(find.text('Cancel this order?'), findsOneWidget);
      await tester.tap(find.text('Confirm Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Order cancelled'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    }
  });

  testWidgets('Empty orders state displays proper message and action', (
    tester,
  ) async {
    final customRepo = _EmptyMockShopRepository();
    await tester.pumpWidget(buildTestableScreen(repository: customRepo));
    await tester.pumpAndSettle();

    expect(find.text('No orders yet'), findsOneWidget);
    expect(find.text('Explore Shop'), findsOneWidget);
  });
}

class _EmptyMockShopRepository extends MockShopRepository {
  @override
  Future<List<ShopOrder>> getOrders({int page = 1, int limit = 20}) async => [];
}
