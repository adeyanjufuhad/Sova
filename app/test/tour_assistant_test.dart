import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sova/app.dart';
import 'package:sova/core/router/sova_router.dart';
import 'package:sova/data/models.dart';
import 'package:sova/data/providers.dart';

/// The guided tours and "Ask Sova", on the in-memory demo backend.
void main() {
  Future<void> settle(WidgetTester tester, [int ticks = 15]) async {
    for (var i = 0; i < ticks; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ProviderContainer> startDemo(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SovaApp()));
    await settle(tester);
    await tester.tap(find.text('Try the demo'));
    await settle(tester, 25);
    return container;
  }

  testWidgets('a demo visitor gets the main tour once and can skip it', (tester) async {
    final container = await startDemo(tester);

    expect(find.text('Welcome to Sova'), findsOneWidget);
    expect(find.textContaining('Your demo PIN is 2580'), findsOneWidget);
    expect(find.text('1 of 9'), findsOneWidget);

    await tester.tap(find.text('Skip tour'));
    await settle(tester);
    expect(find.text('Skip tour'), findsNothing);
    expect(container.read(authProvider).session!.pendingTours, {Tour.circle});

    // It can be taken again from the Record tab.
    container.read(routerProvider).go(SovaRoutes.record);
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Take the tour again'), 300, scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300)); // clear the tab bar
    await settle(tester);
    await tester.tap(find.text('Take the tour again'));
    await settle(tester, 25);
    expect(find.text('Welcome to Sova'), findsOneWidget);
    await tester.tap(find.text('Skip tour'));
    await settle(tester);
  });

  testWidgets('the first running circle gets its own tour, and Ask Sova explains it', (tester) async {
    final container = await startDemo(tester);
    await tester.tap(find.text('Skip tour'));
    await settle(tester);

    container.read(routerProvider).go('/circle/office-esusu');
    await settle(tester, 25);
    expect(find.text('This circle'), findsOneWidget);

    // Step through to the end; steps whose part isn't on screen are passed over.
    for (var i = 0; i < 8 && find.text('Done').evaluate().isEmpty; i++) {
      await tester.tap(find.text('Next'));
      await settle(tester, 25);
    }
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(container.read(authProvider).session!.pendingTours, isEmpty);

    await tester.tap(find.byTooltip('Ask Sova about this circle'));
    await settle(tester, 25);
    expect(find.textContaining('Office Esusu is a'), findsOneWidget);
    expect(find.textContaining('Offline demo: a fixed answer'), findsOneWidget);

    // Pidgin is hidden until a model writes it well.
    expect(find.text('Pidgin'), findsNothing);
  });

  testWidgets('Ask Sova answers a question about how Sova works', (tester) async {
    final container = await startDemo(tester);
    await tester.tap(find.text('Skip tour'));
    await settle(tester);
    container.read(routerProvider).go(SovaRoutes.home);
    await settle(tester);

    await tester.tap(find.bySemanticsLabel('Ask Sova'));
    await settle(tester);
    await tester.tap(find.text('Ask'));
    await settle(tester);
    expect(find.text('Type a question first.'), findsOneWidget);

    await tester.tap(find.text('Who holds the money?'));
    await settle(tester, 25);
    expect(find.textContaining('Sova never holds, moves, lends or invests money'), findsOneWidget);
  });
}
