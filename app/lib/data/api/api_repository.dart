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

  static Session _session(Map<String, dynamic> u) {
    final bank = u['bank'] as Map<String, dynamic>?;
    return Session(
      phone: u['phone'] as String,
      userId: u['id'] as String,
      fullName: u['fullName'] as String?,
      hasPin: u['hasPin'] as bool,
      isDemo: (u['isDemo'] as bool?) ?? false,
      bank: bank == null
          ? null
          : BankDetails(
              bankName: bank['bankName'] as String,
              accountNumber: bank['accountNumber'] as String,
              accountName: bank['accountName'] as String,
            ),
    );
  }

  @override
  Future<Session> updateName(String fullName) async =>
      _session(await _api.patch('/me', {'fullName': fullName.trim()}) as Map<String, dynamic>);

  @override
  Future<List<String>> banks() async {
    final res = await _api.get('/banks') as Map<String, dynamic>;
    return [for (final b in (res['banks'] as List).cast<Map<String, dynamic>>()) b['name'] as String];
  }

  @override
  Future<Session> saveBank({required BankDetails bank, required String pin}) async => _session(await _api.put('/me/bank', {
        'bankName': bank.bankName,
        'accountNumber': bank.accountNumber,
        'accountName': bank.accountName,
        'pin': pin,
      }) as Map<String, dynamic>);

  @override
  Future<void> changePin({required String currentPin, required String newPin}) =>
      _api.post('/me/pin/change', {'currentPin': currentPin, 'newPin': newPin});

  @override
  Future<Inbox> notifications() async {
    final j = await _api.get('/me/notifications') as Map<String, dynamic>;
    return Inbox(
      reminders: [
        for (final r in (j['reminders'] as List).cast<Map<String, dynamic>>())
          Reminder(kind: r['kind'] as String, title: r['title'] as String, message: r['message'] as String, link: r['link'] as String),
      ],
      items: [
        for (final n in (j['items'] as List).cast<Map<String, dynamic>>())
          AppNotification(
            id: n['id'] as String,
            type: n['type'] as String,
            title: n['title'] as String,
            message: n['message'] as String,
            read: n['read'] as bool,
            createdAt: _time(n['createdAt']),
            link: n['link'] as String?,
          ),
      ],
      badge: j['badge'] as int,
    );
  }

  @override
  Future<void> markNotificationsRead() => _api.post('/me/notifications/read');

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

  @override
  Future<List<Dispute>> disputes(String circleId) async {
    final res = await _api.get('/circles/$circleId/disputes') as Map<String, dynamic>;
    return [for (final d in (res['disputes'] as List).cast<Map<String, dynamic>>()) _dispute(d)];
  }

  @override
  Future<Dispute> dispute(String id) async => _dispute(await _api.get('/disputes/$id') as Map<String, dynamic>);

  @override
  Future<Dispute> raiseDispute({required String contributionId, required String reason, required String pin}) async =>
      _dispute(await _api.post('/contributions/$contributionId/dispute', {'reason': reason, 'pin': pin})
          as Map<String, dynamic>);

  @override
  Future<Dispute> voteDispute({required String disputeId, required DisputeSide side, required String pin}) async =>
      _dispute(await _api.post('/disputes/$disputeId/vote', {'side': side.name, 'pin': pin}) as Map<String, dynamic>);

  @override
  Future<Dispute> settleDispute({required String disputeId, required String pin}) async =>
      _dispute(await _api.post('/disputes/$disputeId/settle', {'pin': pin}) as Map<String, dynamic>);

  @override
  Future<Dispute> commentOnDispute({required String disputeId, required String message}) async =>
      _dispute(await _api.post('/disputes/$disputeId/comments', {'message': message}) as Map<String, dynamic>);

  @override
  Future<SovaScore> myScore() async => _score(await _api.get('/me/score') as Map<String, dynamic>);

  @override
  Future<SovaScore> shareScore({required String pin}) async =>
      _score(await _api.post('/me/score/share', {'pin': pin}) as Map<String, dynamic>);

  @override
  Future<SovaScore> stopSharingScore() async =>
      _score(await _api.post('/me/score/share/stop') as Map<String, dynamic>);

  static SovaScore _score(Map<String, dynamic> j) {
    final share = j['share'] as Map<String, dynamic>?;
    double rate(String k) => (j[k] as num).toDouble();
    return SovaScore(
      minimumPayments: j['minimumPayments'] as int,
      score: j['score'] as int?,
      band: j['band'] as String?,
      onTimeRate: rate('onTimeRate'),
      consistencyRate: rate('consistencyRate'),
      completionRate: rate('completionRate'),
      confirmedPayments: j['confirmedPayments'] as int,
      onTimePayments: j['onTimePayments'] as int,
      activeCircles: j['activeCircles'] as int,
      completedCircles: j['completedCircles'] as int,
      share: share == null
          ? null
          : ScoreShare(
              token: share['token'] as String,
              sharedAt: _time(share['sharedAt']),
              score: share['score'] as int,
            ),
    );
  }

  @override
  Future<TurnChanges> turnChanges(String circleId) async =>
      _turnChanges(await _api.get('/circles/$circleId/turn-changes') as Map<String, dynamic>);

  @override
  Future<TurnChanges> requestSwap({required String circleId, required String targetId, String? reason, required String pin}) async =>
      _turnChanges(await _api.post('/circles/$circleId/swaps', {'targetId': targetId, 'reason': reason, 'pin': pin})
          as Map<String, dynamic>);

  @override
  Future<TurnChanges> answerSwap({required String circleId, required String swapId, required bool accept, String? pin}) async =>
      _turnChanges(await _api.post('/swaps/$swapId/${accept ? 'accept' : 'decline'}', accept ? {'pin': pin} : null)
          as Map<String, dynamic>);

  @override
  Future<TurnChanges> cancelSwap({required String circleId, required String swapId}) async =>
      _turnChanges(await _api.post('/swaps/$swapId/cancel') as Map<String, dynamic>);

  @override
  Future<TurnChanges> requestHandover({required String circleId, required String phone, String? reason, required String pin}) async =>
      _turnChanges(await _api.post('/circles/$circleId/handovers', {'phone': phone, 'reason': reason, 'pin': pin})
          as Map<String, dynamic>);

  @override
  Future<TurnChanges> decideHandover({required String circleId, required String handoverId, required bool approve, String? pin}) async =>
      _turnChanges(await _api.post('/handovers/$handoverId/${approve ? 'approve' : 'reject'}', approve ? {'pin': pin} : null)
          as Map<String, dynamic>);

  @override
  Future<TurnChanges> cancelHandover({required String circleId, required String handoverId}) async =>
      _turnChanges(await _api.post('/handovers/$handoverId/cancel') as Map<String, dynamic>);

  @override
  Future<List<HandoverOffer>> handoverOffers() async =>
      _offers(await _api.get('/me/handover-offers') as Map<String, dynamic>);

  @override
  Future<List<HandoverOffer>> answerHandover({required String handoverId, required bool accept, int? rulesVersion, String? pin}) async =>
      _offers(await _api.post(
        '/handovers/$handoverId/${accept ? 'accept' : 'decline'}',
        accept ? {'rulesVersion': rulesVersion, 'pin': pin} : null,
      ) as Map<String, dynamic>);

  static TurnPerson _turnPerson(Map<String, dynamic> p) =>
      TurnPerson(id: p['id'] as String, name: p['name'] as String, turn: p['turn'] as int?);

  static TurnChanges _turnChanges(Map<String, dynamic> j) => TurnChanges(
        swaps: [
          for (final s in (j['swaps'] as List).cast<Map<String, dynamic>>())
            SwapRequest(
              id: s['id'] as String,
              status: SwapStatus.values.byName(s['status'] as String),
              createdAt: _time(s['createdAt']),
              requester: _turnPerson(s['requester'] as Map<String, dynamic>),
              target: _turnPerson(s['target'] as Map<String, dynamic>),
              reason: s['reason'] as String?,
              canAnswer: s['canAnswer'] as bool,
              canCancel: s['canCancel'] as bool,
            ),
        ],
        handovers: [
          for (final h in (j['handovers'] as List).cast<Map<String, dynamic>>())
            Handover(
              id: h['id'] as String,
              status: HandoverStatus.values.byName(h['status'] as String),
              createdAt: _time(h['createdAt']),
              leaving: _turnPerson(h['leaving'] as Map<String, dynamic>),
              replacement: _turnPerson(h['replacement'] as Map<String, dynamic>),
              paidIn: h['paidIn'] as int,
              reason: h['reason'] as String?,
              canApprove: h['canApprove'] as bool,
              canCancel: h['canCancel'] as bool,
            ),
        ],
      );

  static List<HandoverOffer> _offers(Map<String, dynamic> j) => [
        for (final o in (j['offers'] as List).cast<Map<String, dynamic>>())
          HandoverOffer(
            id: o['id'] as String,
            createdAt: _time(o['createdAt']),
            leavingName: (o['leaving'] as Map<String, dynamic>)['name'] as String,
            paidIn: o['paidIn'] as int,
            turn: o['turn'] as int?,
            reason: o['reason'] as String?,
            circleId: (o['circle'] as Map<String, dynamic>)['id'] as String,
            circleName: (o['circle'] as Map<String, dynamic>)['name'] as String,
            contributionAmount: (o['circle'] as Map<String, dynamic>)['contributionAmount'] as int,
            payoutAmount: (o['circle'] as Map<String, dynamic>)['payoutAmount'] as int,
            memberCount: (o['circle'] as Map<String, dynamic>)['memberCount'] as int,
            cycle: _cycle((o['circle'] as Map<String, dynamic>)['cycleType']),
            rules: _rules(o['rules'] as Map<String, dynamic>, const {}),
          ),
      ];

  static Person _person(Map<String, dynamic> p) => Person(id: p['id'] as String, name: p['name'] as String);

  static DateTime _time(Object? v) => DateTime.parse(v as String).toLocal();

  static Dispute _dispute(Map<String, dynamic> j) {
    final votes = j['votes'] as Map<String, dynamic>;
    final payment = j['payment'] as Map<String, dynamic>?;
    return Dispute(
      id: j['id'] as String,
      circleId: j['circleId'] as String,
      kind: DisputeKind.values.byName(j['kind'] as String),
      status: _disputeStatus[j['status']] ?? DisputeStatus.open,
      turn: j['turn'] as int,
      reason: j['reason'] as String,
      createdAt: _time(j['createdAt']),
      resolvedAt: j['resolvedAt'] == null ? null : _time(j['resolvedAt']),
      resolutionNote: j['resolutionNote'] as String?,
      raisedBy: _person(j['raisedBy'] as Map<String, dynamic>),
      collector: _person(j['collector'] as Map<String, dynamic>),
      payers: [for (final p in (j['payers'] as List).cast<Map<String, dynamic>>()) _person(p)],
      payment: payment == null
          ? null
          : DisputePayment(
              contributionId: payment['id'] as String,
              amount: payment['amount'] as int,
              bankReference: payment['bankReference'] as String?,
              hasProof: (payment['hasProof'] as bool?) ?? false,
              paidAt: payment['paidAt'] == null ? null : _time(payment['paidAt']),
            ),
      myRole: DisputeRole.values.byName(j['myRole'] as String),
      payerVotes: votes['payer'] as int,
      collectorVotes: votes['collector'] as int,
      eligibleVoters: votes['eligible'] as int,
      myVote: votes['mine'] == null ? null : DisputeSide.values.byName(votes['mine'] as String),
      votes: [
        for (final v in (votes['cast'] as List).cast<Map<String, dynamic>>())
          DisputeVote(
            voter: _person(v['voter'] as Map<String, dynamic>),
            side: DisputeSide.values.byName(v['side'] as String),
            at: _time(v['at']),
          ),
      ],
      timeline: [
        for (final e in ((j['timeline'] as List?) ?? const []).cast<Map<String, dynamic>>())
          DisputeEvent(
            actor: _person(e['actor'] as Map<String, dynamic>),
            kind: e['kind'] as String,
            message: e['message'] as String?,
            at: _time(e['at']),
          ),
      ],
      canVote: j['canVote'] as bool,
      canSettle: j['canSettle'] as bool,
    );
  }

  static const _disputeStatus = {
    'open': DisputeStatus.open,
    'resolved_for_payer': DisputeStatus.resolvedForPayer,
    'resolved_for_collector': DisputeStatus.resolvedForCollector,
    'withdrawn': DisputeStatus.withdrawn,
  };

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
        order: d['order'] == null
            ? null
            : [for (final p in (d['order'] as List).cast<Map<String, dynamic>>()) _person(p)],
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
