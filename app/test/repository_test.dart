import 'package:flutter_test/flutter_test.dart';
import 'package:sova/data/demo_repository.dart';
import 'package:sova/data/models.dart';
import 'package:sova/data/sova_repository.dart';

void main() {
  late DemoRepository repo;

  setUp(() async {
    repo = DemoRepository();
    await repo.verifyOtp('+2348031234567', DemoRepository.demoOtp);
    await repo.saveProfile(fullName: 'Ada Obi', pin: '2580');
  });

  test('wrong OTP is rejected', () async {
    expect(() => repo.verifyOtp('+2348031234567', '000000'), throwsA(isA<SovaException>()));
  });

  test('profile name replaces the placeholder in every circle', () async {
    for (final c in await repo.myCircles()) {
      expect(c.memberById(DemoRepository.me)!.name, 'Ada Obi');
    }
  });

  test('circle maths: payout and paid count exclude the collector', () async {
    final c = await repo.circle('office-esusu');
    expect(c.payout, 120000); // 6 seats x 20,000
    expect(c.payersThisRound, 5);
    expect(c.paidThisRound, 2); // Ifeoma and Bayo fully confirmed; Chuka awaiting
  });

  test('recording a payment needs the collector to confirm it', () async {
    final c = await repo.circle('office-esusu');
    final round = c.activeRound!;
    final mine = await repo.confirmMyPayment(circleId: c.id, roundId: round.id, bankReference: 'FT123', hasProof: true);
    expect(mine.status, ContributionStatus.payerConfirmed);
    expect(mine.reference, startsWith('SV-'));

    // Recording twice is refused.
    expect(() => repo.confirmMyPayment(circleId: c.id, roundId: round.id), throwsA(isA<SovaException>()));

    // Only the collector (Halima) may confirm, so the signed-in member cannot.
    expect(() => repo.confirmReceived(circleId: c.id, contributionId: mine.id), throwsA(isA<SovaException>()));
  });

  test('collector confirms a payment they received', () async {
    final c = await repo.circle('class-ajo');
    final emeka = c.contributions.firstWhere((x) => x.userId == 'emeka' && x.roundId == c.activeRound!.id);
    final confirmed = await repo.confirmReceived(circleId: c.id, contributionId: emeka.id);
    expect(confirmed.status, ContributionStatus.fullyConfirmed);
    expect((await repo.circle('class-ajo')).paidThisRound, 2);
  });

  test('PIN locks after five wrong tries', () async {
    for (var i = 1; i <= 4; i++) {
      await expectLater(repo.verifyPin('1111'), throwsA(predicate((e) => e.toString().contains('${5 - i} tries left'))));
    }
    await expectLater(repo.verifyPin('1111'), throwsA(predicate((e) => e.toString().contains('locked'))));
    // Even the right PIN is refused while locked.
    await expectLater(repo.verifyPin('2580'), throwsA(predicate((e) => e.toString().contains('locked'))));
  });

  test('accepting rules records the member', () async {
    expect((await repo.circle('class-ajo')).rules!.acceptedBy, isNot(contains('david')));
    await repo.acceptRules('class-ajo');
    expect((await repo.circle('class-ajo')).rules!.acceptedBy, contains(DemoRepository.me));
  });

  group('create and join', () {
    test('creating a circle makes you admin, collecting last, with the rules accepted', () async {
      final c = await repo.createCircle(NewCircle(
        name: '  Market Friends  ',
        contributionAmount: 5000,
        memberCount: 5,
        cycle: CycleType.weekly,
        startDate: DateTime(2026, 10, 9),
        adminCollectsFirst: false,
        lateFee: 500,
        graceDays: 1,
        earlyExit: EarlyExitPolicy.findReplacement,
      ));
      expect(c.name, 'Market Friends');
      expect(c.isAdmin(DemoRepository.me), isTrue);
      expect(c.memberById(DemoRepository.me)!.position, 5);
      expect(c.rules!.acceptedBy, {DemoRepository.me});
      expect(c.inviteCode, matches(RegExp(r'^[A-HJKMNP-Z2-9]{6}$')));
      expect(c.activeRound, isNull);
      expect((await repo.myCircles()).first.id, c.id);
    });

    test('invite codes are found regardless of case and dashes', () async {
      final c = await repo.findByInviteCode('t7k-p9q');
      expect(c.name, 'Ikeja Tech Hub Esusu');
      expect(() => repo.findByInviteCode('ZZZZZZ'), throwsA(isA<SovaException>()));
    });

    test('joining takes the earliest free turn, records the voucher and accepts the rules', () async {
      expect(() => repo.joinCircle(code: 'T7KP9Q', voucherId: 'stranger'), throwsA(isA<SovaException>()));
      final c = await repo.joinCircle(code: 'T7KP9Q', voucherId: 'kemi');
      final mine = c.memberById(DemoRepository.me)!;
      expect(mine.position, 4); // 1, 2, 3 and 8 were taken
      expect(mine.vouchedBy, 'kemi');
      expect(c.rules!.acceptedBy, contains(DemoRepository.me));
      expect((await repo.myCircles()).map((x) => x.id), contains('tech-hub'));
      expect(() => repo.joinCircle(code: 'T7KP9Q', voucherId: 'kemi'), throwsA(isA<SovaException>()));
    });
  });
}
