import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sova/data/api/api_client.dart';
import 'package:sova/data/api/api_repository.dart';
import 'package:sova/data/api/session_store.dart';
import 'package:sova/data/models.dart';
import 'package:sova/data/sova_repository.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> tokens(String access, String refresh) => {
      'accessToken': access,
      'refreshToken': refresh,
      'expiresIn': 900,
      'user': {'id': 'u1', 'phone': '+2348000000000', 'fullName': 'Ada Obi', 'hasPin': true, 'isDemo': true},
    };

ApiClient client(MockClient mock, SessionStore store) =>
    ApiClient(baseUrl: 'https://api.test', store: store, client: mock, wakeRetryDelay: Duration.zero);

void main() {
  test('waits while the host shows its waking page', () async {
    var calls = 0;
    final api = client(
      MockClient((req) async {
        calls++;
        if (calls < 3) {
          return http.Response('<html data-rumpty-wake="1">Waking your app…</html>', 200,
              headers: {'content-type': 'text/html; charset=utf-8'});
        }
        return json({'status': 'ok'});
      }),
      MemorySessionStore(),
    );
    expect(await api.get('/health'), {'status': 'ok'});
    expect(calls, 3);
  });

  test('refreshes an expired access token once and retries', () async {
    final store = MemorySessionStore();
    final seen = <String?>[];
    final api = client(
      MockClient((req) async {
        if (req.url.path == '/auth/refresh') {
          expect(jsonDecode(req.body), {'refreshToken': 'refresh-1'});
          return json(tokens('access-2', 'refresh-2'));
        }
        seen.add(req.headers['Authorization']);
        return req.headers['Authorization'] == 'Bearer access-2'
            ? json({'circles': []})
            : json({'error': {'code': 'unauthorized', 'message': 'Please sign in.'}}, 401);
      }),
      store,
    );
    await api.startSession(tokens('access-1', 'refresh-1'));
    expect(await api.get('/circles'), {'circles': []});
    expect(seen, ['Bearer access-1', 'Bearer access-2']);
    expect(await store.read(), 'refresh-2'); // rotated token saved
  });

  test('turns API errors into readable exceptions', () async {
    final api = client(
      MockClient((_) async => json({'error': {'code': 'wrong_pin', 'message': 'Wrong PIN. 4 tries left.'}}, 401)),
      MemorySessionStore(),
    );
    await expectLater(
      api.post('/me/pin/verify', {'pin': '0000'}),
      throwsA(isA<SovaException>()
          .having((e) => e.code, 'code', 'wrong_pin')
          .having((e) => e.message, 'message', 'Wrong PIN. 4 tries left.')),
    );
  });

  test('a saved session that the server no longer accepts just signs out', () async {
    final store = MemorySessionStore()..write('old-refresh');
    final repo = ApiRepository(client(
      MockClient((_) async => json({'error': {'code': 'unauthorized', 'message': 'Please sign in again.'}}, 401)),
      store,
    ));
    expect(await repo.restoreSession(), isNull);
    expect(await store.read(), isNull);
  });

  test('maps a circle from the API', () async {
    final repo = ApiRepository(client(MockClient((_) async => json(_detail)), MemorySessionStore()));
    final c = await repo.circle('c1');
    expect(c.status, CircleStatus.active);
    expect(c.payout, 20000); // 2 other members x 10,000
    expect(c.membersByPosition.map((m) => m.name), ['Bayo Adeyemi', 'Ada Obi', 'Chuka Eze']);
    expect(c.currentCollector!.bank!.accountNumber, '0234567891');
    expect(c.memberById('ada')!.bank, isNull); // only the collector's account is shared
    expect(c.rules!.acceptedBy, {'ada', 'bayo', 'chuka'});
    expect(c.draw!.revealed, isTrue);
    final paid = c.contributionFor('r1', 'ada')!;
    expect(paid.status, ContributionStatus.payerConfirmed);
    expect(paid.reference, 'SV-0A1B2C3D');
    expect(c.statusFor('r1', 'chuka'), ContributionStatus.pending);
  });
}

final _detail = {
  'id': 'c1',
  'name': 'Tech Hub Esusu',
  'status': 'active',
  'contributionAmount': 10000,
  'payoutAmount': 20000,
  'cycleType': 'weekly',
  'memberCount': 3,
  'membersJoined': 3,
  'startDate': '2026-10-05',
  'inviteCode': 'K7QX2M',
  'adminId': 'ada',
  'adminCollectsLast': false,
  'isAdmin': true,
  'myPosition': 2,
  'members': [
    {'id': 'bayo', 'name': 'Bayo Adeyemi', 'phone': '+2348000000012', 'position': 1, 'isAdmin': false, 'acceptedRules': true, 'vouchedBy': null, 'owesAfterCollecting': false},
    {'id': 'ada', 'name': 'Ada Obi', 'phone': '+2348000000011', 'position': 2, 'isAdmin': true, 'acceptedRules': true, 'vouchedBy': null, 'owesAfterCollecting': false},
    {'id': 'chuka', 'name': 'Chuka Eze', 'phone': '+2348000000013', 'position': 3, 'isAdmin': false, 'acceptedRules': true, 'vouchedBy': {'id': 'ada', 'name': 'Ada Obi'}, 'owesAfterCollecting': false},
  ],
  'rules': {'version': 1, 'lateFee': 500, 'graceDays': 1, 'earlyExitPolicy': 'find_replacement', 'emergencyPolicy': null, 'otherRules': null, 'acceptedByMe': true},
  'draw': {'commitment': 'ab' * 32, 'revealedAt': '2026-10-04T10:00:00.000Z', 'seed': 'cd' * 32},
  'currentRound': {
    'id': 'r1',
    'number': 1,
    'dueDate': '2026-10-05',
    'payoutAmount': 20000,
    'isMyTurn': false,
    'collector': {'id': 'bayo', 'name': 'Bayo Adeyemi', 'bank': {'bankName': 'Guaranty Trust Bank (GTBank)', 'accountNumber': '0234567891', 'accountName': 'Bayo Adeyemi'}},
    'contributions': [],
  },
  'openDisputes': 0,
  'rounds': [
    {'id': 'r1', 'number': 1, 'collectorId': 'bayo', 'dueDate': '2026-10-05', 'status': 'active', 'payoutReceived': null, 'payoutConfirmedAt': null},
  ],
  'contributions': [
    {'id': '0a1b2c3d-0000-0000-0000-000000000000', 'roundId': 'r1', 'userId': 'ada', 'amount': 10000, 'status': 'payer_confirmed', 'bankReference': 'FT1', 'hasProof': false, 'paidAt': '2026-10-04T12:00:00.000Z', 'confirmedAt': null},
  ],
};
