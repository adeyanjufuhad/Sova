import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sova/app.dart';
import 'package:sova/core/router/sova_router.dart';
import 'package:sova/data/demo_repository.dart';
import 'package:sova/data/models.dart';
import 'package:sova/data/providers.dart';
import 'package:sova/data/sova_repository.dart';

const pin = '2580';
const me = DemoRepository.me;

class _SignedIn extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
        restoring: false,
        onboarded: true,
        session: Session(phone: '+2348031234567', userId: me, fullName: 'Ada Obi', hasPin: true),
      );
}

class _DemoSignedIn extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
        restoring: false,
        onboarded: true,
        session: Session(phone: '+2348000000000', userId: me, fullName: 'Ada Obi', hasPin: true, isDemo: true),
      );
}

NewCircle _draft() => NewCircle(
      name: 'Market Friends',
      contributionAmount: 5000,
      memberCount: 4,
      cycle: CycleType.weekly,
      startDate: DateTime.now().add(const Duration(days: 3)),
      adminCollectsLast: false,
      lateFee: 0,
      graceDays: 0,
      earlyExit: EarlyExitPolicy.findReplacement,
    );

void main() {
  late DemoRepository repo;

  setUp(() async {
    repo = DemoRepository();
    await repo.verifyOtp('+2348031234567', DemoRepository.demoOtp);
    await repo.saveProfile(fullName: 'Ada Obi', pin: pin);
  });

  group('leaving', () {
    test('a member leaves a forming circle with the PIN, and can join again', () async {
      await repo.joinCircle(code: 'T7KP9Q', voucherId: 'kemi', rulesVersion: 1, pin: pin);
      await expectLater(repo.leaveCircle(circleId: 'tech-hub', pin: '0000'), throwsA(isA<SovaException>()));

      await repo.leaveCircle(circleId: 'tech-hub', pin: pin);
      await expectLater(repo.circle('tech-hub'), throwsA(isA<SovaException>()));
      expect((await repo.myCircles()).map((c) => c.id), isNot(contains('tech-hub')));

      final again = await repo.joinCircle(code: 'T7KP9Q', voucherId: 'kemi', rulesVersion: 1, pin: pin);
      expect(again.members.length, 5);
    });

    test('the admin and members of started circles can\'t leave', () async {
      final mine = await repo.createCircle(_draft(), pin: pin);
      await expectLater(
        repo.leaveCircle(circleId: mine.id, pin: pin),
        throwsA(isA<SovaException>().having((e) => e.message, 'message', contains('cancel it'))),
      );
      await expectLater(
        repo.leaveCircle(circleId: 'office-esusu', pin: pin),
        throwsA(isA<SovaException>().having((e) => e.message, 'message', contains('Hand your place'))),
      );
    });
  });

  group('cancelling', () {
    test('the admin cancels a forming circle and its code stops working', () async {
      final mine = await repo.createCircle(_draft(), pin: pin);
      final cancelled = await repo.cancelCircle(circleId: mine.id, pin: pin);
      expect(cancelled.cancelled, isTrue);
      await expectLater(repo.findByInviteCode(mine.inviteCode), throwsA(isA<SovaException>()));
      await expectLater(repo.cancelCircle(circleId: mine.id, pin: pin), throwsA(isA<SovaException>()));
    });

    test('only the admin can cancel', () async {
      await repo.joinCircle(code: 'T7KP9Q', voucherId: 'kemi', rulesVersion: 1, pin: pin);
      await expectLater(repo.cancelCircle(circleId: 'tech-hub', pin: pin), throwsA(isA<SovaException>()));
    });
  });

  group('deleting the account', () {
    test('waits until every circle has finished', () async {
      await expectLater(
        repo.deleteAccount(pin: pin),
        throwsA(isA<SovaException>().having((e) => e.message, 'message', contains('still running'))),
      );
    });

    test('the shared demo account can\'t be deleted', () async {
      final demo = DemoRepository();
      await demo.startDemo();
      await expectLater(demo.deleteAccount(pin: pin), throwsA(isA<SovaException>()));
    });
  });

  Future<ProviderContainer> open(WidgetTester tester, DemoRepository demo, AuthNotifier Function() auth) async {
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(auth),
      repositoryProvider.overrideWithValue(demo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SovaApp()));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> enterPin(WidgetTester tester) async {
    for (final d in pin.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('a member leaves a forming circle from its screen', (tester) async {
    final demo = DemoRepository();
    await tester.runAsync(() async {
      await demo.verifyOtp('+2348031234567', DemoRepository.demoOtp);
      await demo.saveProfile(fullName: 'Ada Obi', pin: pin);
      await demo.joinCircle(code: 'T7KP9Q', voucherId: 'kemi', rulesVersion: 1, pin: pin);
    });
    final container = await open(tester, demo, _SignedIn.new);
    container.read(routerProvider).go('/circle/tech-hub');
    await tester.pumpAndSettle();

    final leave = find.text('Leave this circle');
    await tester.scrollUntilVisible(leave, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(leave);
    await tester.pumpAndSettle();
    expect(find.text('Leave Ikeja Tech Hub Esusu?'), findsOneWidget);
    await enterPin(tester);

    expect(find.text('You left Ikeja Tech Hub Esusu.'), findsOneWidget);
    expect(container.read(routerProvider).state.uri.path, '/circles');
  });

  testWidgets('the demo account sees why it can\'t be deleted', (tester) async {
    final demo = DemoRepository();
    await tester.runAsync(demo.startDemo);
    final container = await open(tester, demo, _DemoSignedIn.new);
    container.read(routerProvider).go('/settings/delete');
    await tester.pumpAndSettle();

    expect(find.text("This is the shared demo account, so it can't be deleted."), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete my account'));
    expect(button.onPressed, isNull);
  });
}
