import 'dart:typed_data';

import '../models.dart';
import '../sova_repository.dart';
import 'api_client.dart';

/// [SovaRepository] backed by the Sova API.
class ApiRepository implements SovaRepository {
  ApiRepository(this._api);

  final ApiClient _api;

  @override
  String? get otpHint => null;

  @override
  Future<Session?> restoreSession() async {
    final user = await _api.resume();
    return user == null ? null : _session(user);
  }

  @override
  Future<void> requestOtp(String phone) => _api.post('/auth/otp/request', {'phone': phone});

  @override
  Future<Session> verifyOtp(String phone, String code) async {
    final res = await _api.post('/auth/otp/verify', {'phone': phone, 'code': code});
    return _session(await _api.startSession(res as Map<String, dynamic>));
  }

  @override
  Future<Session> startDemo() async {
    final res = await _api.post('/auth/demo');
    return _session(await _api.startSession(res as Map<String, dynamic>));
  }

  @override
  Future<void> signOut() => _api.endSession(tellServer: true);

  @override
  Future<Session> saveProfile({required String fullName, required String pin}) async {
    var user = await _api.patch('/me', {'fullName': fullName}) as Map<String, dynamic>;
    if (user['hasPin'] != true) user = await _api.post('/me/pin', {'pin': pin}) as Map<String, dynamic>;
    return _session(user);
  }

  @override
  Future<void> verifyPin(String pin) => _api.post('/me/pin/verify', {'pin': pin});

  @override
  Future<List<Circle>> myCircles() async {
    final res = await _api.get('/circles') as Map<String, dynamic>;
    final ids = [for (final c in res['circles'] as List) (c as Map<String, dynamic>)['id'] as String];
    return Future.wait(ids.map(circle));
  }

  @override
  Future<Circle> circle(String id) async => _circle(await _api.get('/circles/$id') as Map<String, dynamic>);

  @override
  Future<Circle> createCircle(NewCircle d, {required String pin}) async {
    final emergency = d.emergencyPolicy?.trim();
    final res = await _api.post('/circles', {
      'name': d.name.trim(),
      'contributionAmount': d.contributionAmount,
      'memberCount': d.memberCount,
      'cycleType': d.cycle.name,
      'startDate': _date(d.startDate),
      'adminCollectsLast': d.adminCollectsLast,
      'rules': {
        'lateFee': d.lateFee,
        'graceDays': d.graceDays,
        'earlyExitPolicy': _exitCodes[d.earlyExit],
        'emergencyPolicy': (emergency?.isEmpty ?? true) ? null : emergency,
      },
      'pin': pin,
    });
    return _circle(res as Map<String, dynamic>);
  }

  @override
  Future<Circle> findByInviteCode(String code) async {
    final clean = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final j = await _api.get('/circles/preview/$clean') as Map<String, dynamic>;
    if (j['alreadyMember'] == true) throw const SovaException('You are already in this circle.');
    if (j['status'] != 'forming') {
      throw const SovaException('This circle has already started. Ask the admin about the next one.');
    }
    if (j['isFull'] == true) throw const SovaException('This circle is already full.');
    final rules = j['rules'] as Map<String, dynamic>;
    return Circle(
      id: j['id'] as String,
      name: j['name'] as String,
      adminId: j['adminId'] as String,
      memberCount: j['memberCount'] as int,
      contributionAmount: j['contributionAmount'] as int,
      cycle: _cycle(j['cycleType']),
      startDate: DateTime.parse(j['startDate'] as String),
      inviteCode: j['inviteCode'] as String,
      status: CircleStatus.forming,
      adminCollectsLast: j['adminCollectsLast'] as bool,
      members: [
        for (final m in (j['members'] as List).cast<Map<String, dynamic>>())
          Member(userId: m['id'] as String, name: (m['name'] as String?) ?? 'Member', phone: '', position: null),
      ],
      rounds: const [],
      contributions: const [],
      rules: _rules(rules, const {}),
      draw: j['drawCommitment'] == null ? null : DrawInfo(commitment: j['drawCommitment'] as String),
    );
  }

  @override
  Future<Circle> joinCircle({
    required String code,
    String? voucherId,
    required int rulesVersion,
    required String pin,
  }) async {
    final res = await _api.post('/circles/join', {
      'code': code,
      'voucherId': voucherId,
      'rulesVersion': rulesVersion,
      'pin': pin,
    });
    return _circle(res as Map<String, dynamic>);
  }

  @override
  Future<Circle> acceptRules(String circleId, int version) async =>
      _circle(await _api.post('/circles/$circleId/rules/accept', {'version': version}) as Map<String, dynamic>);

  @override
  Future<String> uploadProof({
    required String circleId,
    required int roundNumber,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final res = await _api.postBytes('/circles/$circleId/rounds/$roundNumber/proof', bytes, contentType)
        as Map<String, dynamic>;
    return res['key'] as String;
  }

  @override
  Future<String> proofUrl(String contributionId) async =>
      ((await _api.get('/contributions/$contributionId/proof')) as Map<String, dynamic>)['url'] as String;

  @override
  Future<Circle> confirmMyPayment({
    required String circleId,
    required int roundNumber,
    String? bankReference,
    String? proofKey,
    required String pin,
  }) async {
    final res = await _api.post('/circles/$circleId/rounds/$roundNumber/pay', {
      'bankReference': bankReference,
      'proofKey': proofKey,
      'pin': pin,
    });
    return _circle(res as Map<String, dynamic>);
  }

  @override
  Future<Circle> confirmReceived({required String circleId, required String contributionId, required String pin}) async =>
      _circle(await _api.post('/contributions/$contributionId/confirm', {'pin': pin}) as Map<String, dynamic>);

  @override
  Future<PayoutResult> confirmPayout({
    required String circleId,
    required int roundNumber,
    required int amount,
    required String pin,
  }) async {
    final res = await _api.post('/circles/$circleId/rounds/$roundNumber/payout', {'amount': amount, 'pin': pin})
        as Map<String, dynamic>;
    return PayoutResult(
      shortfall: res['shortfall'] as int,
      nextRound: res['nextRound'] as int?,
      circle: _circle(res['circle'] as Map<String, dynamic>),
    );
  }

  // --- JSON -> models ---------------------------------------------------------

  static Session _session(Map<String, dynamic> u) => Session(
        phone: u['phone'] as String,
        userId: u['id'] as String,
        fullName: u['fullName'] as String?,
        hasPin: u['hasPin'] as bool,
        isDemo: (u['isDemo'] as bool?) ?? false,
      );

  static Circle _circle(Map<String, dynamic> j) {
    final current = j['currentRound'] as Map<String, dynamic>?;
    final collector = current?['collector'] as Map<String, dynamic>?;
    final collectorBank = collector?['bank'] as Map<String, dynamic>?;
    final members = (j['members'] as List).cast<Map<String, dynamic>>();

    return Circle(
      id: j['id'] as String,
      name: j['name'] as String,
      adminId: j['adminId'] as String,
      memberCount: j['memberCount'] as int,
      contributionAmount: j['contributionAmount'] as int,
      cycle: _cycle(j['cycleType']),
      startDate: DateTime.parse(j['startDate'] as String),
      inviteCode: j['inviteCode'] as String,
      status: CircleStatus.values.byName(j['status'] as String),
      adminCollectsLast: j['adminCollectsLast'] as bool,
      openDisputes: (j['openDisputes'] as int?) ?? 0,
      members: [
        for (final m in members)
          Member(
            userId: m['id'] as String,
            name: (m['name'] as String?) ?? 'Member',
            phone: (m['phone'] as String?) ?? '',
            position: m['position'] as int?,
            vouchedBy: (m['vouchedBy'] as Map<String, dynamic>?)?['id'] as String?,
            owesAfterCollecting: (m['owesAfterCollecting'] as bool?) ?? false,
            // Bank details are shared only for this turn's collector, so payers know where to send money.
            bank: collectorBank != null && collector!['id'] == m['id']
                ? BankDetails(
                    bankName: collectorBank['bankName'] as String,
                    accountNumber: collectorBank['accountNumber'] as String,
                    accountName: collectorBank['accountName'] as String,
                  )
                : null,
          ),
      ],
      rounds: [
        for (final r in (j['rounds'] as List).cast<Map<String, dynamic>>())
          Round(
            id: r['id'] as String,
            number: r['number'] as int,
            collectorId: r['collectorId'] as String,
            dueDate: DateTime.parse(r['dueDate'] as String),
            status: RoundStatus.values.byName(r['status'] as String),
            payoutReceived: r['payoutReceived'] as int?,
          ),
      ],
      contributions: [
        for (final c in (j['contributions'] as List).cast<Map<String, dynamic>>())
          Contribution(
            id: c['id'] as String,
            roundId: c['roundId'] as String,
            userId: c['userId'] as String,
            amount: c['amount'] as int,
            status: _contributionStatus[c['status']] ?? ContributionStatus.pending,
            bankReference: c['bankReference'] as String?,
            hasProof: (c['hasProof'] as bool?) ?? false,
            payerConfirmedAt: c['paidAt'] == null ? null : DateTime.parse(c['paidAt'] as String).toLocal(),
            reference: 'SV-${(c['id'] as String).substring(0, 8).toUpperCase()}',
          ),
      ],
      rules: j['rules'] == null
          ? null
          : _rules(j['rules'] as Map<String, dynamic>, {
              for (final m in members)
                if (m['acceptedRules'] == true) m['id'] as String,
            }),
      draw: j['draw'] == null ? null : _draw(j['draw'] as Map<String, dynamic>),
    );
  }

  static GroupRules _rules(Map<String, dynamic> r, Set<String> acceptedBy) => GroupRules(
        version: r['version'] as int,
        lateFee: r['lateFee'] as int,
        graceDays: r['graceDays'] as int,
        earlyExit: _exitPolicies[r['earlyExitPolicy']] ?? EarlyExitPolicy.findReplacement,
        emergencyPolicy: r['emergencyPolicy'] as String?,
        acceptedBy: acceptedBy,
      );

  static DrawInfo _draw(Map<String, dynamic> d) => DrawInfo(
        commitment: d['commitment'] as String,
        seed: d['seed'] as String?,
        revealedAt: d['revealedAt'] == null ? null : DateTime.parse(d['revealedAt'] as String).toLocal(),
      );

  static CycleType _cycle(Object? v) => CycleType.values.byName(v as String);

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static const _contributionStatus = {
    'pending': ContributionStatus.pending,
    'payer_confirmed': ContributionStatus.payerConfirmed,
    'fully_confirmed': ContributionStatus.fullyConfirmed,
    'disputed': ContributionStatus.disputed,
  };

  static const _exitPolicies = {
    'find_replacement': EarlyExitPolicy.findReplacement,
    'refund_after_cycle': EarlyExitPolicy.refundAfterCycle,
    'forfeit_fee': EarlyExitPolicy.forfeitFee,
  };

  static final _exitCodes = {for (final e in _exitPolicies.entries) e.value: e.key};
}
