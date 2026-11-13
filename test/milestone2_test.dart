import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/core/widgets/app_button.dart';
import 'package:lidapay_app/features/shell/main_shell.dart';
import 'package:lidapay_app/features/shop/widgets/delivery_pin_screen.dart';
import 'package:lidapay_app/features/shop/widgets/product_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_app.dart';

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

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(MainDock), matching: find.text(label)),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('shop: browse → product sheet → cart → checkout success', (
    tester,
  ) async {
    await _login(tester);
    await _openTab(tester, 'Shop');

    // Catalog loads (mock latency) with featured row, chips and grid.
    expect(find.text('Featured'), findsOneWidget);
    expect(find.text('Electronics'), findsOneWidget);

    // The full-grid header sits just below the fold in the compact test
    // viewport, so nudge the catalog to bring it into the build window.
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -250),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('All Products'), findsOneWidget);
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 250),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Open the product detail sheet. The tall hero carousel pushes the
    // featured row near the fold, so bring the card fully into view first.
    await tester.ensureVisible(find.byType(ProductCard).first);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.byType(ProductCard).first);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(
      find.textContaining('6.6" HD+ display'),
      findsOneWidget,
    ); // description start
    await tester.ensureVisible(find.widgetWithText(AppButton, 'Add to Cart'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(AppButton, 'Add to Cart'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Cart badge on the app bar.
    expect(find.text('1'), findsWidgets);

    // Open the cart and check out.
    await tester.tap(find.byIcon(Icons.shopping_cart_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('My Cart'), findsOneWidget);
    expect(find.text('Nova X5 Smartphone'), findsOneWidget);

    await tester.tap(find.textContaining('Pay ·'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // The contract requires a complete delivery address before checkout —
    // the sheet opens first, prefilled from the KYC profile.
    expect(find.text('Delivery Address'), findsOneWidget);
    final addressFields = find.byType(TextFormField);
    await tester.enterText(addressFields.at(2), '12 Osu Avenue');
    await tester.enterText(addressFields.at(4), 'Accra');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // The checkout contract requires a delivery pin — without a Maps key
    // the picker falls back to manual coordinate entry.
    await tester.ensureVisible(find.text('Delivery pin on map'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Delivery pin on map'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    final pinFields = find.descendant(
      of: find.byType(DeliveryPinPickerScreen),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(pinFields.at(0), '5.6037');
    await tester.enterText(pinFields.at(1), '-0.187');
    await tester.tap(find.text('Use these coordinates'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Confirm pin'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    await tester.ensureVisible(find.text('Continue to Payment'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Continue to Payment'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // GTPay debitwallet is still on GTBank's test bed, so the shop sheet
    // offers the ExpressPay card rail only.
    expect(find.textContaining('Send Prompt'), findsNothing);
    expect(find.textContaining('Continue to Card'), findsOneWidget);
    await tester.tap(find.textContaining('Continue to Card'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    // The hosted checkout opened; the awaiting panel's recheck drives the
    // saved-token verification to completion.
    await tester.tap(find.textContaining("I've paid"));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(find.text('Payment Confirmed!'), findsOneWidget);
    expect(find.textContaining('LPS'), findsWidgets);
  });

  testWidgets('services: Airtime and Lida Value open real flows', (
    tester,
  ) async {
    await _login(tester);
    await _openTab(tester, 'Services');

    expect(find.text('All services, one wallet'), findsOneWidget);
    expect(find.text('Airtime'), findsOneWidget);
    expect(find.text('Lida Value'), findsOneWidget);

    await tester.tap(find.text('Buy Airtime'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Country-first flow — the profile country is auto-selected.
    expect(find.text('Buy Airtime'), findsOneWidget);
    expect(find.text('Choose the country for airtime topup'), findsOneWidget);
    await tester.tap(find.text('Ghana').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Legacy order: the country pick lands on the phone step — detection
    // answers the Network position inline, not on a selection screen.
    expect(find.text('Enter Phone Number'), findsOneWidget);
    expect(find.text('Select Network'), findsNothing);

    // Tap "Use My Number" to run detection on profile number
    await tester.tap(find.textContaining('Use My Number').last);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Confirm Operating Network'), findsOneWidget);
    await tester.tap(find.text('MTN').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Recipient number'), findsOneWidget);
    expect(find.textContaining('MTN Ghana detected'), findsOneWidget);
    expect(find.text('Quick Amounts'), findsNothing);
    expect(find.text('Save to Lida Value'), findsNothing);

    // Amount choices and delivery options live on the next step.
    await tester.tap(find.text('NEXT').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Quick Amounts'), findsOneWidget);
    expect(find.text('Save to Lida Value'), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('GH₵ 10'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('NEXT').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.textContaining('10.00'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.ensureVisible(find.text('Lida Value'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Lida Value'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Available value'), findsOneWidget);
  });

  testWidgets('history: filter chips narrow the ledger', (tester) async {
    await _login(tester);
    await _openTab(tester, 'History');

    // First page of the ledger.
    expect(find.text('MTN airtime to Ama'), findsOneWidget);
    expect(find.text('AT airtime — Mama'), findsNothing);

    await tester.tap(find.text('Data'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Only data transactions remain.
    expect(find.text('Telecel 5GB bundle'), findsOneWidget);
    expect(find.text('MTN airtime to Ama'), findsNothing);

    // Back to everything.
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('MTN airtime to Ama'), findsOneWidget);
  });

  testWidgets('profile: theme toggle switches app themeMode and persists', (
    tester,
  ) async {
    await _login(tester);
    await _openTab(tester, 'Profile');

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Theme Mode'), findsOneWidget);

    // The floating dock overlays the bottom of the viewport — scroll the
    // theme control above it before tapping.
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
  });

  testWidgets('profile: edit details and save through the API', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _login(tester);
    await _openTab(tester, 'Profile');

    await tester.scrollUntilVisible(
      find.text('Profile & KYC'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Profile & KYC'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Account verification'), findsOneWidget);
    expect(find.text('Personal details'), findsOneWidget);
    expect(find.text('Not verified'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ama');
    await tester.enterText(fields.at(1), 'Owusu');

    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.widgetWithText(AppButton, 'Save changes'));
    await tester.tap(find.widgetWithText(AppButton, 'Save changes'));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Profile & KYC address updated.'), findsOneWidget);

    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 1000),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Ama Owusu'), findsOneWidget);
  });
}
