// Domain models. Field names mirror the Neon tables in db/migrations.

enum CycleType {
  daily('Daily', 'day'),
  weekly('Weekly', 'week'),
  monthly('Monthly', 'month');

  const CycleType(this.label, this.unit);
  final String label;
  final String unit;
}

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
  });

  final String userId;
  final String name;
  final String phone;
  final int position;
  final BankDetails? bank;

  /// userId of the member who vouched for this one, if any.
  final String? vouchedBy;

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
  });

  final String id;
  final int number;
  final String collectorId;
  final DateTime dueDate;
  final RoundStatus status;
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
    this.rules,
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
  final GroupRules? rules;

  /// Everyone pays in each round, including the collector, so the payout is
  /// one contribution per seat.
  int get payout => contributionAmount * memberCount;

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

  List<Member> get membersByPosition => [...members]..sort((a, b) => a.position.compareTo(b.position));

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

  bool isAdmin(String userId) => adminId == userId;
}

class Session {
  const Session({
    required this.phone,
    required this.userId,
    this.fullName,
    this.hasPin = false,
  });

  final String phone;
  final String userId;
  final String? fullName;
  final bool hasPin;

  bool get profileComplete => (fullName?.isNotEmpty ?? false) && hasPin;

  Session copyWith({String? fullName, bool? hasPin}) => Session(
        phone: phone,
        userId: userId,
        fullName: fullName ?? this.fullName,
        hasPin: hasPin ?? this.hasPin,
      );
}
