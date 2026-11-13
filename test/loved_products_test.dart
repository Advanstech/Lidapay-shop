import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/features/dashboard/widgets/flash_deals_carousel.dart';
import 'package:lidapay_app/features/shop/providers.dart';
import 'package:lidapay_app/features/shop/widgets/product_detail_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_app.dart';

const _filled = Icons.favorite_rounded;
const _empty = Icons.favorite_border_rounded;

Future<void> _login(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});
  await pumpMockApp(tester);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));

  await tester.enterText(find.byType(TextFormField).at(0), '0244588584');
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  await tester.tap(find.text('Use password instead'));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  await tester.enterText(find.byType(TextFormField).at(0), 'hunter22');
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  await tester.tap(find.text('Sign in'));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));

  expect(find.textContaining('Hello,'), findsOneWidget);
}

void main() {
  group('LovedProductsNotifier', () {
    test('toggles, persists per user and restores on launch', () async {
      SharedPreferences.setMockInitialValues({
        'lidapay.loved_products.usr_a': ['prod_phone'],
      });
      final prefs = await SharedPreferences.getInstance();

      final forA = LovedProductsNotifier(prefs, 'usr_a');
      expect(forA.isLoved('prod_phone'), isTrue);

      // Toggling an already-loved product removes it and rewrites storage.
      expect(await forA.toggle('prod_phone'), isFalse);
      expect(forA.isLoved('prod_phone'), isFalse);
      expect(prefs.getStringList('lidapay.loved_products.usr_a'), isEmpty);

      expect(await forA.toggle('prod_skincare'), isTrue);
      expect(prefs.getStringList('lidapay.loved_products.usr_a'), [
        'prod_skincare',
      ]);

      // A relaunch (new notifier, same prefs) sees the stored selection...
      expect(
        LovedProductsNotifier(prefs, 'usr_a').isLoved('prod_skincare'),
        true,
      );
      // ...and another account never inherits it.
      expect(
        LovedProductsNotifier(prefs, 'usr_b').isLoved('prod_skincare'),
        false,
      );
    });

    test('ignores blank ids so a malformed product cannot be stored', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = LovedProductsNotifier(prefs, 'usr_a');

      expect(await notifier.toggle('   '), isFalse);
      expect(notifier.state, isEmpty);
    });
  });

  testWidgets('heart on the sheet and on the browse card are one selection', (
    tester,
  ) async {
    await _login(tester);

    // The flash-deal carousel is the app's own route into a product sheet.
    await tester.scrollUntilVisible(
      find.text('Flash deals'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byType(FlashDealsCarousel));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FlashDealsCarousel));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.byType(ProductDetailSheet), findsOneWidget);
    final productId = tester
        .widget<ProductDetailSheet>(find.byType(ProductDetailSheet))
        .product
        .id;

    // Nothing is loved yet, so no filled heart is painted anywhere.
    expect(find.byIcon(_filled), findsNothing);
    expect(find.byIcon(_empty), findsWidgets);

    final sheetHeart = find.descendant(
      of: find.byType(ProductDetailSheet),
      matching: find.byIcon(_empty),
    );
    expect(sheetHeart, findsOneWidget);

    await tester.tap(sheetHeart);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Selected: the sheet fills the heart and confirms.
    expect(
      find.descendant(
        of: find.byType(ProductDetailSheet),
        matching: find.byIcon(_filled),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('saved to loved items'), findsOneWidget);

    // Let the snack bar expire, then close the sheet.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ProductDetailSheet),
        matching: find.byIcon(Icons.chevron_left_rounded),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.byType(ProductDetailSheet), findsNothing);

    // It is on disk, under this account.
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getKeys().firstWhere(
      (k) => k.startsWith('lidapay.loved_products.'),
    );
    expect(prefs.getStringList(key), contains(productId));

    // Re-opening the same product finds the heart still filled — the state
    // came back from storage, not from a flag that dies with the sheet.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await tester.ensureVisible(find.byType(FlashDealsCarousel));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FlashDealsCarousel));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.byType(ProductDetailSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ProductDetailSheet),
        matching: find.byIcon(_filled),
      ),
      findsOneWidget,
    );

    // Drain the sheet's best-effort hydrate call so no timer outlives the test.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}
