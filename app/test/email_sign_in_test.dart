import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sova/app.dart';
import 'package:sova/data/demo_repository.dart';
import 'package:sova/data/providers.dart';

/// Signing in with an email code instead of a phone, and with Google.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a member signs in with an email code', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: SovaApp()));
    await settle(tester);
    await tester.tap(find.text('Skip'));
    await settle(tester);

    await tester.tap(find.text('Use email instead'));
    await settle(tester);
    expect(find.text('What is your email?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'not an email');
    await tester.tap(find.text('Send code'));
    await settle(tester);
    expect(find.textContaining('Enter your email address'), findsOneWidget);

    await tester.enterText(find.byType(TextField), ' Ada@Example.com ');
    await tester.tap(find.text('Send code'));
    await settle(tester);
    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.textContaining('We emailed it to ada@example.com'), findsOneWidget);

    // Wrong codes are explained; the right one leads to the profile.
    await tester.enterText(find.byType(TextField), '000000');
    await settle(tester);
    expect(find.textContaining('Check your email'), findsOneWidget);
    await tester.enterText(find.byType(TextField), DemoRepository.demoOtp);
    await settle(tester);
    expect(find.text('What should your group call you?'), findsOneWidget);
  });

  test('Google sign-in starts a session and suggests the account\'s name', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(authProvider);
    await Future<void>.delayed(Duration.zero);

    await container.read(authProvider.notifier).signInWithGoogle('google-id-token');
    final auth = container.read(authProvider);
    expect(auth.session?.email, 'ada@example.com');
    expect(auth.session?.contact, 'ada@example.com');
    expect(auth.suggestedName, 'Ada Obi');
    expect(auth.ready, isFalse, reason: 'a new account still sets its name and PIN');
  });
}
