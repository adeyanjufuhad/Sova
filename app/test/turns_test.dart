import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sova/app.dart';
import 'package:sova/core/router/sova_router.dart';
import 'package:sova/data/demo_repository.dart';
import 'package:sova/data/fair_draw.dart';
import 'package:sova/data/models.dart';
import 'package:sova/data/providers.dart';
import 'package:sova/data/sova_repository.dart';

const pin = DemoRepository.demoPin;
const office = 'office-esusu';

class _SignedIn extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
        restoring: false,
        onboarded: true,
        session: Session(phone: '+2348000000000', userId: 'me', fullName: 'Ada Obi', hasPin: true),
      );
}

void main() {
  late DemoRepository repo;

  setUp(() async {
    repo = DemoRepository();
    await repo.startDemo();
  });

  group('swaps', () {
    test('accepting a swap trades the turns and keeps the draw checkable', () async {
      final t = await repo.turnChanges(office);
      final ask = t.swaps.single;
      expect(ask.canAnswer, isTrue);
      expect(t.needsMe, 1);
      expect((ask.requester.turn, ask.target.turn), (6, 4));

      await expectLater(
        repo.answerSwap(circleId: office, swapId: ask.id, accept: true, pin: '0000'),
        throwsA(isA<SovaException>()),
      );
      final after = await repo.answerSwap(circleId: office, swapId: ask.id, accept: true, pin: pin);
      expect(after.swaps.single.status, SwapStatus.accepted);
      final c = await repo.circle(office);
      expect(c.memberById('me')!.position, 6);
      expect(c.memberById('zainab')!.position, 4);
      expect(checkDraw(c)!.passed, isTrue);
      expect(turnsChangedSinceDraw(c), isTrue);
    });

    test('only open turns can be swapped, one request at a time', () async {
      // Halima collects turn 3 right now.
      await expectLater(
        repo.requestSwap(circleId: office, targetId: 'halima', pin: pin),
        throwsA(isA<SovaException>().having((e) => e.code, 'code', 'turn_started')),
      );
      final made = await repo.requestSwap(circleId: office, targetId: 'chuka', reason: 'School fees.', pin: pin);
      final mine = made.swaps.firstWhere((s) => s.canCancel);
      expect(mine.reason, 'School fees.');
      await expectLater(
        repo.requestSwap(circleId: office, targetId: 'zainab', pin: pin),
        throwsA(isA<SovaException>().having((e) => e.code, 'code', 'already_asked')),
      );
      final cancelled = await repo.cancelSwap(circleId: office, swapId: mine.id);
      expect(cancelled.swaps.firstWhere((s) => s.id == mine.id).status, SwapStatus.cancelled);
    });
  });

  group('handovers', () {
    test('a member names a replacement by phone; the admin and unknown numbers are refused', () async {
      await expectLater(
        repo.requestHandover(circleId: 'class-ajo', phone: '0803 222 0003', pin: pin),
        throwsA(isA<SovaException>().having((e) => e.code, 'code', 'admin_cannot_leave')),
      );
      await expectLater(
        repo.requestHandover(circleId: office, phone: '0809 999 9999', pin: pin),
        throwsA(isA<SovaException>().having((e) => e.code, 'code', 'no_account')),
      );
      await expectLater(
        repo.requestHandover(circleId: office, phone: '0803 111 0001', pin: pin), // Ifeoma is in the circle
        throwsA(isA<SovaException>().having((e) => e.code, 'code', 'already_member')),
      );
      // Tolu, from the class ajo, takes your place in the office esusu.
      final made = await repo.requestHandover(circleId: office, phone: '0803 222 0001', reason: 'Moving to Abuja.', pin: pin);
      final h = made.handovers.single;
      expect(h.status, HandoverStatus.pending);
      expect(h.replacement.name, 'Tolu Ajayi');
      expect(h.leaving.turn, 4);
      expect(h.paidIn, 40000); // turns 1 and 2, confirmed
      expect(h.canCancel, isTrue);
      expect((await repo.cancelHandover(circleId: office, handoverId: h.id)).handovers.single.status, HandoverStatus.cancelled);
    });
  });

  testWidgets('a member answers a swap request from the circle screen', (tester) async {
    tester.view.physicalSize = const Size(412, 2000) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final demo = DemoRepository();
    await tester.runAsync(demo.startDemo);
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(_SignedIn.new),
      repositoryProvider.overrideWithValue(demo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SovaApp()));
    await tester.pumpAndSettle();

    container.read(routerProvider).go('/circle/$office');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byIcon(Icons.swap_horiz_rounded), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zainab asks to swap turns'));
    await tester.pumpAndSettle();

    expect(find.text('Zainab asks to swap turns with you'), findsOneWidget);
    expect(find.text('“My shop rent is due before my turn. Could we swap?”'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
    await tester.pumpAndSettle();
    for (final digit in pin.split('')) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('Swapped'), findsOneWidget);
    expect(find.textContaining('now collects on turn 4'), findsOneWidget);
  });
}
