import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/core/deep_links.dart';
import 'package:lidapay_app/core/router/app_router.dart';
import 'package:lidapay_app/core/widgets/app_button.dart';
import 'package:lidapay_app/features/auth/screens/login_screen.dart';
import 'package:lidapay_app/features/dashboard/screens/dashboard_screen.dart';
import 'package:lidapay_app/features/dashboard/widgets/transaction_tile.dart';
import 'package:lidapay_app/features/payments/data/pending_payment.dart';
import 'package:lidapay_app/features/payments/providers.dart';
import 'package:lidapay_app/features/payments/screens/payment_return_screen.dart';
import 'package:lidapay_app/features/services/widgets/service_receipt_screen.dart';
import 'package:lidapay_app/features/splash/screens/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_app.dart';

class _FakeAppLinks implements AppLinks {
  final _controller = StreamController<Uri>.broadcast();

  @override
  Stream<Uri> get uriLinkStream => _controller.stream;

  @override
  Future<Uri?> getInitialLink() async => null;

  void emit(Uri uri) => _controller.add(uri);

  Future<void> dispose() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('cold start shows branded splash, then routes to onboarding', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpMockApp(tester);
    await tester.pump();

    expect(find.text('Lidapay'), findsOneWidget);
    expect(find.text('Money, moving beautifully.'), findsOneWidget);

    // Splash timer + reveal animation resolve into onboarding.
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('onboarding → login → dashboard', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpMockApp(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Onboarding shows on first launch.
    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Login screen — enter phone/email, tap Continue -> 6-digit OTP boxes appear
    // with option to switch to Password.
    expect(find.text('Welcome back'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), '0244588584');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // 6-digit boxes are shown first alongside the Password switch option.
    expect(find.text('Enter 6-Digit Code'), findsOneWidget);
    expect(find.byKey(const ValueKey('otp_box_0')), findsOneWidget);
    expect(find.text('Use password instead'), findsOneWidget);

    // Switch smoothly to Password mode and sign in.
    await tester.tap(find.text('Use password instead'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Enter Password'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'hunter22');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Sign in'));
    // Mock auth latency.
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.textContaining('Hello,'), findsOneWidget);
    expect(find.text('Lidapay Wallet'), findsOneWidget);
    expect(find.text('Services'), findsWidgets); // section header + dock label
    expect(find.text('Flash deals'), findsOneWidget);
    final listFinder = find.byType(CustomScrollView).first;
    await tester.drag(listFinder, const Offset(0, -400));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.drag(listFinder, const Offset(0, -400));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.byType(TransactionRow), findsWidgets);
  });

  testWidgets('6-digit OTP login flow signs in directly from the boxes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});
    await pumpMockApp(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextFormField).at(0), '0244588584');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Enter 6-Digit Code'), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      await tester.enterText(find.byKey(ValueKey('otp_box_$i')), '${i + 1}');
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.textContaining('Hello,'), findsOneWidget);
  });

  testWidgets('API validation error from login is rendered inline', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});
    await pumpMockApp(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextFormField).at(0), '0244588584');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Use password instead'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextFormField).at(0), 'wrongpass');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Incorrect password. Please try again.'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  Future<void> pickCountry(WidgetTester tester, String name) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('register-country-field')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('register-country-field')));
    // The mock catalogue has ~650ms of latency.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.text(name));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
  }

  testWidgets('register wizard: personal account end to end', (tester) async {
    // Roomy viewport so wizard footer buttons are hittable without scroll
    // fighting in tests.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});
    await pumpMockApp(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Step 0 — account type cards.
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Merchant'), findsOneWidget);
    await tester.tap(find.text('Personal'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // Step 1 — details + country picker.
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ama');
    await tester.enterText(fields.at(1), 'Mensah');
    await tester.enterText(fields.at(2), 'ama@example.com');
    await tester.enterText(fields.at(3), '0244123456');
    await pickCountry(tester, 'Ghana');
    await tester.enterText(
      find.byKey(const ValueKey('register-password-input')),
      'hunter22',
    );
    await tester.enterText(
      find.byKey(const ValueKey('register-confirm-password-input')),
      'hunter22',
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('register-confirm-password-input')),
          )
          .controller
          ?.text,
      'hunter22',
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(AppButton, 'Continue'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<AppButton>(find.widgetWithText(AppButton, 'Continue')).onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(AppButton, 'Continue'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Step 2 — confirm + policy gate.
    expect(find.text('Verification email resent'), findsNothing);
    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Create account'))
          .onPressed,
      isNull,
    );

    await tester.scrollUntilVisible(
      find.byType(Checkbox),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(AppButton, 'Create account'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('register wizard: merchant account end to end', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});
    await pumpMockApp(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('Merchant'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Accra Market');
    await tester.enterText(fields.at(1), 'Retail');
    await tester.enterText(fields.at(2), 'shop@example.com');
    await tester.enterText(fields.at(3), '0244123456');
    await pickCountry(tester, 'Ghana');
    await tester.enterText(
      find.byKey(const ValueKey('register-password-input')),
      'hunter22',
    );
    await tester.enterText(
      find.byKey(const ValueKey('register-confirm-password-input')),
      'hunter22',
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('register-confirm-password-input')),
          )
          .controller
          ?.text,
      'hunter22',
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(AppButton, 'Continue'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<AppButton>(find.widgetWithText(AppButton, 'Continue')).onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(AppButton, 'Continue'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('step-confirm')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byType(Checkbox),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(AppButton, 'Register business'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets(
    'lidapay://auth/password-reset-complete routes to LoginScreen with confirmation',
    (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});
      await pumpMockApp(tester);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.byType(LoginScreen), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LoginScreen)),
      );
      final router = container.read(routerProvider);

      // Push ForgotPasswordScreen while LoginScreen stays mounted beneath it.
      router.push(AppRoutes.forgotPassword);
      await tester.pumpAndSettle();
      expect(find.text('Reset password'), findsOneWidget);

      final fakeLinks = _FakeAppLinks();
      addTearDown(fakeLinks.dispose);
      final handler = PaymentDeepLinkHandler(
        links: fakeLinks,
        router: router,
        hasSession: () => false,
      );
      addTearDown(handler.dispose);
      await handler.start();

      // Simulate returning via "Open LidaPay" deep link from browser reset form.
      fakeLinks.emit(Uri.parse('lidapay://auth/password-reset-complete'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(
        find.text('Password updated. Sign in with your new password.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'lidapay://redirect-url routes directly to PaymentReturnScreen receipt instead of restarting at Splash',
    (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});
      await pumpMockApp(tester);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      // Sign in via 6-digit OTP on LoginScreen.
      await tester.enterText(find.byType(TextFormField).at(0), '0244588584');
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      for (var i = 0; i < 6; i++) {
        await tester.enterText(find.byKey(ValueKey('otp_box_$i')), '${i + 1}');
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byType(DashboardScreen), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(DashboardScreen)),
      );
      await container.read(paymentSessionProvider.notifier).beginPayment(
            PendingPayment.ghanaAirtime(
              reference: 'LDP-TEST-1',
              amount: 10,
              recipientNumber: '0244588584',
              networkId: '4',
              saveToLidaValue: false,
              isSelfTopup: false,
              orderDesc: 'Test airtime',
            ),
          );

      // Simulate Android delivering `lidapay://redirect-url?...` into GoRouter.
      final router = container.read(routerProvider);
      router.go('lidapay://redirect-url?orderId=ADV-1&token=saved-token&status=success');
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(PaymentReturnScreen), findsOneWidget);

      // Wait for mock credit latency to settle onto the receipt.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.byType(ServiceReceiptScreen), findsOneWidget);
    },
  );
}
