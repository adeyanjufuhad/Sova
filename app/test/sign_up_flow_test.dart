import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sova/app.dart';

/// Walks the whole sign-up: welcome -> phone -> OTP -> name -> PIN x2 -> home.
void main() {
  Future<void> settle(WidgetTester tester) async {
    // Demo repository answers after ~350ms.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapKeys(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
  }

  testWidgets('a new member signs up and lands on their circles', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: SovaApp()));
    await settle(tester);
    expect(find.text('Your ajo, on record.'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect(find.text('What is your phone number?'), findsOneWidget);

    // A bad number is explained, not silently rejected.
    await tester.enterText(find.byType(TextField), '12345');
    await tester.tap(find.text('Send code'));
    await settle(tester);
    expect(find.textContaining('Enter a Nigerian mobile number'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '0803 123 4567');
    await tester.tap(find.text('Send code'));
    await settle(tester);
    expect(find.text('Enter the 6-digit code'), findsOneWidget);
    expect(find.textContaining('0803 123 4567'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await settle(tester);
    expect(find.text('What should your group call you?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Ada Obi');
    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(find.text('Create a 4-digit PIN'), findsOneWidget);

    // Easy PINs are refused.
    await tapKeys(tester, '1111');
    await settle(tester);
    expect(find.textContaining('too easy to guess'), findsOneWidget);

    await tapKeys(tester, '2580');
    await settle(tester);
    expect(find.text('Enter your PIN again'), findsOneWidget);
    await tapKeys(tester, '2580');
    await settle(tester);

    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Office Esusu'), findsOneWidget);
    expect(find.textContaining('Pay Halima'), findsOneWidget);
    expect(find.textContaining('Did Emeka pay you'), findsOneWidget);
    expect(find.text('Accept the group rules'), findsNothing); // both circles' rules include "me"
  });
}
