import 'dart:math';
import 'dart:typed_data';

import '../core/format.dart';
import 'fair_draw.dart';
import 'models.dart';
import 'sova_repository.dart';

/// In-memory backend for tests and offline demos. It follows the same rules
/// as the API (forming until full, turns drawn at the start, payout from the
/// other members, PIN on money actions, commit-reveal draw). The OTP is always
/// [demoOtp]; data resets when the app restarts.
class DemoRepository implements SovaRepository {
  DemoRepository() {
    _seed();
  }

  static const demoOtp = '123456';
  static const demoPin = '2580';
  static const me = 'me';

  final _random = Random();
  final _circles = <String, Circle>{};

  /// Draw seeds stay secret here until the turns are drawn, as on the server.
  final _drawSeeds = <String, String>{};
  final _disputes = <String, _DemoDispute>{};
  final _swaps = <_DemoSwap>[];
  final _handovers = <_DemoHandover>[];
  Session? _session;
  String? _pin;
  int _pinFailures = 0;
  DateTime? _pinLockedUntil;

  Future<void> _latency() => Future.delayed(const Duration(milliseconds: 350));

  String _reference() => 'SV-${1000 + _random.nextInt(9000)}';

  @override
  String? get otpHint => 'Demo mode: use the code $demoOtp.';

  @override
  Future<Session?> restoreSession() async => null;

  @override
  Future<void> requestOtp(String phone) => _latency();

  @override
  Future<Session> verifyOtp(String phone, String code) async {
    await _latency();
    if (code != demoOtp) throw const SovaException('That code is not correct. Check the SMS and try again.');
    return _session = Session(phone: phone, userId: me);
  }

  @override
  Future<Session> startDemo() async {
    await _latency();
    _pin = demoPin;
    _renameMe('Ada Obi', '+2348000000000');
    return _session = const Session(phone: '+2348000000000', userId: me, fullName: 'Ada Obi', hasPin: true, isDemo: true);
  }

  @override
  Future<void> signOut() async => _session = null;

  @override
  Future<Session> saveProfile({required String fullName, required String pin}) async {
    await _latency();
    _pin = pin;
    final session = _session!.copyWith(fullName: fullName, hasPin: true);
    _session = session;
    _renameMe(fullName, session.phone);
    return session;
  }

  @override
  Future<void> verifyPin(String pin) async {
    await _latency();
    _checkPin(pin);
  }

  @override
  Future<Session> updateName(String fullName) async {
    await _latency();
    final name = fullName.trim();
    if (name.length < 2) throw const SovaException('Enter your full name.');
    _session = _session!.copyWith(fullName: name);
    _renameMe(name, _session!.phone);
    return _session!;
  }

  @override
  Future<List<String>> banks() async => const [
        'Access Bank', 'Ecobank', 'Fidelity Bank', 'First Bank', 'FCMB', 'GTBank', 'Kuda', 'Moniepoint MFB', 'OPay',
        'PalmPay', 'Polaris Bank', 'Stanbic IBTC', 'Sterling Bank', 'UBA', 'Union Bank', 'Wema Bank', 'Zenith Bank',
      ];

  @override
  Future<Session> saveBank({required BankDetails bank, required String pin}) async {
    await _latency();
    _checkPin(pin);
    if (!RegExp(r'^\d{10}$').hasMatch(bank.accountNumber)) throw const SovaException('Account numbers are 10 digits.');
    if (bank.accountName.trim().length < 2) throw const SovaException('Enter the name on the account.');
    _session = _session!.copyWith(bank: bank);
    for (final c in _circles.values.toList()) {
      _circles[c.id] = _copyCircle(c, members: [
        for (final m in c.members)
          m.userId == me
              ? Member(userId: me, name: m.name, phone: m.phone, position: m.position, bank: bank, vouchedBy: m.vouchedBy)
              : m,
      ]);
    }
    return _session!;
  }

  @override
  Future<void> changePin({required String currentPin, required String newPin}) async {
    await _latency();
    _checkPin(currentPin);
    if (isEasyPin(newPin)) throw const SovaException('That PIN is too easy to guess. Choose another.', code: 'weak_pin');
    if (newPin == currentPin) {
      throw const SovaException("Choose a PIN that's different from your current one.", code: 'same_pin');
    }
    _pin = newPin;
  }

  /// Seeded notifications; the server writes these from real events.
  late final _inbox = <AppNotification>[
    AppNotification(
      id: 'n-swap',
      type: 'swap_request',
      title: 'Zainab asks to swap turns with you',
      message: 'Office Esusu',
      read: false,
      createdAt: DateTime.now().subtract(const Duration(hours: 20)),
      link: '/circle/office-esusu/turns',
    ),
    AppNotification(
      id: 'n-emeka',
      type: 'payment_marked',
      title: 'Emeka marked ₦10,000 as sent',
      message: "Unilag Class of '24 Ajo, turn 2. Check your bank, then confirm it arrived.",
      read: false,
      createdAt: DateTime.now().subtract(const Duration(hours: 26)),
      link: '/circle/class-ajo',
    ),
    AppNotification(
      id: 'n-turn',
      type: 'turn_opened',
      title: 'Turn 3: pay Halima ₦20,000',
      message: 'Office Esusu. Due in a week.',
      read: true,
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
      link: '/circle/office-esusu',
    ),
  ];

  @override
  Future<Inbox> notifications() async {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final reminders = <Reminder>[];
    for (final c in _circles.values.where((c) => c.memberById(me) != null)) {
      final r = c.activeRound;
      if (r == null) continue;
      if (r.collectorId == me) {
        final n = c.contributions.where((x) => x.roundId == r.id && x.status == ContributionStatus.payerConfirmed).length;
        if (n > 0) {
          reminders.add(Reminder(
            kind: 'confirm',
            title: '$n payment${n == 1 ? '' : 's'} to confirm',
            message: '${c.name}. Check your bank, then confirm what arrived.',
            link: '/circle/${c.id}',
          ));
        }
        continue;
      }
      final days = r.dueDate.difference(day).inDays;
      if (c.statusFor(r.id, me) == ContributionStatus.pending && days <= 2) {
        final who = c.currentCollector?.firstName ?? 'the collector';
        reminders.add(Reminder(
          kind: days < 0 ? 'overdue' : 'due',
          title: 'Pay $who ${naira(c.contributionAmount)}',
          message: days < 0
              ? '${c.name}, turn ${r.number}. ${-days} day${days == -1 ? '' : 's'} late.'
              : '${c.name}, turn ${r.number}. Due ${days == 0 ? 'today' : days == 1 ? 'tomorrow' : shortDate(r.dueDate)}.',
          link: '/circle/${c.id}/pay',
        ));
      }
    }
    return Inbox(
      reminders: reminders,
      items: List.of(_inbox),
      badge: _inbox.where((n) => !n.read).length + reminders.length,
    );
  }

  @override
  Future<void> markNotificationsRead() async {
    for (final (i, n) in _inbox.indexed) {
      _inbox[i] = AppNotification(
        id: n.id,
        type: n.type,
        title: n.title,
        message: n.message,
        read: true,
        createdAt: n.createdAt,
        link: n.link,
      );
    }
  }

  void _checkPin(String pin) {
    final now = DateTime.now();
    if (_pinLockedUntil != null && _pinLockedUntil!.isAfter(now)) {
      throw const SovaException('Too many wrong tries. Your PIN is locked for 15 minutes.', code: 'pin_locked');
    }
    if (pin != _pin) {
      _pinFailures++;
      if (_pinFailures >= 5) {
        _pinFailures = 0;
        _pinLockedUntil = now.add(const Duration(minutes: 15));
        throw const SovaException('Too many wrong tries. Your PIN is locked for 15 minutes.', code: 'pin_locked');
      }
      throw SovaException('Wrong PIN. ${5 - _pinFailures} tries left.', code: 'wrong_pin');
    }
    _pinFailures = 0;
  }

  @override
  Future<List<Circle>> myCircles() async {
    await _latency();
    // Newest first; only circles the signed-in member belongs to.
    return _circles.values.where((c) => c.memberById(me) != null).toList().reversed.toList();
  }

  @override
  Future<Circle> circle(String id) async {
    await _latency();
    final c = _circles[id];
    if (c == null || c.memberById(me) == null) throw const SovaException('Circle not found.');
    return c;
  }

  @override
  Future<Circle> createCircle(NewCircle d, {required String pin}) async {
    await _latency();
    _checkPin(pin);
    final name = d.name.trim();
    if (name.length < 2) throw const SovaException('Give your circle a name.');
    if (d.contributionAmount < 100) throw const SovaException('The contribution must be at least ₦100.');
    final id = 'circle-${_random.nextInt(1000000000)}';
    final seed = [for (var i = 0; i < 32; i++) Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')].join();
    _drawSeeds[id] = seed;
    final circle = Circle(
      id: id,
      name: name,
      adminId: me,
      memberCount: d.memberCount,
      contributionAmount: d.contributionAmount,
      cycle: d.cycle,
      startDate: d.startDate,
      inviteCode: _newInviteCode(),
      status: CircleStatus.forming,
      adminCollectsLast: d.adminCollectsLast,
      draw: DrawInfo(commitment: commitmentOf(seed)),
      members: [Member(userId: me, name: _session?.fullName ?? 'You', phone: _session?.phone ?? '', position: null)],
      rounds: const [],
      contributions: const [],
      rules: GroupRules(
        version: 1,
        lateFee: d.lateFee,
        graceDays: d.graceDays,
        earlyExit: d.earlyExit,
        emergencyPolicy: (d.emergencyPolicy?.trim().isEmpty ?? true) ? null : d.emergencyPolicy!.trim(),
        acceptedBy: const {me},
      ),
    );
    _circles[id] = circle;
    return circle;
  }

  @override
  Future<Circle> findByInviteCode(String code) async {
    await _latency();
    final c = _byCode(code);
    if (c.memberById(me) != null) throw const SovaException('You are already in this circle.');
    if (!c.forming) throw const SovaException('This circle has already started. Ask the admin about the next one.');
    if (c.members.length >= c.memberCount) throw const SovaException('This circle is already full.');
    return c;
  }

  @override
  Future<Circle> joinCircle({
    required String code,
    String? voucherId,
    required int rulesVersion,
    required String pin,
  }) async {
    await _latency();
    _checkPin(pin);
    final c = await findByInviteCode(code);
    if (voucherId != null && c.memberById(voucherId) == null) {
      throw const SovaException('The person vouching for you must already be in this circle.');
    }
    if (c.rules != null && c.rules!.version != rulesVersion) {
      throw const SovaException('The rules changed while you were reading. Please read them again.');
    }
    final joined = _copyCircle(
      c,
      members: [
        ...c.members,
        Member(userId: me, name: _session?.fullName ?? 'You', phone: _session?.phone ?? '', position: null, vouchedBy: voucherId),
      ],
      rules: c.rules == null ? null : _withAcceptance(c.rules!, me),
    );
    return _circles[c.id] = _startIfReady(joined);
  }

  @override
  Future<Circle> acceptRules(String circleId, int version) async {
    await _latency();
    final c = await circle(circleId);
    if (c.rules == null || c.rules!.version != version) {
      throw const SovaException('The rules changed while you were reading. Please read them again.');
    }
    return _circles[circleId] = _startIfReady(_copyCircle(c, rules: _withAcceptance(c.rules!, me)));
  }

  @override
  Future<String> uploadProof({
    required String circleId,
    required int roundNumber,
    required Uint8List bytes,
    required String contentType,
  }) async {
    await _latency();
    if (bytes.length > 5 * 1024 * 1024) throw const SovaException('Photos can be up to 5 MB.');
    return 'demo/$circleId/$roundNumber/${_random.nextInt(1000000000)}';
  }

  @override
  Future<String> proofUrl(String contributionId) async {
    await _latency();
    throw const SovaException('Receipt photos are only stored when Sova runs on the server.');
  }

  @override
  Future<Circle> confirmMyPayment({
    required String circleId,
    required int roundNumber,
    String? bankReference,
    String? proofKey,
    required String pin,
  }) async {
    await _latency();
    _checkPin(pin);
    final c = await circle(circleId);
    final round = c.rounds.where((r) => r.number == roundNumber).firstOrNull;
    if (round == null || round.status == RoundStatus.pending) throw const SovaException('This turn has not started yet.');
    if (round.collectorId == me) throw const SovaException("You collect this turn, so you don't pay into it.");
    final existing = c.contributionFor(round.id, me);
    if (existing?.status == ContributionStatus.fullyConfirmed) {
      throw const SovaException('The collector already confirmed this payment.');
    }
    if (existing?.status == ContributionStatus.disputed) throw const SovaException('This payment is under dispute.');
    _replaceContribution(
      c,
      Contribution(
        id: existing?.id ?? 'c-${_random.nextInt(1000000000)}',
        roundId: round.id,
        userId: me,
        amount: c.contributionAmount,
        status: ContributionStatus.payerConfirmed,
        bankReference: bankReference ?? existing?.bankReference,
        hasProof: proofKey != null || (existing?.hasProof ?? false),
        payerConfirmedAt: existing?.payerConfirmedAt ?? DateTime.now(),
        reference: existing?.reference ?? _reference(),
      ),
    );
    return _circles[circleId]!;
  }

  @override
  Future<Circle> confirmReceived({required String circleId, required String contributionId, required String pin}) async {
    await _latency();
    _checkPin(pin);
    final c = await circle(circleId);
    final old = c.contributions.firstWhere((x) => x.id == contributionId);
    final round = c.rounds.firstWhere((r) => r.id == old.roundId);
    if (round.collectorId != me) throw const SovaException('Only the collector for this turn can confirm payments.');
    if (old.status != ContributionStatus.payerConfirmed) {
      throw const SovaException("This member hasn't marked the payment as sent yet.");
    }
    _replaceContribution(
      c,
      Contribution(
        id: old.id,
        roundId: old.roundId,
        userId: old.userId,
        amount: old.amount,
        status: ContributionStatus.fullyConfirmed,
        bankReference: old.bankReference,
        hasProof: old.hasProof,
        payerConfirmedAt: old.payerConfirmedAt,
        reference: old.reference ?? _reference(),
      ),
    );
    _settleShortfalls(circleId, old.roundId);
    return _circles[circleId]!;
  }

  @override
  Future<PayoutResult> confirmPayout({
    required String circleId,
    required int roundNumber,
    required int amount,
    required String pin,
  }) async {
    await _latency();
    _checkPin(pin);
    final c = await circle(circleId);
    final round = c.activeRound;
    if (round == null || round.number != roundNumber) throw const SovaException('This is not the current turn.');
    if (round.collectorId != me) throw const SovaException('Only the collector for this turn can confirm the payout.');
    if (amount < 0) throw const SovaException('The amount cannot be negative.');

    final shortfall = max(c.payout - amount, 0);
    // Approved handovers take effect as this turn ends, before the next collector is chosen.
    _onTurnEnded(c.id);
    final ended = _circles[circleId]!;
    final next = ended.membersByPosition.where((m) => m.position == round.number + 1).firstOrNull;
    final rounds = [
      for (final r in c.rounds)
        r.id == round.id
            ? Round(
                id: r.id,
                number: r.number,
                collectorId: r.collectorId,
                dueDate: r.dueDate,
                status: RoundStatus.completed,
                payoutReceived: amount,
              )
            : r,
      if (next != null)
        Round(
          id: '${c.id}-r${round.number + 1}',
          number: round.number + 1,
          collectorId: next.userId,
          dueDate: _step(c.cycle, round.dueDate),
          status: RoundStatus.active,
        ),
    ];
    _circles[circleId] = _copyCircle(ended, rounds: rounds, status: next == null ? CircleStatus.completed : c.status);
    if (next != null) _onTurnStarted(circleId, next.userId);
    if (shortfall > 0) {
      final id = 'd-${_random.nextInt(1000000000)}';
      _disputes[id] = _DemoDispute(
        id: id,
        circleId: c.id,
        roundId: round.id,
        kind: DisputeKind.shortfall,
        raisedBy: me,
        reason: 'Turn ${round.number} payout was ${naira(shortfall)} short: '
            'expected ${naira(c.payout)}, received ${naira(amount)}.',
        createdAt: DateTime.now(),
      )..events.add((me, 'opened', 'Opened automatically when the collector confirmed a short payout.', DateTime.now()));
      _syncOpenDisputes(c.id);
    }
    final updated = _circles[circleId]!;
    return PayoutResult(shortfall: shortfall, nextRound: next == null ? null : round.number + 1, circle: updated);
  }

  @override
  Future<List<Dispute>> disputes(String circleId) async {
    await circle(circleId);
    final list = _disputes.values.where((d) => d.circleId == circleId).toList()
      ..sort((a, b) {
        final byOpen = (b.status == DisputeStatus.open ? 1 : 0) - (a.status == DisputeStatus.open ? 1 : 0);
        return byOpen != 0 ? byOpen : b.createdAt.compareTo(a.createdAt);
      });
    return [for (final d in list) _disputeView(d, withTimeline: false)];
  }

  @override
  Future<Dispute> dispute(String id) async {
    await _latency();
    return _disputeView(_ownDispute(id));
  }

  @override
  Future<Dispute> raiseDispute({required String contributionId, required String reason, required String pin}) async {
    await _latency();
    _checkPin(pin);
    final c = _circles.values
        .where((c) => c.memberById(me) != null && c.contributions.any((x) => x.id == contributionId))
        .firstOrNull;
    if (c == null) throw const SovaException('Payment not found.');
    final x = c.contributions.firstWhere((x) => x.id == contributionId);
    final round = c.rounds.firstWhere((r) => r.id == x.roundId);
    if (me != round.collectorId && me != x.userId) {
      throw const SovaException('Only the payer or the collector can dispute this payment.', code: 'not_party');
    }
    if (x.status == ContributionStatus.disputed) throw const SovaException('This payment is already under dispute.');
    if (x.status != ContributionStatus.payerConfirmed) {
      throw const SovaException('Only a payment marked as sent can be disputed.');
    }
    final text = reason.trim();
    if (text.length < 3) throw const SovaException('Say what went wrong.');

    final id = 'd-${_random.nextInt(1000000000)}';
    _disputes[id] = _DemoDispute(
      id: id,
      circleId: c.id,
      roundId: round.id,
      kind: DisputeKind.payment,
      contributionId: x.id,
      raisedBy: me,
      reason: text,
      createdAt: DateTime.now(),
    )..events.add((me, 'opened', text, DateTime.now()));
    _setContributionStatus(c.id, x.id, ContributionStatus.disputed);
    _syncOpenDisputes(c.id);
    return _disputeView(_disputes[id]!);
  }

  @override
  Future<Dispute> voteDispute({required String disputeId, required DisputeSide side, required String pin}) async {
    await _latency();
    final d = _ownDispute(disputeId);
    _checkPin(pin);
    if (d.status != DisputeStatus.open) throw const SovaException('This dispute is already closed.');
    if (d.kind != DisputeKind.payment) {
      throw const SovaException('A shortfall closes when the missing payments are confirmed; there is nothing to vote on.');
    }
    final view = _disputeView(d);
    if (view.myRole != DisputeRole.voter) {
      throw const SovaException('You are part of this dispute, so the other members decide it.',
          code: 'party_cannot_vote');
    }
    d.votes[me] = (side, DateTime.now());
    final count = d.votes.values.where((v) => v.$1 == side).length;
    if (count * 2 > view.eligibleVoters) {
      _resolve(
        d,
        side == DisputeSide.payer ? DisputeStatus.resolvedForPayer : DisputeStatus.resolvedForCollector,
        me,
        'Decided by the circle: $count of ${view.eligibleVoters} members voted that '
        '${side == DisputeSide.payer ? 'the money arrived' : 'the money did not arrive'}.',
      );
    }
    return _disputeView(d);
  }

  @override
  Future<Dispute> settleDispute({required String disputeId, required String pin}) async {
    await _latency();
    final d = _ownDispute(disputeId);
    _checkPin(pin);
    if (d.status != DisputeStatus.open) throw const SovaException('This dispute is already closed.');
    final role = _disputeView(d).myRole;
    final name = _circles[d.circleId]!.memberById(me)!.firstName;
    if (role == DisputeRole.collector) {
      _resolve(d, DisputeStatus.resolvedForPayer, me,
          d.kind == DisputeKind.payment ? '$name confirmed the money arrived.' : '$name marked the shortfall as settled.');
    } else if (role == DisputeRole.payer && d.kind == DisputeKind.payment) {
      _resolve(d, DisputeStatus.resolvedForCollector, me, '$name agreed the payment did not arrive and can pay again.');
    } else {
      throw const SovaException('Only the payer or the collector can settle this dispute.', code: 'not_party');
    }
    return _disputeView(d);
  }

  @override
  Future<Dispute> commentOnDispute({required String disputeId, required String message}) async {
    await _latency();
    final d = _ownDispute(disputeId);
    if (d.status != DisputeStatus.open) throw const SovaException('This dispute is already closed.');
    final text = message.trim();
    if (text.isEmpty) throw const SovaException('Write a message.');
    d.events.add((me, 'comment', text, DateTime.now()));
    return _disputeView(d);
  }

  /// The same rules as the database's sova_score_now: 60% on time, 25% paying
  /// every turn that is over, 15% circles finished; shown after 3 confirmed payments.
  @override
  Future<SovaScore> myScore() async {
    await _latency();
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    var confirmed = 0, onTime = 0, turns = 0, made = 0, active = 0, completed = 0;
    for (final c in _circles.values.where((c) => c.memberById(me) != null)) {
      if (c.status == CircleStatus.completed) completed++;
      if (c.status != CircleStatus.completed && c.status != CircleStatus.forming) active++;
      for (final r in c.rounds) {
        final x = c.contributionFor(r.id, me);
        if (x?.status == ContributionStatus.fullyConfirmed) {
          confirmed++;
          final paid = x!.payerConfirmedAt;
          if (paid != null && !DateTime(paid.year, paid.month, paid.day).isAfter(r.dueDate)) onTime++;
        }
        final over = r.status == RoundStatus.completed || (r.status == RoundStatus.active && r.dueDate.isBefore(day));
        if (r.collectorId != me && over) {
          turns++;
          if (x != null && (x.status == ContributionStatus.payerConfirmed || x.status == ContributionStatus.fullyConfirmed)) {
            made++;
          }
        }
      }
    }
    final onTimeRate = confirmed == 0 ? 0.0 : onTime / confirmed;
    final consistency = turns == 0 ? 0.0 : made / turns;
    final completion = active + completed == 0 ? 0.0 : completed / (active + completed);
    final value = (100 * (0.60 * onTimeRate + 0.25 * consistency + 0.15 * completion)).round();
    final ready = confirmed >= 3;
    return SovaScore(
      minimumPayments: 3,
      score: ready ? value : null,
      band: ready ? scoreBand(value) : null,
      onTimeRate: onTimeRate,
      consistencyRate: consistency,
      completionRate: completion,
      confirmedPayments: confirmed,
      onTimePayments: onTime,
      activeCircles: active,
      completedCircles: completed,
    );
  }

  @override
  Future<SovaScore> shareScore({required String pin}) async {
    await _latency();
    _checkPin(pin);
    throw const SovaException('Sharing your score needs the Sova server, so it works in the live app.');
  }

  @override
  Future<SovaScore> stopSharingScore() => myScore();

  // Swaps and handovers: the same rules as the database (request_swap,
  // respond_swap, request_handover, decide_handover...).

  bool _turnOpen(Circle c, int? position) =>
      position == null ||
      !c.rounds.any((r) => r.number == position && (r.status == RoundStatus.active || r.status == RoundStatus.completed));

  TurnChanges _turnChangesOf(String circleId) {
    final c = _circles[circleId]!;
    TurnPerson person(String id, String name) => TurnPerson(id: id, name: name, turn: c.memberById(id)?.position);
    final swaps = _swaps.where((s) => s.circleId == circleId).toList()
      ..sort((a, b) => (a.status == SwapStatus.pending) == (b.status == SwapStatus.pending)
          ? b.createdAt.compareTo(a.createdAt)
          : (a.status == SwapStatus.pending ? -1 : 1));
    final handovers = _handovers.where((h) => h.circleId == circleId).toList()
      ..sort((a, b) => a.status.open == b.status.open ? b.createdAt.compareTo(a.createdAt) : (a.status.open ? -1 : 1));
    return TurnChanges(
      swaps: [
        for (final s in swaps)
          SwapRequest(
            id: s.id,
            status: s.status,
            createdAt: s.createdAt,
            requester: person(s.requester, s.requesterName),
            target: person(s.target, s.targetName),
            reason: s.reason,
            canAnswer: s.status == SwapStatus.pending && s.target == me,
            canCancel: s.status == SwapStatus.pending && s.requester == me,
          ),
      ],
      handovers: [
        for (final h in handovers)
          Handover(
            id: h.id,
            status: h.status,
            createdAt: h.createdAt,
            leaving: TurnPerson(id: h.leaving.userId, name: h.leaving.name, turn: h.position ?? c.memberById(h.leaving.userId)?.position),
            replacement: TurnPerson(id: h.replacement.userId, name: h.replacement.name),
            paidIn: c.contributions
                .where((x) => x.userId == h.leaving.userId && x.status == ContributionStatus.fullyConfirmed)
                .fold(0, (t, x) => t + x.amount),
            reason: h.reason,
            canApprove: h.status == HandoverStatus.accepted && c.adminId == me,
            canCancel: h.status.open && h.leaving.userId == me,
          ),
      ],
    );
  }

  @override
  Future<TurnChanges> turnChanges(String circleId) async {
    if (_circles[circleId]?.memberById(me) == null) throw const SovaException('Circle not found.');
    return _turnChangesOf(circleId);
  }

  @override
  Future<TurnChanges> requestSwap({required String circleId, required String targetId, String? reason, required String pin}) async {
    final c = await circle(circleId);
    _checkPin(pin);
    if (c.status != CircleStatus.active) throw const SovaException('Turns can only be swapped once the circle has started.');
    final target = c.memberById(targetId);
    if (target == null || targetId == me) throw const SovaException('Choose another member.');
    if (c.adminCollectsLast && (c.adminId == me || c.adminId == targetId)) {
      throw const SovaException("The admin pledged to collect last, so their turn can't be swapped.", code: 'pledged_last');
    }
    if (!_turnOpen(c, c.memberById(me)!.position)) {
      throw const SovaException("Your turn has already started, so it can't be swapped.", code: 'turn_started');
    }
    if (!_turnOpen(c, target.position)) {
      throw const SovaException("Their turn has already started, so it can't be swapped.", code: 'turn_started');
    }
    if (_swaps.any((s) => s.circleId == circleId && s.requester == me && s.status == SwapStatus.pending)) {
      throw const SovaException('You already have a swap request waiting. Cancel it first.', code: 'already_asked');
    }
    _swaps.add(_DemoSwap(
      id: 's-${_random.nextInt(1000000000)}',
      circleId: circleId,
      requester: me,
      requesterName: c.memberById(me)!.name,
      target: targetId,
      targetName: target.name,
      reason: (reason?.trim().isEmpty ?? true) ? null : reason!.trim(),
      createdAt: DateTime.now(),
    ));
    return _turnChangesOf(circleId);
  }

  @override
  Future<TurnChanges> answerSwap({required String circleId, required String swapId, required bool accept, String? pin}) async {
    final c = await circle(circleId);
    final s = _swaps.firstWhere((s) => s.id == swapId, orElse: () => throw const SovaException('Swap request not found.'));
    if (s.target != me) throw const SovaException('Only the member who was asked can answer.', code: 'not_target');
    if (s.status != SwapStatus.pending) throw const SovaException('This request has already been answered.');
    if (!accept) {
      s.status = SwapStatus.declined;
      return _turnChangesOf(circleId);
    }
    _checkPin(pin ?? '');
    final a = c.memberById(s.requester), b = c.memberById(s.target);
    if (a == null || b == null) throw const SovaException('Both people must still be in the circle.');
    if (!_turnOpen(c, a.position) || !_turnOpen(c, b.position)) {
      throw const SovaException('One of these turns has already started.', code: 'turn_started');
    }
    _circles[circleId] = _copyCircle(c, members: [
      for (final m in c.members)
        m.userId == a.userId
            ? _withPosition(m, b.position)
            : m.userId == b.userId
                ? _withPosition(m, a.position)
                : m,
    ]);
    s.status = SwapStatus.accepted;
    return _turnChangesOf(circleId);
  }

  Member _withPosition(Member m, int? position) => Member(
        userId: m.userId,
        name: m.name,
        phone: m.phone,
        position: position,
        bank: m.bank,
        vouchedBy: m.vouchedBy,
        owesAfterCollecting: m.owesAfterCollecting,
      );

  @override
  Future<TurnChanges> cancelSwap({required String circleId, required String swapId}) async {
    await circle(circleId);
    final s = _swaps.firstWhere((s) => s.id == swapId && s.requester == me,
        orElse: () => throw const SovaException('Swap request not found.'));
    if (s.status != SwapStatus.pending) throw const SovaException('This request has already been answered.');
    s.status = SwapStatus.cancelled;
    return _turnChangesOf(circleId);
  }

  @override
  Future<TurnChanges> requestHandover({required String circleId, required String phone, String? reason, required String pin}) async {
    final c = await circle(circleId);
    _checkPin(pin);
    if (c.adminId == me) throw const SovaException("The admin can't hand over their place yet.", code: 'admin_cannot_leave');
    if (!_turnOpen(c, c.memberById(me)!.position)) {
      throw const SovaException('You have already collected or are collecting, so you need to finish the cycle.',
          code: 'turn_started');
    }
    final number = normalisePhone(phone);
    final replacement = number == null
        ? null
        : _circles.values.expand((x) => x.members).where((m) => m.phone == number).firstOrNull;
    if (replacement == null) {
      throw const SovaException('Nobody with that number uses Sova yet. Ask them to sign up first.', code: 'no_account');
    }
    if (c.memberById(replacement.userId) != null) {
      throw const SovaException('That person is already in this circle.', code: 'already_member');
    }
    if (_handovers.any((h) => h.circleId == circleId && h.leaving.userId == me && h.status.open)) {
      throw const SovaException('You already have a handover in progress. Cancel it first.', code: 'already_asked');
    }
    _handovers.add(_DemoHandover(
      id: 'h-${_random.nextInt(1000000000)}',
      circleId: circleId,
      leaving: c.memberById(me)!,
      replacement: replacement,
      reason: (reason?.trim().isEmpty ?? true) ? null : reason!.trim(),
      createdAt: DateTime.now(),
    ));
    return _turnChangesOf(circleId);
  }

  @override
  Future<TurnChanges> decideHandover({required String circleId, required String handoverId, required bool approve, String? pin}) async {
    final c = await circle(circleId);
    final h = _handovers.firstWhere((h) => h.id == handoverId, orElse: () => throw const SovaException('Handover not found.'));
    if (c.adminId != me) throw const SovaException('Only the admin can approve a handover.', code: 'not_admin');
    if (h.status != HandoverStatus.accepted) {
      throw const SovaException('The replacement has to accept before you can decide.', code: 'not_ready');
    }
    if (!approve) {
      h.status = HandoverStatus.rejected;
      return _turnChangesOf(circleId);
    }
    _checkPin(pin ?? '');
    h.status = HandoverStatus.approved;
    if (c.forming) _completeHandover(h);
    return _turnChangesOf(circleId);
  }

  @override
  Future<TurnChanges> cancelHandover({required String circleId, required String handoverId}) async {
    await circle(circleId);
    final h = _handovers.firstWhere((h) => h.id == handoverId && h.leaving.userId == me,
        orElse: () => throw const SovaException('Handover not found.'));
    if (!h.status.open) throw const SovaException('This handover can no longer be cancelled.');
    h.status = HandoverStatus.cancelled;
    return _turnChangesOf(circleId);
  }

  @override
  Future<List<HandoverOffer>> handoverOffers() async {
    return [
      for (final h in _handovers.where((h) => h.replacement.userId == me && h.status == HandoverStatus.pending))
        HandoverOffer(
          id: h.id,
          createdAt: h.createdAt,
          leavingName: h.leaving.name,
          paidIn: _circles[h.circleId]!
              .contributions
              .where((x) => x.userId == h.leaving.userId && x.status == ContributionStatus.fullyConfirmed)
              .fold(0, (t, x) => t + x.amount),
          circleId: h.circleId,
          circleName: _circles[h.circleId]!.name,
          contributionAmount: _circles[h.circleId]!.contributionAmount,
          payoutAmount: _circles[h.circleId]!.payout,
          memberCount: _circles[h.circleId]!.memberCount,
          cycle: _circles[h.circleId]!.cycle,
          rules: _circles[h.circleId]!.rules!,
          turn: _circles[h.circleId]!.memberById(h.leaving.userId)?.position,
          reason: h.reason,
        ),
    ];
  }

  @override
  Future<List<HandoverOffer>> answerHandover({required String handoverId, required bool accept, int? rulesVersion, String? pin}) async {
    final h = _handovers.firstWhere((h) => h.id == handoverId && h.replacement.userId == me,
        orElse: () => throw const SovaException('Handover not found.'));
    if (h.status != HandoverStatus.pending) throw const SovaException('This handover has already been answered.');
    if (!accept) {
      h.status = HandoverStatus.declined;
      return handoverOffers();
    }
    _checkPin(pin ?? '');
    if (_circles[h.circleId]!.rules?.version != rulesVersion) {
      throw const SovaException('The rules changed while you were reading. Please read them again.');
    }
    h.status = HandoverStatus.accepted;
    return handoverOffers();
  }

  /// The replacement takes the leaving member's place and turn.
  void _completeHandover(_DemoHandover h) {
    final c = _circles[h.circleId]!;
    final leaving = c.memberById(h.leaving.userId)!;
    h
      ..position = leaving.position
      ..status = HandoverStatus.completed;
    final r = h.replacement;
    _circles[h.circleId] = _copyCircle(
      c,
      members: [
        for (final m in c.members)
          m.userId == leaving.userId
              ? Member(userId: r.userId, name: r.name, phone: r.phone, position: leaving.position, bank: r.bank, vouchedBy: leaving.userId)
              : m,
      ],
      rules: c.rules == null ? null : _withAcceptance(c.rules!, r.userId),
    );
    for (final s in _swaps) {
      if (s.circleId == h.circleId && s.status == SwapStatus.pending && (s.requester == leaving.userId || s.target == leaving.userId)) {
        s.status = SwapStatus.cancelled;
      }
    }
  }

  /// When a turn ends: approved handovers take effect. When the next starts:
  /// pending requests involving its collector are cancelled.
  void _onTurnEnded(String circleId) {
    for (final h in _handovers.where((h) => h.circleId == circleId && h.status == HandoverStatus.approved).toList()) {
      _completeHandover(h);
    }
  }

  void _onTurnStarted(String circleId, String collectorId) {
    for (final s in _swaps.where((s) => s.circleId == circleId && s.status == SwapStatus.pending)) {
      if (s.requester == collectorId || s.target == collectorId) s.status = SwapStatus.cancelled;
    }
    for (final h in _handovers.where((h) => h.circleId == circleId && h.status.open)) {
      if (h.leaving.userId == collectorId) h.status = HandoverStatus.cancelled;
    }
  }

  /// Plain-words label for a score, as the API gives it.
  static String scoreBand(int score) =>
      score >= 90 ? 'Excellent' : score >= 75 ? 'Strong' : score >= 50 ? 'Fair' : 'Building';

  _DemoDispute _ownDispute(String id) {
    final d = _disputes[id];
    if (d == null || _circles[d.circleId]?.memberById(me) == null) throw const SovaException('Dispute not found.');
    return d;
  }

  /// The payment's payer, or for a shortfall everyone whose payment for that
  /// turn is still not confirmed.
  List<String> _payersOf(_DemoDispute d) {
    final c = _circles[d.circleId]!;
    if (d.kind == DisputeKind.payment) return [c.contributions.firstWhere((x) => x.id == d.contributionId).userId];
    final round = c.rounds.firstWhere((r) => r.id == d.roundId);
    return [
      for (final m in c.members)
        if (m.userId != round.collectorId && c.statusFor(round.id, m.userId) != ContributionStatus.fullyConfirmed)
          m.userId,
    ];
  }

  Dispute _disputeView(_DemoDispute d, {bool withTimeline = true}) {
    final c = _circles[d.circleId]!;
    final round = c.rounds.firstWhere((r) => r.id == d.roundId);
    Person person(String id) => Person(id: id, name: c.memberById(id)?.name ?? 'Member');
    final payers = _payersOf(d);
    final role = round.collectorId == me
        ? DisputeRole.collector
        : payers.contains(me)
            ? DisputeRole.payer
            : DisputeRole.voter;
    final open = d.status == DisputeStatus.open;
    final x = d.contributionId == null ? null : c.contributions.firstWhere((x) => x.id == d.contributionId);
    final votes = [for (final e in d.votes.entries) DisputeVote(voter: person(e.key), side: e.value.$1, at: e.value.$2)]
      ..sort((a, b) => a.at.compareTo(b.at));
    return Dispute(
      id: d.id,
      circleId: d.circleId,
      kind: d.kind,
      status: d.status,
      turn: round.number,
      reason: d.reason,
      createdAt: d.createdAt,
      resolvedAt: d.resolvedAt,
      resolutionNote: d.resolutionNote,
      raisedBy: person(d.raisedBy),
      collector: person(round.collectorId),
      payers: [for (final id in payers) person(id)],
      payment: x == null
          ? null
          : DisputePayment(
              contributionId: x.id,
              amount: x.amount,
              bankReference: x.bankReference,
              hasProof: x.hasProof,
              paidAt: x.payerConfirmedAt,
            ),
      myRole: role,
      payerVotes: votes.where((v) => v.side == DisputeSide.payer).length,
      collectorVotes: votes.where((v) => v.side == DisputeSide.collector).length,
      // Everyone except the collector and the payer(s).
      eligibleVoters: c.members.length - 1 - payers.length,
      myVote: d.votes[me]?.$1,
      votes: votes,
      timeline: withTimeline
          ? [for (final e in d.events) DisputeEvent(actor: person(e.$1), kind: e.$2, message: e.$3, at: e.$4)]
          : const [],
      canVote: open && d.kind == DisputeKind.payment && role == DisputeRole.voter,
      canSettle: open && (role == DisputeRole.collector || (d.kind == DisputeKind.payment && role == DisputeRole.payer)),
    );
  }

  void _resolve(_DemoDispute d, DisputeStatus status, String actor, String note) {
    d
      ..status = status
      ..resolutionNote = note
      ..resolvedAt = DateTime.now()
      ..events.add((actor, 'resolved', note, DateTime.now()));
    if (d.kind == DisputeKind.payment) {
      final arrived = status == DisputeStatus.resolvedForPayer;
      _setContributionStatus(
          d.circleId, d.contributionId!, arrived ? ContributionStatus.fullyConfirmed : ContributionStatus.pending);
      if (arrived) _settleShortfalls(d.circleId, d.roundId);
    }
    _syncOpenDisputes(d.circleId);
  }

  /// A shortfall closes by itself once nobody's payment for that turn is missing.
  void _settleShortfalls(String circleId, String roundId) {
    for (final d in _disputes.values.toList()) {
      if (d.circleId == circleId &&
          d.roundId == roundId &&
          d.kind == DisputeKind.shortfall &&
          d.status == DisputeStatus.open &&
          _payersOf(d).isEmpty) {
        final collector = _circles[circleId]!.rounds.firstWhere((r) => r.id == roundId).collectorId;
        _resolve(d, DisputeStatus.resolvedForPayer, collector, 'Made up: every missing payment for this turn is now confirmed.');
      }
    }
  }

  void _setContributionStatus(String circleId, String contributionId, ContributionStatus status) {
    final c = _circles[circleId]!;
    final old = c.contributions.firstWhere((x) => x.id == contributionId);
    _replaceContribution(
      c,
      Contribution(
        id: old.id,
        roundId: old.roundId,
        userId: old.userId,
        amount: old.amount,
        status: status,
        bankReference: old.bankReference,
        hasProof: old.hasProof,
        payerConfirmedAt: status == ContributionStatus.pending ? null : old.payerConfirmedAt,
        reference: old.reference,
      ),
    );
  }

  void _syncOpenDisputes(String circleId) {
    final open = _disputes.values.where((d) => d.circleId == circleId && d.status == DisputeStatus.open).length;
    _circles[circleId] = _copyCircle(_circles[circleId]!, openDisputes: open);
  }

  // ---------------------------------------------------------------------------

  Circle _byCode(String code) {
    final clean = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    for (final c in _circles.values) {
      if (c.inviteCode == clean) return c;
    }
    throw const SovaException('No circle uses that code. Check it and try again.');
  }

  /// Six characters without look-alikes (no 0/O, 1/I/L).
  String _newInviteCode() {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    return String.fromCharCodes(List.generate(6, (_) => alphabet.codeUnitAt(_random.nextInt(alphabet.length))));
  }

  GroupRules _withAcceptance(GroupRules r, String userId) => GroupRules(
        version: r.version,
        lateFee: r.lateFee,
        graceDays: r.graceDays,
        earlyExit: r.earlyExit,
        emergencyPolicy: r.emergencyPolicy,
        acceptedBy: {...r.acceptedBy, userId},
      );

  /// Full, and everyone accepted the rules: draw the turns and open turn 1.
  Circle _startIfReady(Circle c) {
    final accepted = c.rules?.acceptedBy ?? const {};
    if (!c.forming || c.members.length < c.memberCount || c.members.any((m) => !accepted.contains(m.userId))) return c;

    final seed = _drawSeeds[c.id]!;
    final order = [
      for (final id in drawOrder(seed, c.members.map((m) => m.userId), c.adminId, c.adminCollectsLast)) c.memberById(id)!,
    ];
    final today = DateTime.now();
    final start = c.startDate.isBefore(DateTime(today.year, today.month, today.day))
        ? DateTime(today.year, today.month, today.day)
        : c.startDate;
    return _copyCircle(
      c,
      status: CircleStatus.active,
      draw: DrawInfo(
        commitment: c.draw!.commitment,
        seed: seed,
        revealedAt: DateTime.now(),
        order: [for (final m in order) Person(id: m.userId, name: m.name)],
      ),
      members: [
        for (final (i, m) in order.indexed)
          Member(
            userId: m.userId,
            name: m.name,
            phone: m.phone,
            position: i + 1,
            bank: m.bank,
            vouchedBy: m.vouchedBy,
          ),
      ],
      rounds: [Round(id: '${c.id}-r1', number: 1, collectorId: order.first.userId, dueDate: start, status: RoundStatus.active)],
    );
  }

  DateTime _step(CycleType cycle, DateTime d) => switch (cycle) {
        CycleType.daily => d.add(const Duration(days: 1)),
        CycleType.weekly => d.add(const Duration(days: 7)),
        CycleType.monthly => DateTime(d.year, d.month + 1, d.day),
      };

  void _replaceContribution(Circle c, Contribution next) {
    final list = [
      for (final x in c.contributions)
        if (!(x.roundId == next.roundId && x.userId == next.userId)) x,
      next,
    ];
    _circles[c.id] = _copyCircle(c, contributions: list);
  }

  void _renameMe(String fullName, String phone) {
    for (final c in _circles.values.toList()) {
      _circles[c.id] = _copyCircle(c, members: [
        for (final m in c.members)
          m.userId == me
              ? Member(
                  userId: me,
                  name: fullName,
                  phone: phone,
                  position: m.position,
                  bank: m.bank == null
                      ? null
                      : BankDetails(bankName: m.bank!.bankName, accountNumber: m.bank!.accountNumber, accountName: fullName),
                  vouchedBy: m.vouchedBy,
                )
              : m,
      ]);
    }
  }

  Circle _copyCircle(
    Circle c, {
    List<Member>? members,
    List<Round>? rounds,
    List<Contribution>? contributions,
    GroupRules? rules,
    CircleStatus? status,
    DrawInfo? draw,
    int? openDisputes,
  }) =>
      Circle(
        id: c.id,
        name: c.name,
        adminId: c.adminId,
        memberCount: c.memberCount,
        contributionAmount: c.contributionAmount,
        cycle: c.cycle,
        startDate: c.startDate,
        inviteCode: c.inviteCode,
        status: status ?? c.status,
        adminCollectsLast: c.adminCollectsLast,
        members: members ?? c.members,
        rounds: rounds ?? c.rounds,
        contributions: contributions ?? c.contributions,
        rules: rules ?? c.rules,
        draw: draw ?? c.draw,
        openDisputes: openDisputes ?? c.openDisputes,
      );

  void _seed() {
    final today = DateTime.now();
    DateTime day(int offset) => DateTime(today.year, today.month, today.day + offset);

    // Seeds searched to reproduce each started circle's scripted payout order
    // (as the API's demo seed does), so their draws still verify.
    DrawInfo revealed(String id, String seed, DateTime at) {
      _drawSeeds[id] = seed;
      return DrawInfo(commitment: commitmentOf(seed), seed: seed, revealedAt: at);
    }

    // A weekly office esusu where you owe this turn's payment.
    const office = 'office-esusu';
    final officeMembers = [
      const Member(userId: 'ifeoma', name: 'Ifeoma Okeke', phone: '+2348031110001', position: 1),
      const Member(userId: 'bayo', name: 'Bayo Adeyemi', phone: '+2348031110002', position: 2),
      const Member(
        userId: 'halima',
        name: 'Halima Sani',
        phone: '+2348031110003',
        position: 3,
        bank: BankDetails(bankName: 'Moniepoint MFB', accountNumber: '8012345678', accountName: 'Halima Sani'),
      ),
      const Member(userId: me, name: 'You', phone: '', position: 4),
      const Member(userId: 'chuka', name: 'Chuka Obi', phone: '+2348031110005', position: 5),
      const Member(userId: 'zainab', name: 'Zainab Bello', phone: '+2348031110006', position: 6, vouchedBy: 'ifeoma'),
    ];
    final officeRounds = [
      Round(id: 'o-r1', number: 1, collectorId: 'ifeoma', dueDate: day(-12), status: RoundStatus.completed, payoutReceived: 100000),
      Round(id: 'o-r2', number: 2, collectorId: 'bayo', dueDate: day(-5), status: RoundStatus.completed, payoutReceived: 100000),
      Round(id: 'o-r3', number: 3, collectorId: 'halima', dueDate: day(2), status: RoundStatus.active),
    ];
    const paidOn = {'o-r1': -13, 'o-r2': -6, 'o-r3': -1, 'c-r1': -22, 'c-r2': -1};
    Contribution paid(String round, String user, int amount, {ContributionStatus status = ContributionStatus.fullyConfirmed}) =>
        Contribution(
          id: '$round-$user',
          roundId: round,
          userId: user,
          amount: amount,
          status: status,
          hasProof: true,
          payerConfirmedAt: day(paidOn[round]!),
          reference: _reference(),
        );
    _circles[office] = Circle(
      id: office,
      name: 'Office Esusu',
      adminId: 'ifeoma',
      memberCount: 6,
      contributionAmount: 20000,
      cycle: CycleType.weekly,
      startDate: day(-12),
      inviteCode: 'K7QX2M',
      draw: revealed(office, 'e4c573cbc70b5605bdec3cbb0572d47fa94260bf7e97bd2b8dc5b15a7c3db5ba', day(-12)),
      members: officeMembers,
      rounds: officeRounds,
      contributions: [
        for (final u in ['bayo', 'halima', me, 'chuka', 'zainab']) paid('o-r1', u, 20000),
        for (final u in ['ifeoma', 'halima', me, 'chuka', 'zainab']) paid('o-r2', u, 20000),
        paid('o-r3', 'ifeoma', 20000),
        paid('o-r3', 'bayo', 20000),
        paid('o-r3', 'chuka', 20000, status: ContributionStatus.payerConfirmed),
      ],
      rules: const GroupRules(
        version: 1,
        lateFee: 1000,
        graceDays: 1,
        earlyExit: EarlyExitPolicy.findReplacement,
        emergencyPolicy: 'If a member falls ill, the group can agree to move their turn earlier.',
        acceptedBy: {'ifeoma', 'bayo', 'halima', me, 'chuka', 'zainab'},
      ),
    );

    // A circle you can join with code T7KP9Q (you are not a member yet).
    _drawSeeds['tech-hub'] = '96cec7fef4945c050329e80a09b2c03f08994d5f8d3700209b7e3ff4a9d77e7e';
    _circles['tech-hub'] = Circle(
      id: 'tech-hub',
      name: 'Ikeja Tech Hub Esusu',
      adminId: 'kemi',
      memberCount: 8,
      contributionAmount: 15000,
      cycle: CycleType.weekly,
      startDate: day(10),
      inviteCode: 'T7KP9Q',
      draw: DrawInfo(commitment: commitmentOf(_drawSeeds['tech-hub']!)),
      status: CircleStatus.forming,
      adminCollectsLast: true,
      members: const [
        Member(userId: 'kemi', name: 'Kemi Adebayo', phone: '+2348033330001', position: null),
        Member(userId: 'femi', name: 'Femi Lawal', phone: '+2348033330002', position: null),
        Member(userId: 'ngozi2', name: 'Ngozi Eze', phone: '+2348033330003', position: null),
        Member(userId: 'sani', name: 'Sani Musa', phone: '+2348033330004', position: null, vouchedBy: 'kemi'),
      ],
      rounds: const [],
      contributions: const [],
      rules: const GroupRules(
        version: 1,
        lateFee: 1000,
        graceDays: 1,
        earlyExit: EarlyExitPolicy.findReplacement,
        emergencyPolicy: 'Members can swap turns for emergencies if both agree.',
        acceptedBy: {'kemi', 'femi', 'ngozi2', 'sani'},
      ),
    );

    // A monthly class ajo you run, where you collect this turn.
    const classAjo = 'class-ajo';
    _circles[classAjo] = Circle(
      id: classAjo,
      name: "Unilag Class of '24 Ajo",
      adminId: me,
      memberCount: 5,
      contributionAmount: 10000,
      cycle: CycleType.monthly,
      startDate: day(-21),
      inviteCode: 'P4DN8R',
      draw: revealed(classAjo, '1c0f12c0a5184d33dc2dae1dc6b76ae2a7aa1353e3cec869ac5d8453b41f39c4', day(-21)),
      members: [
        const Member(userId: 'tolu', name: 'Tolu Ajayi', phone: '+2348032220001', position: 1),
        const Member(
          userId: me,
          name: 'You',
          phone: '',
          position: 2,
          bank: BankDetails(bankName: 'OPay', accountNumber: '9061234567', accountName: 'You'),
        ),
        const Member(userId: 'emeka', name: 'Emeka Nwosu', phone: '+2348032220003', position: 3),
        const Member(userId: 'amina', name: 'Amina Yusuf', phone: '+2348032220004', position: 4),
        const Member(userId: 'david', name: 'David Etim', phone: '+2348032220005', position: 5, vouchedBy: 'tolu'),
      ],
      rounds: [
        Round(id: 'c-r1', number: 1, collectorId: 'tolu', dueDate: day(-21), status: RoundStatus.completed, payoutReceived: 40000),
        Round(id: 'c-r2', number: 2, collectorId: me, dueDate: day(9), status: RoundStatus.active),
      ],
      contributions: [
        for (final u in [me, 'emeka', 'amina', 'david']) paid('c-r1', u, 10000),
        paid('c-r2', 'tolu', 10000),
        paid('c-r2', 'emeka', 10000, status: ContributionStatus.payerConfirmed),
      ],
      rules: const GroupRules(
        version: 1,
        lateFee: 500,
        graceDays: 2,
        earlyExit: EarlyExitPolicy.refundAfterCycle,
        acceptedBy: {'tolu', me, 'emeka', 'amina', 'david'},
      ),
    );

    // Halima says Chuka's turn-3 payment never arrived. Ifeoma and Bayo voted
    // that it did; your vote would make 3 of 4 and settle it.
    const disputed = 'o-r3-chuka';
    _setContributionStatus(office, disputed, ContributionStatus.disputed);
    final raisedAt = day(-1).add(const Duration(hours: 9));
    _disputes['d-office-chuka'] = _DemoDispute(
      id: 'd-office-chuka',
      circleId: office,
      roundId: 'o-r3',
      kind: DisputeKind.payment,
      contributionId: disputed,
      raisedBy: 'halima',
      reason: 'Chuka marked ₦20,000 as sent, but nothing has reached my Moniepoint account.',
      createdAt: raisedAt,
    )
      ..events.addAll([
        ('halima', 'opened', 'Chuka marked ₦20,000 as sent, but nothing has reached my Moniepoint account.', raisedAt),
        ('chuka', 'comment', 'I sent it from GTBank. The receipt photo is attached to my payment.',
            raisedAt.add(const Duration(hours: 2))),
      ])
      ..votes['ifeoma'] = (DisputeSide.payer, raisedAt.add(const Duration(hours: 4)))
      ..votes['bayo'] = (DisputeSide.payer, raisedAt.add(const Duration(hours: 6)));
    _syncOpenDisputes(office);

    // The order as drawn, as the server reads it from the record.
    for (final id in [office, classAjo]) {
      final c = _circles[id]!;
      final d = c.draw!;
      _circles[id] = _copyCircle(
        c,
        draw: DrawInfo(
          commitment: d.commitment,
          seed: d.seed,
          revealedAt: d.revealedAt,
          order: [for (final m in c.membersByPosition) Person(id: m.userId, name: m.name)],
        ),
      );
    }

    // Zainab (turn 6) asks to swap with your turn 4 in the office esusu.
    _swaps.add(_DemoSwap(
      id: 's-office-zainab',
      circleId: office,
      requester: 'zainab',
      requesterName: 'Zainab Bello',
      target: me,
      targetName: 'You',
      reason: 'My shop rent is due before my turn. Could we swap?',
      createdAt: day(-1).add(const Duration(hours: 15)),
    ));
  }
}

/// A dispute held in memory: who raised it, the votes and the history.
class _DemoDispute {
  _DemoDispute({
    required this.id,
    required this.circleId,
    required this.roundId,
    required this.kind,
    required this.raisedBy,
    required this.reason,
    required this.createdAt,
    this.contributionId,
  });

  final String id;
  final String circleId;
  final String roundId;
  final DisputeKind kind;
  final String? contributionId;
  final String raisedBy;
  final String reason;
  final DateTime createdAt;
  DisputeStatus status = DisputeStatus.open;
  String? resolutionNote;
  DateTime? resolvedAt;

  /// Voter id -> their current side and when they chose it.
  final votes = <String, (DisputeSide, DateTime)>{};

  /// (actor id, kind, message, at)
  final events = <(String, String, String?, DateTime)>[];
}

class _DemoSwap {
  _DemoSwap({
    required this.id,
    required this.circleId,
    required this.requester,
    required this.requesterName,
    required this.target,
    required this.targetName,
    required this.createdAt,
    this.reason,
  });

  final String id;
  final String circleId;
  final String requester;
  final String requesterName;
  final String target;
  final String targetName;
  final String? reason;
  final DateTime createdAt;
  SwapStatus status = SwapStatus.pending;
}

class _DemoHandover {
  _DemoHandover({
    required this.id,
    required this.circleId,
    required this.leaving,
    required this.replacement,
    required this.createdAt,
    this.reason,
  });

  final String id;
  final String circleId;
  final Member leaving;
  final Member replacement;
  final String? reason;
  final DateTime createdAt;
  HandoverStatus status = HandoverStatus.pending;

  /// The turn handed over, once done.
  int? position;
}
