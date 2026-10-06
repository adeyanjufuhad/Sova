import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sova/app.dart';
import 'package:sova/core/router/sova_router.dart';
import 'package:sova/data/demo_repository.dart';
import 'package:sova/data/models.dart';
import 'package:sova/data/providers.dart';
import 'package:sova/data/sova_repository.dart';

const pin = DemoRepository.demoPin;

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

  group('payment disputes', () {
    test('the seeded dispute: you can vote, and your vote decides it', () async {
      final list = await repo.disputes('office-esusu');
      expect(list, hasLength(1));
      final d = list.single;
      expect(d.kind, DisputeKind.payment);
      expect(d.myRole, DisputeRole.voter);
      expect(d.canVote, isTrue);
      expect((d.eligibleVoters, d.votesNeeded, d.payerVotes), (4, 3, 2));

      final decided = await repo.voteDispute(disputeId: d.id, side: DisputeSide.payer, pin: pin);
      expect(decided.status, DisputeStatus.resolvedForPayer);
      expect(decided.resolutionNote, 'Decided by the circle: 3 of 4 members voted that the money arrived.');
      final c = await repo.circle('office-esusu');
      expect(c.statusFor('o-r3', 'chuka'), ContributionStatus.fullyConfirmed);
      expect(c.openDisputes, 0);
    });

    test('a vote short of a majority leaves it open, and can be changed', () async {
      final d = (await repo.disputes('office-esusu')).single;
      final against = await repo.voteDispute(disputeId: d.id, side: DisputeSide.collector, pin: pin);
      expect(against.status, DisputeStatus.open);
      expect(against.myVote, DisputeSide.collector);
      final changed = await repo.voteDispute(disputeId: d.id, side: DisputeSide.payer, pin: pin);
      expect(changed.status, DisputeStatus.resolvedForPayer);
    });

    test('the collector disputes a payment; they cannot vote, but can settle it', () async {
      final c = await repo.circle('class-ajo');
      final emeka = c.contributionFor(c.activeRound!.id, 'emeka')!;
      await expectLater(
        repo.raiseDispute(contributionId: emeka.id, reason: 'Not here', pin: '0000'),
        throwsA(isA<SovaException>()),
      );
      final d = await repo.raiseDispute(contributionId: emeka.id, reason: 'Nothing in my OPay account.', pin: pin);
      expect(d.myRole, DisputeRole.collector);
      expect(d.canVote, isFalse);
      expect(d.canSettle, isTrue);
      expect((await repo.circle('class-ajo')).statusFor(c.activeRound!.id, 'emeka'), ContributionStatus.disputed);
      await expectLater(
        repo.voteDispute(disputeId: d.id, side: DisputeSide.collector, pin: pin),
        throwsA(isA<SovaException>().having((e) => e.code, 'code', 'party_cannot_vote')),
      );
      await expectLater(
        repo.confirmReceived(circleId: c.id, contributionId: emeka.id, pin: pin),
        throwsA(isA<SovaException>()),
      );

      final settled = await repo.settleDispute(disputeId: d.id, pin: pin);
      expect(settled.status, DisputeStatus.resolvedForPayer);
      expect((await repo.circle('class-ajo')).statusFor(c.activeRound!.id, 'emeka'), ContributionStatus.fullyConfirmed);
    });

    test('only open disputes take comments', () async {
      final d = (await repo.disputes('office-esusu')).single;
      final commented = await repo.commentOnDispute(disputeId: d.id, message: 'I saw the GTBank receipt.');
      expect(commented.timeline.last.message, 'I saw the GTBank receipt.');
      await repo.voteDispute(disputeId: d.id, side: DisputeSide.payer, pin: pin);
      expect(() => repo.commentOnDispute(disputeId: d.id, message: 'Late'), throwsA(isA<SovaException>()));
    });
  });

  test('a short payout opens a shortfall dispute with no vote; the collector can mark it settled', () async {
    final c = await repo.circle('class-ajo');
    final result = await repo.confirmPayout(circleId: c.id, roundNumber: 2, amount: 10000, pin: pin);
    expect(result.shortfall, 30000);
    final d = (await repo.disputes(c.id)).single;
    expect(d.kind, DisputeKind.shortfall);
    expect(d.payers.map((p) => p.id), containsAll(['emeka', 'amina', 'david']));
    expect(d.canVote, isFalse);
    expect(() => repo.voteDispute(disputeId: d.id, side: DisputeSide.payer, pin: pin), throwsA(isA<SovaException>()));
    final settled = await repo.settleDispute(disputeId: d.id, pin: pin);
    expect(settled.status, DisputeStatus.resolvedForPayer);
    expect(settled.resolutionNote, contains('marked the shortfall as settled'));
  });

  testWidgets('a member opens the dispute from the circle and casts the deciding vote', (tester) async {
    tester.view.physicalSize = const Size(412, 2400) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final demo = DemoRepository();
    await tester.runAsync(demo.startDemo); // sets the demo PIN
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(_SignedIn.new),
      repositoryProvider.overrideWithValue(demo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SovaApp()));
    await tester.pumpAndSettle();

    container.read(routerProvider).go('/circle/office-esusu');
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 open dispute'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Chuka's turn 3 payment"));
    await tester.pumpAndSettle();

    expect(find.text('Did Chuka\'s ₦20,000 reach Halima?'), findsOneWidget);
    expect(find.text('2 of 3 needed'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'It arrived'));
    await tester.pumpAndSettle();
    for (final digit in DemoRepository.demoPin.split('')) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // In the outcome notice and as the last line of the history.
    expect(find.textContaining('Decided by the circle: 3 of 4 members voted that the money arrived.'), findsNWidgets(2));
    expect(find.textContaining('Closed: paid'), findsOneWidget);
  });
}
