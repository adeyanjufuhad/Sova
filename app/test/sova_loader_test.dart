import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sova/shared/widgets/sova_loader.dart';

void main() {
  testWidgets('the loader holds still when the system asks for reduced motion', (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: Directionality(textDirection: TextDirection.ltr, child: Center(child: SovaLoader())),
    ));
    // pumpAndSettle would time out if the cradle kept swinging.
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  });

  testWidgets('the loader swings otherwise', (tester) async {
    await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: Center(child: SovaLoader())));
    await tester.pump(const Duration(milliseconds: 300));
    final first = tester.widgetList<Transform>(find.byType(Transform)).first;
    expect(first.transform.isIdentity(), isFalse);
  });
}
