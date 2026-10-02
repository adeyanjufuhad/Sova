import 'dart:math';

import 'models.dart';
import 'sova_repository.dart';

/// In-memory backend for building and testing the app before the API exists.
/// The OTP is always [demoOtp] and the data resets when the app restarts.
class DemoRepository implements SovaRepository {
  DemoRepository() {
    _seed();
  }

  static const demoOtp = '123456';
  static const me = 'me';

  final _random = Random();
  final _circles = <String, Circle>{};
  Session? _session;
  String? _pin;
  int _pinFailures = 0;
  DateTime? _pinLockedUntil;

  Future<void> _latency() => Future.delayed(const Duration(milliseconds: 350));

  String _reference() => 'SV-${1000 + _random.nextInt(9000)}';

  @override
  Future<void> requestOtp(String phone) => _latency();

  @override
  Future<Session> verifyOtp(String phone, String code) async {
    await _latency();
    if (code != demoOtp) throw const SovaException('That code is not correct. Check the SMS and try again.');
    return _session = Session(phone: phone, userId: me);
  }

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
    final now = DateTime.now();
    if (_pinLockedUntil != null && _pinLockedUntil!.isAfter(now)) {
      throw const SovaException('Too many wrong tries. Your PIN is locked for 15 minutes.');
    }
    if (pin != _pin) {
      _pinFailures++;
      if (_pinFailures >= 5) {
        _pinFailures = 0;
        _pinLockedUntil = now.add(const Duration(minutes: 15));
        throw const SovaException('Too many wrong tries. Your PIN is locked for 15 minutes.');
      }
      throw SovaException('Wrong PIN. ${5 - _pinFailures} tries left.');
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
    if (c == null) throw const SovaException('This circle no longer exists.');
    return c;
  }

  @override
  Future<Contribution> confirmMyPayment({
    required String circleId,
    required String roundId,
    String? bankReference,
    bool hasProof = false,
  }) async {
    await _latency();
    final c = _circles[circleId]!;
    final existing = c.contributionFor(roundId, me);
    if (existing != null && existing.status != ContributionStatus.pending) {
      throw const SovaException('You have already recorded this payment.');
    }
    final contribution = Contribution(
      id: 'c-${_random.nextInt(1000000000)}',
      roundId: roundId,
      userId: me,
      amount: c.contributionAmount,
      status: ContributionStatus.payerConfirmed,
      bankReference: bankReference,
      hasProof: hasProof,
      payerConfirmedAt: DateTime.now(),
      reference: _reference(),
    );
    _replaceContribution(c, contribution);
    return contribution;
  }

  @override
  Future<Contribution> confirmReceived({required String circleId, required String contributionId}) async {
    await _latency();
    final c = _circles[circleId]!;
    final old = c.contributions.firstWhere((x) => x.id == contributionId);
    final round = c.rounds.firstWhere((r) => r.id == old.roundId);
    if (round.collectorId != me) throw const SovaException('Only this round\'s collector can confirm payments.');
    final updated = Contribution(
      id: old.id,
      roundId: old.roundId,
      userId: old.userId,
      amount: old.amount,
      status: ContributionStatus.fullyConfirmed,
      bankReference: old.bankReference,
      hasProof: old.hasProof,
      payerConfirmedAt: old.payerConfirmedAt,
      reference: old.reference ?? _reference(),
    );
    _replaceContribution(c, updated);
    return updated;
  }

  @override
  Future<void> acceptRules(String circleId) async {
    await _latency();
    final c = _circles[circleId]!;
    final r = c.rules!;
    _circles[circleId] = _copyCircle(
      c,
      rules: GroupRules(
        version: r.version,
        lateFee: r.lateFee,
        graceDays: r.graceDays,
        earlyExit: r.earlyExit,
        emergencyPolicy: r.emergencyPolicy,
        acceptedBy: {...r.acceptedBy, me},
      ),
    );
  }

  @override
  Future<Circle> createCircle(NewCircle d) async {
    await _latency();
    final name = d.name.trim();
    if (name.length < 2) throw const SovaException('Give your circle a name.');
    if (d.contributionAmount < 100) throw const SovaException('The contribution must be at least ₦100.');
    final id = 'circle-${_random.nextInt(1000000000)}';
    final circle = Circle(
      id: id,
      name: name,
      adminId: me,
      memberCount: d.memberCount,
      contributionAmount: d.contributionAmount,
      cycle: d.cycle,
      startDate: d.startDate,
      inviteCode: _newInviteCode(),
      members: [
        Member(
          userId: me,
          name: _session?.fullName ?? 'You',
          phone: _session?.phone ?? '',
          position: d.adminCollectsFirst ? 1 : d.memberCount,
        ),
      ],
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
    if (c.members.length >= c.memberCount) throw const SovaException('This circle is already full.');
    return c;
  }

  @override
  Future<Circle> joinCircle({required String code, required String voucherId}) async {
    await _latency();
    final c = _byCode(code);
    if (c.memberById(me) != null) throw const SovaException('You are already in this circle.');
    if (c.members.length >= c.memberCount) throw const SovaException('This circle is already full.');
    if (c.memberById(voucherId) == null) throw const SovaException('Choose the member who invited you.');

    // Take the earliest free payout position.
    final taken = c.members.map((m) => m.position).toSet();
    final position = [for (var p = 1; p <= c.memberCount; p++) p].firstWhere((p) => !taken.contains(p));
    final joined = _copyCircle(
      c,
      members: [
        ...c.members,
        Member(
          userId: me,
          name: _session?.fullName ?? 'You',
          phone: _session?.phone ?? '',
          position: position,
          vouchedBy: voucherId,
        ),
      ],
      rules: c.rules == null
          ? null
          : GroupRules(
              version: c.rules!.version,
              lateFee: c.rules!.lateFee,
              graceDays: c.rules!.graceDays,
              earlyExit: c.rules!.earlyExit,
              emergencyPolicy: c.rules!.emergencyPolicy,
              acceptedBy: {...c.rules!.acceptedBy, me},
            ),
    );
    _circles[c.id] = joined;
    return joined;
  }

  Circle _byCode(String code) {
    final clean = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    for (final c in _circles.values) {
      if (c.inviteCode == clean) return c;
    }
    throw const SovaException('No circle has that code. Check it with the member who invited you.');
  }

  /// Six characters without look-alikes (no 0/O, 1/I/L).
  String _newInviteCode() {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    return String.fromCharCodes(List.generate(6, (_) => alphabet.codeUnitAt(_random.nextInt(alphabet.length))));
  }

  // ---------------------------------------------------------------------------

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
        members: members ?? c.members,
        rounds: rounds ?? c.rounds,
        contributions: contributions ?? c.contributions,
        rules: rules ?? c.rules,
      );

  void _seed() {
    final today = DateTime.now();
    DateTime day(int offset) => DateTime(today.year, today.month, today.day + offset);

    // A weekly office esusu where you owe this round's payment.
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
      Round(id: 'o-r1', number: 1, collectorId: 'ifeoma', dueDate: day(-12), status: RoundStatus.completed),
      Round(id: 'o-r2', number: 2, collectorId: 'bayo', dueDate: day(-5), status: RoundStatus.completed),
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
    _circles['tech-hub'] = Circle(
      id: 'tech-hub',
      name: 'Ikeja Tech Hub Esusu',
      adminId: 'kemi',
      memberCount: 8,
      contributionAmount: 15000,
      cycle: CycleType.weekly,
      startDate: day(10),
      inviteCode: 'T7KP9Q',
      members: const [
        Member(userId: 'kemi', name: 'Kemi Adebayo', phone: '+2348033330001', position: 8),
        Member(userId: 'femi', name: 'Femi Lawal', phone: '+2348033330002', position: 1),
        Member(userId: 'ngozi2', name: 'Ngozi Eze', phone: '+2348033330003', position: 2),
        Member(userId: 'sani', name: 'Sani Musa', phone: '+2348033330004', position: 3, vouchedBy: 'kemi'),
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

    // A monthly class ajo you run, where you collect this round.
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
        Round(id: 'c-r1', number: 1, collectorId: 'tolu', dueDate: day(-21), status: RoundStatus.completed),
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
        acceptedBy: {'tolu', me, 'emeka', 'amina'},
      ),
    );
  }
}
