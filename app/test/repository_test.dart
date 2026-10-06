import 'package:flutter_test/flutter_test.dart';
import 'package:sova/data/demo_repository.dart';
import 'package:sova/data/models.dart';
import 'package:sova/data/sova_repository.dart';

const pin = '2580';
const me = DemoRepository.me;

void main() {
  late DemoRepository repo;

  setUp(() async {
    repo = DemoRepository();
    await repo.verifyOtp('+2348031234567', DemoRepository.demoOtp);
    await repo.saveProfile(fullName: 'Ada Obi', pin: pin);
  });

  NewCircle draft({int members = 5, bool adminLast = true}) => NewCircle(
        name: '  Market Friends  ',
        contributionAmount: 5000,
        memberCount: members,
        cycle: CycleType.weekly,
        startDate: DateTime(2026, 10, 9),
        adminCollectsLast: adminLast,
        lateFee: 500,
        graceDays: 1,
        earlyExit: EarlyExitPolicy.findReplacement,
      );

  test('wrong OTP is rejected', () async {
    expect(() => repo.verifyOtp('+2348031234567', '000000'), throwsA(isA<SovaException>()));
  });

  test('the demo account signs in with a PIN already set', () async {
    final session = await DemoRepository().startDemo();
    expect(session.isDemo, isTrue);
    expect(session.profileComplete, isTrue);
  });

  test('profile name replaces the placeholder in every circle', () async {
    for (final c in await repo.myCircles()) {
      expect(c.memberById(me)!.name, 'Ada Obi');
    }
  });

  test('circle maths: the collector receives from the other members', () async {
    final c = await repo.circle('office-esusu');
    expect(c.payout, 100000); // 5 other members x 20,000
    expect(c.payersThisRound, 5);
    expect(c.paidThisRound, 2); // Ifeoma and Bayo fully confirmed; Chuka awaiting
  });

  test('recording a payment needs the PIN and the collector to confirm it', () async {
    final c = await repo.circle('office-esusu');
    final round = c.activeRound!;
    await expectLater(
      repo.confirmMyPayment(circleId: c.id, roundNumber: round.number, pin: '9999'),
      throwsA(isA<SovaException>().having((e) => e.code, 'code', 'wrong_pin')),
    );
    final after = await repo.confirmMyPayment(
        circleId: c.id, roundNumber: round.number, bankReference: 'FT123', proofKey: 'demo-photo', pin: pin);
    final mine = after.contributionFor(round.id, me)!;
    expect(mine.status, ContributionStatus.payerConfirmed);
    expect(mine.reference, startsWith('SV-'));

    // Only the collector (Halima) may confirm, so the signed-in member cannot.
    expect(() => repo.confirmReceived(circleId: c.id, contributionId: mine.id, pin: pin), throwsA(isA<SovaException>()));
  });

  test('collector confirms a payment they received', () async {
    final c = await repo.circle('class-ajo');
    final emeka = c.contributions.firstWhere((x) => x.userId == 'emeka' && x.roundId == c.activeRound!.id);
    final after = await repo.confirmReceived(circleId: c.id, contributionId: emeka.id, pin: pin);
    expect(after.contributionFor(emeka.roundId, 'emeka')!.status, ContributionStatus.fullyConfirmed);
    expect(after.paidThisRound, 2);
  });

  test('a short payout opens a dispute and the next turn starts', () async {
    final c = await repo.circle('class-ajo'); // you collect turn 2 of 5; payout 40,000
    final result = await repo.confirmPayout(circleId: c.id, roundNumber: 2, amount: 10000, pin: pin);
    expect(result.shortfall, 30000);
    expect(result.nextRound, 3);
    expect(result.circle.openDisputes, 1);
    expect(result.circle.activeRound!.collectorId, 'emeka');
    expect(result.circle.rounds.firstWhere((r) => r.number == 2).payoutReceived, 10000);
  });

  test('PIN locks after five wrong tries', () async {
    for (var i = 1; i <= 4; i++) {
      await expectLater(repo.verifyPin('1111'), throwsA(predicate((e) => e.toString().contains('${5 - i} tries left'))));
    }
    await expectLater(repo.verifyPin('1111'), throwsA(predicate((e) => e.toString().contains('locked'))));
    // Even the right PIN is refused while locked.
    await expectLater(repo.verifyPin(pin), throwsA(predicate((e) => e.toString().contains('locked'))));
  });

  group('create and join', () {
    test('creating a circle makes you admin of a forming circle with the rules accepted', () async {
      final c = await repo.createCircle(draft(), pin: pin);
      expect(c.name, 'Market Friends');
      expect(c.forming, isTrue);
      expect(c.payout, 20000); // 4 other members x 5,000
      expect(c.isAdmin(me), isTrue);
      expect(c.memberById(me)!.position, isNull); // drawn when full
      expect(c.rules!.acceptedBy, {me});
      expect(c.inviteCode, matches(RegExp(r'^[A-HJKMNP-Z2-9]{6}$')));
      expect(c.activeRound, isNull);
      expect((await repo.myCircles()).first.id, c.id);
    });

    test('invite codes are found regardless of case and dashes', () async {
      final c = await repo.findByInviteCode('t7k-p9q');
      expect(c.name, 'Ikeja Tech Hub Esusu');
      expect(() => repo.findByInviteCode('ZZZZZZ'), throwsA(isA<SovaException>()));
    });

    test('joining records the voucher, accepts the rules and leaves turns undrawn until full', () async {
      expect(() => repo.joinCircle(code: 'T7KP9Q', voucherId: 'stranger', rulesVersion: 1, pin: pin),
          throwsA(isA<SovaException>()));
      expect(() => repo.joinCircle(code: 'T7KP9Q', voucherId: 'kemi', rulesVersion: 2, pin: pin),
          throwsA(isA<SovaException>()));
      final c = await repo.joinCircle(code: 'T7KP9Q', voucherId: 'kemi', rulesVersion: 1, pin: pin);
      final mine = c.memberById(me)!;
      expect(mine.position, isNull); // 5 of 8 joined
      expect(mine.vouchedBy, 'kemi');
      expect(c.forming, isTrue);
      expect(c.rules!.acceptedBy, contains(me));
      expect((await repo.myCircles()).map((x) => x.id), contains('tech-hub'));
      expect(() => repo.joinCircle(code: 'T7KP9Q', voucherId: 'kemi', rulesVersion: 1, pin: pin),
          throwsA(isA<SovaException>()));
    });
  });
}
