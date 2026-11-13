import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/features/services/data/mock_services_repository.dart';
import 'package:lidapay_app/features/services/data/service_models.dart';
import 'package:lidapay_app/features/services/data/services_repository.dart';
import 'package:lidapay_app/features/shell/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_app.dart';

Future<void> _login(WidgetTester tester, {ServicesRepository? services}) async {
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

/// Opens a service tile from the hub. The tile can sit below the fold in the
/// compact test viewport, so bring it into view first.
Future<void> _openService(WidgetTester tester, String title) async {
  final tile = find.text(title);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  await tester.tap(tile);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

/// Picks a destination from the country step by filtering the search box —
/// the live list is long, so a bare tap can land off-screen.
Future<void> _pickCountry(WidgetTester tester, String name) async {
  await tester.enterText(find.byType(TextField).first, name);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

/// Lets the mock's 650 ms catalogue/detection latency settle.
Future<void> _settleLatency(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

/// Reloadly data operators arrive with their fixed-price plans attached; the
/// stock mock ships none, so this variant exercises the plan grid.
class _PlanCatalogueRepository extends MockServicesRepository {
  @override
  Future<List<ServiceOption>> getInternationalDataOperators(
    String countryCode,
  ) async {
    if (countryCode.toUpperCase() != 'NG') {
      return super.getInternationalDataOperators(countryCode);
    }
    return const [
      ServiceOption(
        id: '341',
        name: 'MTN Nigeria',
        meta: 'Reloadly data',
        bundles: [
          DataBundle(
            id: 'NG_MTN_1GB',
            name: '1GB Monthly',
            price: 8,
            dataAmount: '1GB',
          ),
        ],
      ),
      ServiceOption(
        id: '344',
        name: 'Glo Nigeria',
        meta: 'Reloadly data',
        bundles: [
          // Priced above the auto-detected MTN ceiling (max 100) so a chosen
          // plan would be rejected if the range gate applied to plans.
          DataBundle(
            id: 'NG_GLO_30GB',
            name: '30GB Monthly',
            price: 150,
            dataAmount: '30GB',
          ),
        ],
      ),
    ];
  }
}

/// Fails the international operator lookup the way an unreachable Reloadly
/// route does in production.
class _BrokenOperatorCatalogue extends MockServicesRepository {
  @override
  Future<List<ServiceOption>> getInternationalOperators(
    String countryCode,
  ) async {
    throw Exception('operator catalogue unavailable');
  }
}

/// Same outage on the data route.
class _BrokenDataCatalogue extends MockServicesRepository {
  @override
  Future<List<ServiceOption>> getInternationalDataOperators(
    String countryCode,
  ) async {
    throw Exception('data operator catalogue unavailable');
  }
}

void main() {
  testWidgets('airtime: a live-only country resolves its dial code on pick', (
    tester,
  ) async {
    await _login(tester);
    await _openTab(tester, 'Services');
    await tester.tap(find.text('Buy Airtime'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Choose the country for airtime topup'), findsOneWidget);

    // Togo exists only in the live `reloadly/country-list`, which carries no
    // calling codes — it must be resolved through `find-country-by-code`.
    await _pickCountry(tester, 'Togo');
    await _settleLatency(tester);

    // Legacy order: the country pick lands on the phone step — the network
    // answers itself by detection instead of a standalone selection screen.
    expect(find.text('Enter Phone Number'), findsOneWidget);

    // Without the lazy resolve the dial chip falls back to the ISO code and
    // the typed number never expands to a valid MSISDN.
    expect(find.text('+228'), findsOneWidget);
  });

  testWidgets('airtime: operator failure does not block the phone step', (
    tester,
  ) async {
    await _login(tester, services: _BrokenOperatorCatalogue());
    await _openTab(tester, 'Services');
    await tester.tap(find.text('Buy Airtime'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await _pickCountry(tester, 'Togo');
    await _settleLatency(tester);

    // A Reloadly destination is routed by the operator detected from the
    // number, so an unavailable catalogue must not replace the step with an
    // error screen: the country pick lands on phone entry with "Auto Detect"
    // deferred to autodetect.
    expect(find.text('Something went wrong'), findsNothing);

    // The number entry stays usable and the pinned header survives — the
    // wizard never loses its way back.
    expect(find.text('Phone Number'), findsOneWidget);
    expect(find.text('Enter Phone Number'), findsOneWidget);

    // The dial chip on the phone step is the way back to the country list.
    await tester.tap(find.text('+228'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Choose the country for airtime topup'), findsOneWidget);
  });

  testWidgets('data: operator failure still reaches the amount step', (
    tester,
  ) async {
    await _login(tester, services: _BrokenDataCatalogue());
    await _openTab(tester, 'Services');
    await _openService(tester, 'Data Bundles');

    await _pickCountry(tester, 'Togo');
    await _settleLatency(tester);

    // The country-wide listing is only an enhancement — the wizard must not
    // dead-end while the phone number can still be typed.
    expect(find.text('Something went wrong'), findsNothing);

    await tester.enterText(find.byType(TextField).last, '900112233');
    await _settleLatency(tester);
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // With no fixed plans to show, Reloadly data falls back to amount entry.
    expect(find.text('Enter Amount'), findsOneWidget);
  });

  testWidgets('data: a live-only country resolves its dial code on pick', (
    tester,
  ) async {
    await _login(tester);
    await _openTab(tester, 'Services');
    await _openService(tester, 'Data Bundles');

    expect(find.text('Select Country'), findsOneWidget);

    await _pickCountry(tester, 'Togo');
    await _settleLatency(tester);

    expect(find.text('+228'), findsOneWidget);
  });

  testWidgets('data: confirm charges in the detected currency', (tester) async {
    await _login(tester);
    await _openTab(tester, 'Services');
    await _openService(tester, 'Data Bundles');

    await _pickCountry(tester, 'Togo');
    await _settleLatency(tester);

    await tester.enterText(find.byType(TextField).last, '900112233');
    await _settleLatency(tester);
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Enter Amount'), findsOneWidget);
    // The mock operator quotes USD while Togo's own currency is XOF.
    await tester.tap(find.text('USD 20'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Label the charge with the currency actually debited, never the
    // destination country's.
    expect(find.textContaining('USD 20.00'), findsWidgets);
    expect(find.textContaining('XOF'), findsNothing);
    // The recipient line carries the resolved dial code.
    expect(find.text('228900112233'), findsWidgets);
  });

  testWidgets('data: a plan outside the detected range still advances', (
    tester,
  ) async {
    await _login(tester, services: _PlanCatalogueRepository());
    await _openTab(tester, 'Services');
    await _openService(tester, 'Data Bundles');

    await _pickCountry(tester, 'Nigeria');
    await _settleLatency(tester);

    await tester.enterText(find.byType(TextField).last, '08031234567');
    await _settleLatency(tester);
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // The detected operator's plans lead the grid.
    expect(find.text('Choose Data Bundle'), findsOneWidget);
    expect(find.text('1GB Monthly'), findsOneWidget);

    // Browsing another operator exposes a plan priced above the detected
    // operator's max — the range gate must not block it.
    await tester.tap(find.text('Glo Nigeria'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('30GB Monthly'), findsOneWidget);

    await tester.tap(find.text('30GB Monthly'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('MoMo or Card · choose next'), findsOneWidget);
  });

  testWidgets('airtime: Ghana confirms its network on the phone step', (
    tester,
  ) async {
    await _login(tester);
    await _openTab(tester, 'Services');
    await tester.tap(find.text('Buy Airtime'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await _pickCountry(tester, 'Ghana');
    await _settleLatency(tester);

    // Legacy order: the country pick lands on the phone step — detection
    // answers the Network position instead of a standalone selection screen.
    expect(find.text('Enter Phone Number'), findsOneWidget);
    expect(find.text('Select Network'), findsNothing);

    await tester.enterText(find.byType(TextField).last, '0244588584');
    await tester.pump(const Duration(milliseconds: 700));
    await _settleLatency(tester);

    // Detection resolving opens the Ghana operating-network sheet once —
    // the ported-number correction the legacy popup provided.
    expect(find.text('Confirm Operating Network'), findsOneWidget);
    expect(find.text('Auto Detect'), findsWidgets);
    expect(find.text('Telecel'), findsWidgets);
    expect(find.text('AirtelTigo'), findsWidgets);
  });
}
