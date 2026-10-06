import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sova/app.dart';
import 'package:sova/core/router/sova_router.dart';
import 'package:sova/data/models.dart';
import 'package:sova/data/providers.dart';
import 'package:sova/shared/widgets/glass_tab_bar.dart';

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

  testWidgets('the glass tab bar switches pages by tap and by dragging the lens', (tester) async {
    final container = ProviderContainer(overrides: [authProvider.overrideWith(_SignedIn.new)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SovaApp()));
    await settle(tester);
    final router = container.read(routerProvider);
    router.go(SovaRoutes.home);
    await settle(tester);

    Finder tab(String label) => find.descendant(of: find.byType(GlassTabBar), matching: find.bySemanticsLabel(label));

    // Tap.
    await tester.tap(tab('Circles'));
    await settle(tester);
    expect(router.state.matchedLocation, SovaRoutes.circles);

    // Drag the lens from Circles across to Record and let go.
    final circles = tester.getCenter(tab('Circles'));
    final record = tester.getCenter(tab('Record'));
    await tester.dragFrom(circles, record - circles);
    await settle(tester);
    expect(router.state.matchedLocation, SovaRoutes.record);

    // A short drag that ends nearer where it started stays put.
    await tester.dragFrom(record, const Offset(-20, 0));
    await settle(tester);
    expect(router.state.matchedLocation, SovaRoutes.record);
  });

  testWidgets('a link to nowhere shows a friendly page with a way home', (tester) async {
    final container = ProviderContainer(overrides: [authProvider.overrideWith(_SignedIn.new)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SovaApp()));
    await settle(tester);

    final router = container.read(routerProvider);
    router.go('/no-such-page');
    await settle(tester);
    expect(find.text("This page doesn't exist"), findsOneWidget);
    expect(find.textContaining('GoException'), findsNothing);

    await tester.tap(find.text('Go to home'));
    await settle(tester);
    expect(router.state.matchedLocation, SovaRoutes.home);
  });
}
