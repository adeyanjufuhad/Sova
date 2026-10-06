import 'dart:math';
import 'dart:typed_data';

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
    final next = c.membersByPosition.where((m) => m.position == round.number + 1).firstOrNull;
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
    final updated = _copyCircle(
      c,
      rounds: rounds,
      status: next == null ? CircleStatus.completed : c.status,
      openDisputes: c.openDisputes + (shortfall > 0 ? 1 : 0),
    );
    _circles[circleId] = updated;
    return PayoutResult(shortfall: shortfall, nextRound: next == null ? null : round.number + 1, circle: updated);
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
      draw: DrawInfo(commitment: c.draw!.commitment, seed: seed, revealedAt: DateTime.now()),
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
  }
}
