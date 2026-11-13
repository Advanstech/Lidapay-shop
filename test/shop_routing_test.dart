import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/features/dashboard/screens/dashboard_screen.dart';
import 'package:lidapay_app/features/dashboard/widgets/flash_deals_carousel.dart';
import 'package:lidapay_app/features/shell/main_shell.dart';
import 'package:lidapay_app/features/shop/screens/shop_screen.dart';
import 'package:lidapay_app/features/shop/widgets/product_detail_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_app.dart';

void main() {
  testWidgets(
    'tapping flash deal routes to shop and opens product detail sheet',
    (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});
      await pumpMockApp(tester);
      await tester.pumpAndSettle();

      // Login
      await tester.enterText(find.byType(TextFormField).at(0), '0244588584');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use password instead'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'hunter22');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Hello,'), findsOneWidget);

      // Verify Flash deals is present on dashboard
      await tester.scrollUntilVisible(
        find.text('Flash deals'),
        150,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Flash deals'), findsOneWidget);
      expect(find.byType(FlashDealsCarousel), findsOneWidget);

      // Scroll FlashDealsCarousel into view and tap it
      await tester.ensureVisible(find.byType(FlashDealsCarousel));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FlashDealsCarousel));
      await tester.pumpAndSettle();

      // ShopScreen is now open!
      expect(find.byType(ShopScreen), findsOneWidget);

      // And ProductDetailSheet for the deal is opened!
      expect(find.byType(ProductDetailSheet), findsOneWidget);
      expect(find.text('Add to Cart'), findsOneWidget);

      // Close the sheet
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(ProductDetailSheet), findsNothing);
      expect(find.byType(ShopScreen), findsOneWidget);

      // Tap back button on ShopTopBar to return to Dashboard
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);

      // Tap See all next to Flash deals
      await tester.scrollUntilVisible(
        find.text('Flash deals'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      final seeAllFinder = find.descendant(
        of: find.ancestor(
          of: find.text('Flash deals'),
          matching: find.byType(Row),
        ),
        matching: find.text('See all'),
      );
      await tester.ensureVisible(seeAllFinder);
      await tester.pumpAndSettle();
      await tester.tap(seeAllFinder);
      await tester.pumpAndSettle();

      expect(find.byType(ShopScreen), findsOneWidget);

      // Return to dashboard
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // Tap Shop tab in MainDock
      final shopDockFinder = find.descendant(
        of: find.byType(MainDock),
        matching: find.text('Shop'),
      );
      expect(shopDockFinder, findsOneWidget);
      await tester.tap(shopDockFinder);
      await tester.pumpAndSettle();

      expect(find.byType(ShopScreen), findsOneWidget);
    },
  );
}
