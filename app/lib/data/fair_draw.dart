import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'models.dart';

// The fair payout draw, the same rule as the database (run_draw, draw_key) and
// api/src/lib/draw.ts, so the app can recheck a draw on the phone:
//   commitment = SHA-256(seed bytes), published when the circle is created
//   key(member) = SHA-256(seed_hex + ":" + user_id), turns in ascending key order
//   an admin who pledged to collect last goes last

List<int> _hexBytes(String hex) =>
    [for (var i = 0; i + 1 < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];

String commitmentOf(String seedHex) => sha256.convert(_hexBytes(seedHex)).toString();

String drawKey(String seedHex, String userId) => sha256.convert(utf8.encode('$seedHex:$userId')).toString();

/// Member ids in payout order (turn 1 first).
List<String> drawOrder(String seedHex, Iterable<String> userIds, String adminId, bool adminCollectsLast) {
  int last(String id) => adminCollectsLast && id == adminId ? 1 : 0;
  final keyed = [for (final id in userIds) (id: id, key: drawKey(seedHex, id))];
  keyed.sort((a, b) {
    final byPledge = last(a.id) - last(b.id);
    return byPledge != 0 ? byPledge : a.key.compareTo(b.key);
  });
  return [for (final m in keyed) m.id];
}

/// The outcome of rechecking a circle's revealed draw.
class DrawCheck {
  const DrawCheck({required this.seedMatchesCommitment, required this.recomputedOrder, required this.recordedOrder});

  final bool seedMatchesCommitment;
  final List<String> recomputedOrder;
  final List<String> recordedOrder;

  bool get orderMatches =>
      recomputedOrder.length == recordedOrder.length &&
      [for (var i = 0; i < recordedOrder.length; i++) recomputedOrder[i] == recordedOrder[i]].every((ok) => ok);

  bool get passed => seedMatchesCommitment && orderMatches;
}

/// Rechecks [circle]'s draw from its revealed seed; null until the seed is revealed.
DrawCheck? checkDraw(Circle circle) {
  final draw = circle.draw;
  final seed = draw?.seed;
  if (draw == null || seed == null) return null;
  return DrawCheck(
    seedMatchesCommitment: commitmentOf(seed) == draw.commitment.toLowerCase(),
    recomputedOrder: drawOrder(seed, circle.members.map((m) => m.userId), circle.adminId, circle.adminCollectsLast),
    recordedOrder: [for (final m in circle.membersByPosition) m.userId],
  );
}
