import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sova/app.dart';
import 'package:sova/core/router/sova_router.dart';
import 'package:sova/data/models.dart';
import 'package:sova/data/providers.dart';

class _SignedIn extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
        restoring: false,
        onboarded: true,
        session: Session(phone: '+2348031234567', userId: 'me', fullName: 'Ada Obi', hasPin: true),
      );
}

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // Paying, receipts, creating and joining all `go` to a circle, and a reload
  // lands on it directly: there is nothing underneath, but back must still work.
  testWidgets('a circle opened directly still has a back button to my circles', (tester) async {
    final container = ProviderContainer(overrides: [authProvider.overrideWith(_SignedIn.new)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SovaApp()));
    await settle(tester);

    final router = container.read(routerProvider);
    router.go('/circle/office-esusu');
    await settle(tester);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(router.state.matchedLocation, SovaRoutes.circles);
  });
}
