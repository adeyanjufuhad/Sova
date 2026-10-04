// Domain models. Field names mirror the tables in db/migrations and the API.

enum CycleType {
  daily('Daily', 'day'),
  weekly('Weekly', 'week'),
  monthly('Monthly', 'month');

  const CycleType(this.label, this.unit);
  final String label;
  final String unit;
}

/// A circle fills up while 'forming'; the fair draw then starts it.
enum CircleStatus { forming, active, paused, completed }

enum RoundStatus { pending, active, completed }

enum ContributionStatus {
  pending('Not paid'),
  payerConfirmed('Awaiting confirmation'),
  fullyConfirmed('Paid'),
  disputed('Disputed');

  const ContributionStatus(this.label);
  final String label;
}

enum EarlyExitPolicy {
  findReplacement('Find a replacement', 'A member who leaves must hand their slot to someone the admin approves.'),
  refundAfterCycle('Refund after the cycle', 'A member who leaves gets back what they paid once the cycle ends.'),
  forfeitFee('Pay an exit fee', 'A member who leaves early pays a fee agreed by the group.');

  const EarlyExitPolicy(this.label, this.description);
  final String label;
  final String description;
}

class BankDetails {
  const BankDetails({required this.bankName, required this.accountNumber, required this.accountName});
  final String bankName;
  final String accountNumber;
  final String accountName;
}

class Member {
  const Member({
    required this.userId,
    required this.name,
    required this.phone,
    required this.position,
    this.bank,
    this.vouchedBy,
    this.owesAfterCollecting = false,
  });

  final String userId;
  final String name;
  final String phone;

  /// Payout turn; null until the fair draw runs when the circle is full.
  final int? position;
  final BankDetails? bank;

  /// userId of the member who vouched for this one, if any.
  final String? vouchedBy;

  /// Collected their payout, then missed a later payment that is now overdue.
  final bool owesAfterCollecting;

  String get firstName => name.split(' ').first;
  String get initial => name.isEmpty ? '?' : name[0].toUpperCase();
}

class Round {
  const Round({
    required this.id,
    required this.number,
    required this.collectorId,
    required this.dueDate,
    required this.status,
    this.payoutReceived,
  });

  final String id;
  final int number;
  final String collectorId;
  final DateTime dueDate;
  final RoundStatus status;

  /// What the collector confirmed receiving, once they closed the turn.
  final int? payoutReceived;
}

class Contribution {
  const Contribution({
    required this.id,
    required this.roundId,
    required this.userId,
    required this.amount,
    required this.status,
    this.bankReference,
    this.hasProof = false,
    this.payerConfirmedAt,
    this.reference,
  });

  final String id;
  final String roundId;
  final String userId;
  final int amount;
  final ContributionStatus status;
  final String? bankReference;
  final bool hasProof;
  final DateTime? payerConfirmedAt;

  /// Sova receipt reference shown to both sides, e.g. SV-4821.
  final String? reference;
}

class GroupRules {
  const GroupRules({
    required this.version,
    required this.lateFee,
    required this.graceDays,
    required this.earlyExit,
    this.emergencyPolicy,
    this.acceptedBy = const {},
  });

  final int version;
  final int lateFee;
  final int graceDays;
  final EarlyExitPolicy earlyExit;
  final String? emergencyPolicy;
  final Set<String> acceptedBy;
}

/// The commit-reveal draw: [commitment] is public from the start; [seed] is
/// revealed when the turns are drawn, so anyone can check the order.
class DrawInfo {
  const DrawInfo({required this.commitment, this.seed, this.revealedAt});

  final String commitment;
  final String? seed;
  final DateTime? revealedAt;

  bool get revealed => seed != null;
}

class Circle {
  const Circle({
    required this.id,
    required this.name,
    required this.adminId,
    required this.memberCount,
    required this.contributionAmount,
    required this.cycle,
    required this.startDate,
    required this.inviteCode,
    required this.members,
    required this.rounds,
    required this.contributions,
    this.status = CircleStatus.active,
    this.adminCollectsLast = false,
    this.rules,
    this.draw,
    this.openDisputes = 0,
  });

  final String id;
  final String name;
  final String adminId;
  final int memberCount;
  final int contributionAmount;
  final CycleType cycle;
  final DateTime startDate;
  final String inviteCode;
  final List<Member> members;
  final List<Round> rounds;
  final List<Contribution> contributions;
  final CircleStatus status;

  /// The admin pledged to take the last turn; the draw respects it.
  final bool adminCollectsLast;
  final GroupRules? rules;
  final DrawInfo? draw;
  final int openDisputes;

  /// The collector receives one contribution from every other member.
  int get payout => contributionAmount * (memberCount - 1);

  bool get forming => status == CircleStatus.forming;

  Round? get activeRound {
    for (final r in rounds) {
      if (r.status == RoundStatus.active) return r;
    }
    return null;
  }

  Member? memberById(String userId) {
    for (final m in members) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  Member? get currentCollector {
    final r = activeRound;
    return r == null ? null : memberById(r.collectorId);
  }

  /// Drawn turns first, in order; members still waiting for the draw last.
  List<Member> get membersByPosition =>
      [...members]..sort((a, b) => (a.position ?? 1 << 30).compareTo(b.position ?? 1 << 30));

  Contribution? contributionFor(String roundId, String userId) {
    for (final c in contributions) {
      if (c.roundId == roundId && c.userId == userId) return c;
    }
    return null;
  }

  ContributionStatus statusFor(String roundId, String userId) =>
      contributionFor(roundId, userId)?.status ?? ContributionStatus.pending;

  /// Members (other than the collector) whose payment is fully confirmed this round.
  int get paidThisRound {
    final r = activeRound;
    if (r == null) return 0;
    return members
        .where((m) => m.userId != r.collectorId && statusFor(r.id, m.userId) == ContributionStatus.fullyConfirmed)
        .length;
  }

  int get payersThisRound => activeRound == null ? 0 : members.length - 1;

  /// Total of this turn's payments the collector has confirmed.
  int get confirmedThisRound => paidThisRound * contributionAmount;

  bool isAdmin(String userId) => adminId == userId;
}

class Session {
  const Session({
    required this.phone,
    required this.userId,
    this.fullName,
    this.hasPin = false,
    this.isDemo = false,
  });

  final String phone;
  final String userId;
  final String? fullName;
  final bool hasPin;

  /// The shared demo account behind "Try the demo".
  final bool isDemo;

  bool get profileComplete => (fullName?.isNotEmpty ?? false) && hasPin;

  Session copyWith({String? fullName, bool? hasPin}) => Session(
        phone: phone,
        userId: userId,
        fullName: fullName ?? this.fullName,
        hasPin: hasPin ?? this.hasPin,
        isDemo: isDemo,
      );
}

/// What the admin fills in when starting a circle.
class NewCircle {
  const NewCircle({
    required this.name,
    required this.contributionAmount,
    required this.memberCount,
    required this.cycle,
    required this.startDate,
    required this.adminCollectsLast,
    required this.lateFee,
    required this.graceDays,
    required this.earlyExit,
    this.emergencyPolicy,
  });

  final String name;
  final int contributionAmount;
  final int memberCount;
  final CycleType cycle;
  final DateTime startDate;

  /// Admins often pledge to collect last to show good faith. Otherwise the
  /// fair draw decides their turn like everyone else's.
  final bool adminCollectsLast;
  final int lateFee;
  final int graceDays;
  final EarlyExitPolicy earlyExit;
  final String? emergencyPolicy;

  int get payout => contributionAmount * (memberCount - 1);
}

/// What happened when the collector confirmed their payout.
class PayoutResult {
  const PayoutResult({required this.shortfall, required this.nextRound, required this.circle});

  /// Naira missing from the expected payout; a dispute opens when above 0.
  final int shortfall;

  /// The turn that opened next, or null when the circle is complete.
  final int? nextRound;
  final Circle circle;
}
