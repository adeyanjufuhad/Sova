import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sova/core/theme/sova_theme.dart';
import 'package:sova/data/demo_repository.dart';
import 'package:sova/data/providers.dart';
import 'package:sova/features/circle/draw_screen.dart';

void main() {
  testWidgets('the draw screen replays the order and shows both checks passing', (tester) async {
    tester.view.physicalSize = const Size(412, 1800) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    final repo = DemoRepository();
    await tester.runAsync(repo.startDemo);
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: SovaTheme.light, home: const DrawScreen(circleId: 'class-ajo')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('The seed matches the sealed fingerprint'), findsOneWidget);
    expect(find.text('Recomputing the order gives the same turns'), findsOneWidget);
    expect(find.text('Turn order: smallest key first'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Turn 1, Tolu Ajayi')), findsOneWidget);

    await tester.tap(find.text('Replay'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Members A to Z: working out each one's key from the seed"), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Turn order: smallest key first'), findsOneWidget);
    semantics.dispose();
  });
}
