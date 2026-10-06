import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sova/app.dart';

/// Signs up, then starts a circle through the four-step wizard and joins
/// another one with an invite code.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapKeys(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
  }

  Future<void> signUp(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SovaApp()));
    await settle(tester);
    await tester.tap(find.text('Skip'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '08031234567');
    await tester.tap(find.text('Send code'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '123456');
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Ada Obi');
    await tester.tap(find.text('Continue'));
    await settle(tester);
    await tapKeys(tester, '25802580');
    await settle(tester);
  }

  testWidgets('start a circle and get an invite code', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await signUp(tester);

    await tester.tap(find.text('Start').first);
    await settle(tester);
    expect(find.text('Name your circle and set the amount'), findsOneWidget);

    // Continue without a name is explained.
    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(find.textContaining('Give your circle a name'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Circle name'), 'Market Friends');
    await tester.tap(find.text('₦5,000'));
    await tester.tap(find.bySemanticsLabel('Fewer members'));
    await settle(tester);
    expect(find.text('5'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await settle(tester);

    expect(find.text('When do members pay?'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await settle(tester);

    expect(find.text('Agree the rules up front'), findsOneWidget);
    await tester.tap(find.text('₦1,000'));
    await tester.tap(find.text('Continue'));
    await settle(tester);

    expect(find.text('Check everything'), findsOneWidget);
    expect(find.text('₦20,000'), findsOneWidget); // 4 other members x ₦5,000
    await tester.tap(find.text('Create circle'));
    await settle(tester);
    expect(find.textContaining('Tick the box'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Create circle'));
    await settle(tester);
    await tapKeys(tester, '2580');
    await settle(tester);

    expect(find.text('Market Friends is ready'), findsOneWidget);
    expect(find.text('Invite code'), findsOneWidget);

    await tester.tap(find.text('Go to circle'));
    await settle(tester);
    expect(find.text('Waiting for members'), findsOneWidget);
    expect(find.text('1 of 5 joined'), findsOneWidget);
  });

  testWidgets('join a circle with an invite code', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await signUp(tester);

    await tester.tap(find.bySemanticsLabel('Join a circle with an invite code'));
    await settle(tester);
    expect(find.text('Enter the code from your circle'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ZZZZZZ');
    await settle(tester);
    expect(find.textContaining('No circle uses that code'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 't7kp9q');
    await settle(tester);
    expect(find.text('Ikeja Tech Hub Esusu'), findsOneWidget);
    expect(find.text('4 of 8 joined'), findsOneWidget);

    // Both a voucher and accepting the rules are required.
    await tester.tap(find.text('Join Ikeja Tech Hub Esusu'));
    await settle(tester);
    expect(find.text('Choose the member who invited you.'), findsOneWidget);

    // "Kemi Adebayo" also appears as the admin in the details; pick her in the voucher list.
    final kemiCard = find.widgetWithText(AnimatedContainer, 'Kemi Adebayo');
    await tester.scrollUntilVisible(kemiCard, 200);
    await tester.tap(kemiCard);
    await tester.scrollUntilVisible(find.byType(Checkbox), 200);
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Join Ikeja Tech Hub Esusu'));
    await settle(tester);
    await tapKeys(tester, '2580');
    await settle(tester);

    expect(find.text('Ikeja Tech Hub Esusu'), findsWidgets);
    expect(find.text('Waiting for members'), findsOneWidget);
    expect(find.text('5 of 8 joined'), findsOneWidget);
  });
}
