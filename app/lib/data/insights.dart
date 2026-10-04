// Derived views of the member's circles: what needs doing, what happened,
// and how their record looks. Everything here is computed from real data.

import 'models.dart';

enum PaymentKind { pay, awaiting, confirm, collect }

class PaymentItem {
  const PaymentItem({
    required this.kind,
    required this.circle,
    required this.round,
    required this.amount,
    required this.counterparty,
    required this.date,
    this.contribution,
  });

  final PaymentKind kind;
  final Circle circle;
  final Round? round;
  final int amount;

  /// The other person: who you pay, who paid you, or null for your own payout.
  final Member? counterparty;
  final DateTime date;
  final Contribution? contribution;

  bool get needsAction => kind == PaymentKind.pay || kind == PaymentKind.confirm;
}

/// When the member at [position] collects, estimated from the cycle when the
/// round hasn't been created yet.
DateTime payoutDateFor(Circle c, int position) {
  for (final r in c.rounds) {
    if (r.number == position) return r.dueDate;
  }
  final steps = position - 1;
  return switch (c.cycle) {
    CycleType.daily => c.startDate.add(Duration(days: steps)),
    CycleType.weekly => c.startDate.add(Duration(days: 7 * steps)),
    CycleType.monthly => DateTime(c.startDate.year, c.startDate.month + steps, c.startDate.day),
  };
}

/// The member's soonest payout that hasn't happened yet.
({Circle circle, DateTime date})? nextPayout(List<Circle> circles, String me) {
  ({Circle circle, DateTime date})? best;
  for (final c in circles) {
    final position = c.memberById(me)?.position;
    if (position == null) continue; // not a member, or turns not drawn yet
    final done = c.rounds.any((r) => r.number == position && r.status == RoundStatus.completed);
    if (done) continue;
    final date = payoutDateFor(c, position);
    if (best == null || date.isBefore(best.date)) best = (circle: c, date: date);
  }
  return best;
}

List<PaymentItem> paymentItems(List<Circle> circles, String me) {
  final items = <PaymentItem>[];
  for (final c in circles) {
    final r = c.activeRound;
    if (r != null && r.collectorId != me) {
      final status = c.statusFor(r.id, me);
      if (status == ContributionStatus.pending || status == ContributionStatus.payerConfirmed) {
        items.add(PaymentItem(
          kind: status == ContributionStatus.pending ? PaymentKind.pay : PaymentKind.awaiting,
          circle: c,
          round: r,
          amount: c.contributionAmount,
          counterparty: c.memberById(r.collectorId),
          date: r.dueDate,
          contribution: c.contributionFor(r.id, me),
        ));
      }
    }
    if (r != null && r.collectorId == me) {
      for (final x in c.contributions) {
        if (x.roundId == r.id && x.status == ContributionStatus.payerConfirmed) {
          items.add(PaymentItem(
            kind: PaymentKind.confirm,
            circle: c,
            round: r,
            amount: x.amount,
            counterparty: c.memberById(x.userId),
            date: x.payerConfirmedAt ?? r.dueDate,
            contribution: x,
          ));
        }
      }
    }
    final position = c.memberById(me)?.position;
    if (position != null && !c.rounds.any((x) => x.number == position && x.status == RoundStatus.completed)) {
      items.add(PaymentItem(
        kind: PaymentKind.collect,
        circle: c,
        round: r?.collectorId == me ? r : null,
        amount: c.payout,
        counterparty: null,
        date: payoutDateFor(c, position),
      ));
    }
  }
  // Actions first, then by date.
  items.sort((a, b) {
    if (a.needsAction != b.needsAction) return a.needsAction ? -1 : 1;
    return a.date.compareTo(b.date);
  });
  return items;
}

class ActivityItem {
  const ActivityItem({
    required this.circle,
    required this.round,
    required this.contribution,
    required this.counterparty,
    required this.incoming,
  });

  final Circle circle;
  final Round round;
  final Contribution contribution;
  final Member? counterparty;

  /// True when someone paid the member (they were collecting).
  final bool incoming;

  DateTime get date => contribution.payerConfirmedAt ?? round.dueDate;
}

List<ActivityItem> activity(List<Circle> circles, String me) {
  final items = <ActivityItem>[];
  for (final c in circles) {
    for (final x in c.contributions) {
      if (x.status == ContributionStatus.pending) continue;
      final round = c.rounds.where((r) => r.id == x.roundId).firstOrNull;
      if (round == null) continue;
      if (x.userId == me) {
        items.add(ActivityItem(
          circle: c,
          round: round,
          contribution: x,
          counterparty: c.memberById(round.collectorId),
          incoming: false,
        ));
      } else if (round.collectorId == me) {
        items.add(ActivityItem(
          circle: c,
          round: round,
          contribution: x,
          counterparty: c.memberById(x.userId),
          incoming: true,
        ));
      }
    }
  }
  items.sort((a, b) => b.date.compareTo(a.date));
  return items;
}

class CircleShare {
  const CircleShare(this.circle, this.amount, this.share);
  final Circle circle;
  final int amount;
  final double share;
}

class RecordStats {
  const RecordStats({
    required this.confirmedPayments,
    required this.onTimePayments,
    required this.totalContributed,
    required this.byCircle,
    required this.monthly,
    required this.circlesActive,
    required this.turnsCollected,
  });

  final int confirmedPayments;
  final int onTimePayments;
  final int totalContributed;
  final List<CircleShare> byCircle;

  /// Amount the member paid in each of the last 6 calendar months, oldest first.
  final List<({DateTime month, int amount})> monthly;
  final int circlesActive;
  final int turnsCollected;

  double get onTimeRate => confirmedPayments == 0 ? 0 : onTimePayments / confirmedPayments;
}

RecordStats recordStats(List<Circle> circles, String me, {DateTime? now}) {
  final today = now ?? DateTime.now();
  var confirmed = 0;
  var onTime = 0;
  var total = 0;
  var turns = 0;
  final perCircle = <Circle, int>{};
  final months = [for (var i = 5; i >= 0; i--) DateTime(today.year, today.month - i)];
  final monthly = {for (final m in months) m: 0};

  for (final c in circles) {
    for (final r in c.rounds) {
      if (r.collectorId == me && r.status == RoundStatus.completed) turns++;
    }
    for (final x in c.contributions) {
      if (x.userId != me || x.status != ContributionStatus.fullyConfirmed) continue;
      final round = c.rounds.where((r) => r.id == x.roundId).firstOrNull;
      if (round == null) continue;
      confirmed++;
      final paidAt = x.payerConfirmedAt;
      if (paidAt == null || !DateTime(paidAt.year, paidAt.month, paidAt.day).isAfter(round.dueDate)) onTime++;
      total += x.amount;
      perCircle[c] = (perCircle[c] ?? 0) + x.amount;
      final at = paidAt ?? round.dueDate;
      final key = DateTime(at.year, at.month);
      if (monthly.containsKey(key)) monthly[key] = monthly[key]! + x.amount;
    }
  }

  final shares = [
    for (final e in perCircle.entries) CircleShare(e.key, e.value, total == 0 ? 0 : e.value / total),
  ]..sort((a, b) => b.amount.compareTo(a.amount));

  return RecordStats(
    confirmedPayments: confirmed,
    onTimePayments: onTime,
    totalContributed: total,
    byCircle: shares,
    monthly: [for (final m in months) (month: m, amount: monthly[m]!)],
    circlesActive: circles.where((c) => c.activeRound != null).length,
    turnsCollected: turns,
  );
}
