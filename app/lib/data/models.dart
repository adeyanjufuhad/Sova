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
  const DrawInfo({required this.commitment, this.seed, this.revealedAt, this.order});

  final String commitment;
  final String? seed;
  final DateTime? revealedAt;

  /// Member ids and names in the order drawn (turn 1 first). Agreed swaps and
  /// handovers change who holds a turn later, but the draw is checked against this.
  final List<Person>? order;

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

/// A shortfall opens automatically when a payout comes up short; a payment
/// dispute is about one payment marked as sent.
enum DisputeKind { shortfall, payment }

/// The two sides of a dispute: the payer (the money arrived) and the collector
/// (it didn't).
enum DisputeSide { payer, collector }

enum DisputeStatus {
  open('Open'),
  resolvedForPayer('Closed: paid'),
  resolvedForCollector('Closed: not paid'),
  withdrawn('Withdrawn');

  const DisputeStatus(this.label);
  final String label;
}

/// The signed-in member's part in a dispute.
enum DisputeRole { payer, collector, voter }

/// Someone named in a dispute.
class Person {
  const Person({required this.id, required this.name});
  final String id;
  final String name;

  String get firstName => name.split(' ').first;
}

class DisputePayment {
  const DisputePayment({required this.contributionId, required this.amount, this.bankReference, this.hasProof = false, this.paidAt});
  final String contributionId;
  final int amount;
  final String? bankReference;
  final bool hasProof;
  final DateTime? paidAt;
}

class DisputeVote {
  const DisputeVote({required this.voter, required this.side, required this.at});
  final Person voter;
  final DisputeSide side;
  final DateTime at;
}

/// One line of a dispute's history: opened, comment, evidence or resolved.
class DisputeEvent {
  const DisputeEvent({required this.actor, required this.kind, required this.at, this.message});
  final Person actor;
  final String kind;
  final String? message;
  final DateTime at;
}

class Dispute {
  const Dispute({
    required this.id,
    required this.circleId,
    required this.kind,
    required this.status,
    required this.turn,
    required this.reason,
    required this.createdAt,
    required this.raisedBy,
    required this.collector,
    required this.payers,
    required this.myRole,
    required this.payerVotes,
    required this.collectorVotes,
    required this.eligibleVoters,
    required this.canVote,
    required this.canSettle,
    this.payment,
    this.resolutionNote,
    this.resolvedAt,
    this.myVote,
    this.votes = const [],
    this.timeline = const [],
  });

  final String id;
  final String circleId;
  final DisputeKind kind;
  final DisputeStatus status;
  final int turn;
  final String reason;
  final DateTime createdAt;
  final Person raisedBy;
  final Person collector;

  /// The payer of a payment dispute, or everyone still missing for a shortfall.
  final List<Person> payers;
  final DisputePayment? payment;
  final String? resolutionNote;
  final DateTime? resolvedAt;
  final DisputeRole myRole;
  final int payerVotes;
  final int collectorVotes;
  final int eligibleVoters;
  final DisputeSide? myVote;
  final List<DisputeVote> votes;
  final List<DisputeEvent> timeline;
  final bool canVote;
  final bool canSettle;

  bool get open => status == DisputeStatus.open;

  /// Votes one side needs: more than half of the members who may vote.
  int get votesNeeded => eligibleVoters ~/ 2 + 1;

  /// "Ada O." for a payment dispute, or the missing members for a shortfall.
  String get payerNames => payers.isEmpty ? 'nobody' : payers.map((p) => p.firstName).join(', ');
}

/// A live link to a snapshot of the member's score. Anyone with the link can
/// open the card on the website; the member can stop sharing at any time.
class ScoreShare {
  const ScoreShare({required this.token, required this.sharedAt, required this.score});

  final String token;
  final DateTime sharedAt;

  /// The score as it was when the link was made.
  final int score;
}

/// The member's Sova Score, worked out by the server from their whole record:
/// 60% paying on time, 25% paying every turn, 15% finishing circles.
class SovaScore {
  const SovaScore({
    required this.minimumPayments,
    required this.score,
    required this.band,
    required this.onTimeRate,
    required this.consistencyRate,
    required this.completionRate,
    required this.confirmedPayments,
    required this.onTimePayments,
    required this.activeCircles,
    required this.completedCircles,
    this.share,
  });

  /// Confirmed payments needed before a score is shown.
  final int minimumPayments;

  /// Null until the member has [minimumPayments] confirmed payments.
  final int? score;
  final String? band;
  final double onTimeRate;
  final double consistencyRate;
  final double completionRate;
  final int confirmedPayments;
  final int onTimePayments;
  final int activeCircles;
  final int completedCircles;
  final ScoreShare? share;

  bool get ready => score != null;
}

/// Someone in a swap or handover, with the turn they hold now (if any).
class TurnPerson {
  const TurnPerson({required this.id, required this.name, this.turn});
  final String id;
  final String name;
  final int? turn;

  String get firstName => name.split(' ').first;
}

enum SwapStatus {
  pending('Waiting for an answer'),
  accepted('Swapped'),
  declined('Declined'),
  cancelled('Cancelled');

  const SwapStatus(this.label);
  final String label;
}

/// A member asks another to trade payout turns.
class SwapRequest {
  const SwapRequest({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.requester,
    required this.target,
    this.reason,
    this.canAnswer = false,
    this.canCancel = false,
  });

  final String id;
  final SwapStatus status;
  final DateTime createdAt;
  final TurnPerson requester;
  final TurnPerson target;
  final String? reason;

  /// The signed-in member was asked and can accept or decline.
  final bool canAnswer;

  /// The signed-in member asked and can withdraw it.
  final bool canCancel;
}

enum HandoverStatus {
  pending('Waiting for the replacement'),
  accepted('Waiting for the admin'),
  approved('Approved: takes effect when this turn ends'),
  completed('Handed over'),
  declined('Declined by the replacement'),
  rejected('Not approved by the admin'),
  cancelled('Cancelled');

  const HandoverStatus(this.label);
  final String label;

  bool get open => this == pending || this == accepted || this == approved;
}

/// A member leaving early hands their place to someone outside the circle.
class Handover {
  const Handover({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.leaving,
    required this.replacement,
    required this.paidIn,
    this.reason,
    this.canApprove = false,
    this.canCancel = false,
  });

  final String id;
  final HandoverStatus status;
  final DateTime createdAt;
  final TurnPerson leaving;
  final TurnPerson replacement;

  /// What the leaving member paid into earlier turns. They settle it with the
  /// replacement themselves; Sova only keeps the record.
  final int paidIn;
  final String? reason;
  final bool canApprove;
  final bool canCancel;
}

class TurnChanges {
  const TurnChanges({required this.swaps, required this.handovers});
  final List<SwapRequest> swaps;
  final List<Handover> handovers;

  /// Things waiting on the signed-in member: swaps to answer, handovers to approve.
  int get needsMe => swaps.where((s) => s.canAnswer).length + handovers.where((h) => h.canApprove).length;
}

/// A place offered to the signed-in person in a circle they aren't in yet.
class HandoverOffer {
  const HandoverOffer({
    required this.id,
    required this.createdAt,
    required this.leavingName,
    required this.paidIn,
    required this.circleId,
    required this.circleName,
    required this.contributionAmount,
    required this.payoutAmount,
    required this.memberCount,
    required this.cycle,
    required this.rules,
    this.turn,
    this.reason,
  });

  final String id;
  final DateTime createdAt;
  final String leavingName;
  final int paidIn;
  final String circleId;
  final String circleName;
  final int contributionAmount;
  final int payoutAmount;
  final int memberCount;
  final CycleType cycle;
  final GroupRules rules;

  /// The turn that comes with the place; null before the circle's draw.
  final int? turn;
  final String? reason;
}
