import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/features/payments/widgets/payment_method_selector.dart';

void main() {
  testWidgets('card payment header wraps on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(373, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPaymentMethodSheet(
                context: context,
                amountLabel: 'GHS 10.00',
                orderSummary: 'Test purchase',
                registeredNumber: '0244000000',
              ),
              child: const Text('Open payment methods'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open payment methods'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Debit / Credit Card'));
    await tester.pumpAndSettle();

    expect(find.text('Local & International'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
