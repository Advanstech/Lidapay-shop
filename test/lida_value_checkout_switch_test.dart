import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/features/services/data/mock_services_repository.dart';
import 'package:lidapay_app/features/services/data/service_models.dart';
import 'package:lidapay_app/features/services/widgets/lida_value_checkout_switch.dart';
import 'package:lidapay_app/features/shell/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_app.dart';

Future<void> _login(
  WidgetTester tester, {
  MockServicesRepository? services,
}) async {
  SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});
  await pumpMockApp(tester, services: services);
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

/// A wallet that cannot cover any real top-up, which is the only situation
/// that offers the switch away from Lida Value funding.
class _LowBalanceRepository extends MockServicesRepository {
  @override
  Future<LidaValueWallet> getLidaValueWallet() async =>
      const LidaValueWallet(balance: 2, pending: 0, history: []);
}

Widget _dialogHost(void Function(BuildContext) onPressed) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => onPressed(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'switch dialog explains the new charge rail and can be declined',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        _dialogHost(
          (context) async => result = await confirmStandardCheckoutSwitch(
            context,
            serviceLabel: 'airtime',
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Switch to mobile money or card?'), findsOneWidget);
      expect(find.textContaining('Advansis Pay'), findsOneWidget);
      expect(find.textContaining('Lida Value wallet'), findsOneWidget);
      // Declining is the ordinary cancel, not a bespoke opt-out.
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    },
  );

  testWidgets('switch dialog reports the confirmed switch', (tester) async {
    bool? result;
    await tester.pumpWidget(
      _dialogHost(
        (context) async => result = await confirmStandardCheckoutSwitch(
          context,
          serviceLabel: 'data',
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch payment'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('restore dialog reports the wallet balance and can be declined', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      _dialogHost(
        (context) async => result = await confirmLidaValueRestore(
          context,
          serviceLabel: 'airtime',
          balanceLabel: '2.00 LV',
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Switch back to Lida Value?'), findsOneWidget);
    expect(find.textContaining('2.00 LV available'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use Lida Value'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('SEND shortfall asks before leaving the Lida Value wallet', (
    tester,
  ) async {
    await _login(tester, services: _LowBalanceRepository());
    await _openTab(tester, 'Services');

    // Lida Value lives below the fold in the "All Services" section.
    final lidaValue = find.text('Lida Value');
    await tester.ensureVisible(lidaValue);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(lidaValue);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    // SEND is a Lida Value menu action — the wizard it opens is wallet-funded.
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await tester.tap(find.text('Airtime'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    await tester.tap(find.text('Ghana').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Legacy order: the country pick lands on the phone step — detection
    // answers the Network position inline, not on a selection screen.
    expect(find.text('Enter Phone Number'), findsOneWidget);
    expect(find.text('Select Network'), findsNothing);

    await tester.tap(find.textContaining('Use My Number').last);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('MTN').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('NEXT').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('GH₵ 10'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('NEXT').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // 10.00 against a 2.00 balance: the wallet cannot cover it.
    expect(find.text('Sending with Lida Value'), findsOneWidget);
    expect(find.text('Pay another way'), findsOneWidget);

    await tester.tap(find.text('Pay another way'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Switch to mobile money or card?'), findsOneWidget);

    await tester.tap(find.text('Switch payment'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Funding moved to the standard checkout: no wallet card, card/MoMo rail.
    expect(find.text('Sending with Lida Value'), findsNothing);
    expect(find.text('MoMo or Card · choose next'), findsOneWidget);

    // The detour is reversible, and cancelling it leaves funding untouched.
    await tester.tap(find.text('Pay from Lida Value instead'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Switch back to Lida Value?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('MoMo or Card · choose next'), findsOneWidget);

    await tester.tap(find.text('Pay from Lida Value instead'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Use Lida Value'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Back on the wallet, so the shortfall card returns.
    expect(find.text('Sending with Lida Value'), findsOneWidget);
    expect(find.text('Pay another way'), findsOneWidget);
  });
}
