import 'package:flutter_test/flutter_test.dart';
import 'package:sova/data/demo_repository.dart';
import 'package:sova/data/fair_draw.dart';
import 'package:sova/data/models.dart';

// Reference values from api/src/lib/draw.ts (Node crypto), so the app and the
// server agree on every byte of the rule.
const _seed = '0000000000000000000000000000000000000000000000000000000000000001';

void main() {
  test('commitment and keys match the API', () {
    expect(commitmentOf(_seed), 'ec4916dd28fc4c10d78e287ca5d9cc51ee1ae73cbfde08c6b37324cbfaac8bc5');
    expect(drawKey(_seed, 'ada'), '50aa8b089893d9bcf193da4b2cbe6256573785b4c58228680fa376a01ca9c33f');
  });

  test('order is by key, with a pledged admin last', () {
    const ids = ['ada', 'bola', 'chidi', 'dayo'];
    expect(drawOrder(_seed, ids, 'ada', false), ['dayo', 'ada', 'chidi', 'bola']);
    expect(drawOrder(_seed, ids, 'ada', true), ['dayo', 'chidi', 'bola', 'ada']);
    // Join order does not matter.
    expect(drawOrder(_seed, ids.reversed, 'ada', false), ['dayo', 'ada', 'chidi', 'bola']);
  });

  group('demo circles', () {
    late DemoRepository repo;
    setUp(() async {
      repo = DemoRepository();
      await repo.startDemo();
    });

    test('started circles have draws that verify', () async {
      for (final id in ['office-esusu', 'class-ajo']) {
        final check = checkDraw(await repo.circle(id))!;
        expect(check.seedMatchesCommitment, isTrue, reason: id);
        expect(check.orderMatches, isTrue, reason: id);
      }
    });

    test('a forming circle shows only the sealed fingerprint', () async {
      final c = await repo.findByInviteCode('T7KP9Q');
      expect(c.draw!.commitment, hasLength(64));
      expect(c.draw!.revealed, isFalse);
      expect(checkDraw(c), isNull);
    });

    test('a changed turn or seed fails the check', () async {
      final c = await repo.circle('office-esusu');
      Circle withDraw(DrawInfo d, List<Member> members) => Circle(
            id: c.id,
            name: c.name,
            adminId: c.adminId,
            memberCount: c.memberCount,
            contributionAmount: c.contributionAmount,
            cycle: c.cycle,
            startDate: c.startDate,
            inviteCode: c.inviteCode,
            members: members,
            rounds: c.rounds,
            contributions: c.contributions,
            draw: d,
          );
      // An agreed swap after the draw changes who holds a turn, not the draw.
      final swapped = [
        for (final m in c.members)
          Member(userId: m.userId, name: m.name, phone: m.phone, position: switch (m.position) { 1 => 2, 2 => 1, final p => p }),
      ];
      final agreed = withDraw(c.draw!, swapped);
      expect(checkDraw(agreed)!.passed, isTrue);
      expect(turnsChangedSinceDraw(agreed), isTrue);
      expect(turnsChangedSinceDraw(c), isFalse);

      // A record whose drawn order was altered fails.
      final order = c.draw!.order!;
      final altered = DrawInfo(
        commitment: c.draw!.commitment,
        seed: c.draw!.seed,
        revealedAt: c.draw!.revealedAt,
        order: [order[1], order[0], ...order.skip(2)],
      );
      final moved = checkDraw(withDraw(altered, c.members))!;
      expect(moved.seedMatchesCommitment, isTrue);
      expect(moved.orderMatches, isFalse);

      final otherSeed = checkDraw(withDraw(DrawInfo(commitment: c.draw!.commitment, seed: _seed), c.members))!;
      expect(otherSeed.seedMatchesCommitment, isFalse);
    });
  });
}
