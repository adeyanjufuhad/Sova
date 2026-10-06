import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sova/app.dart';
import 'package:sova/core/router/sova_router.dart';
import 'package:sova/data/models.dart';
import 'package:sova/data/providers.dart';

/// Starts the app already signed in, skipping the sign-up flow.
class _SignedIn extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
        restoring: false,
        onboarded: true,
        session: Session(phone: '+2348031234567', userId: 'me', fullName: 'Ada Obi', hasPin: true),
      );
}

/// Every main screen must fit a small phone with enlarged text: no overflow.
void main() {
  // Measure with the real typeface, not the test framework's wide placeholder font.
  setUpAll(() async {
    final loader = FontLoader('PlusJakartaSans');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      loader.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-$w.ttf'));
    }
    await loader.load();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final size in const [Size(320, 640), Size(412, 915)]) {
    testWidgets('screens fit ${size.width.toInt()}px wide at 130% text', (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final container = ProviderContainer(overrides: [authProvider.overrideWith(_SignedIn.new)]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SovaApp()));
      await settle(tester);

      final router = container.read(routerProvider);
      for (final location in [
        '/home',
        '/circles',
        '/activity',
        '/record',
        '/circle/office-esusu',
        '/circle/office-esusu/pay',
        '/circle/office-esusu/rules',
        '/circle/class-ajo',
        '/circle/class-ajo/draw',
        '/circle/office-esusu/draw',
        '/create',
        '/join',
      ]) {
        router.go(location);
        await settle(tester);
        // Any overflow is reported by the framework; name the screen it happened on.
        expect(tester.takeException(), isNull, reason: 'layout error on $location');
        expect(router.state.matchedLocation, location, reason: 'redirected away from $location');
      }

      // Unused import guard for GoRouter types.
      expect(router, isA<GoRouter>());
    });
  }
}
