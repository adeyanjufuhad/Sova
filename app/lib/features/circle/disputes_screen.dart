import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/adire_painter.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/polish.dart';
import '../../shared/widgets/pin_pad.dart';

/// Short title for a dispute, from the signed-in member's point of view.
String disputeTitle(Dispute d, String me) {
  String name(Person p) => p.id == me ? 'Your' : "${p.firstName}'s";
  return switch (d.kind) {
    DisputeKind.payment => '${name(d.payers.first)} turn ${d.turn} payment',
    DisputeKind.shortfall => 'Turn ${d.turn} payout came up short',
  };
}

/// Every dispute in a circle, open ones first.
class DisputesScreen extends ConsumerWidget {
  const DisputesScreen({super.key, required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(disputesProvider(circleId));
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Disputes')),
      body: async.when(
        loading: () => const SkeletonList(),
        error: (e, _) => ErrorView(message: e.toString(), onRetry: () => ref.invalidate(disputesProvider(circleId))),
        data: (list) => RefreshIndicator(
          color: SovaColors.electric,
          onRefresh: () => ref.refresh(disputesProvider(circleId).future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.lg, SovaSpacing.screenH, SovaSpacing.xl4),
            children: [
              const Text(
                'When a payment is disputed, the members who are not involved decide whether the money arrived. '
                'A short payout closes by itself once the missing payments are confirmed.',
                style: SovaText.bodySmall,
              ),
              const SizedBox(height: SovaSpacing.xl),
              if (list.isEmpty)
                const EmptyState(
                  icon: Icons.verified_outlined,
                  title: 'No disputes',
                  message: 'Nothing is disputed in this circle. If a payment goes missing, the payer or the collector '
                      'can raise a dispute from the payment.',
                ),
              for (final d in list) ...[
                _DisputeCard(dispute: d, me: me),
                const SizedBox(height: SovaSpacing.md),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DisputeCard extends StatelessWidget {
  const _DisputeCard({required this.dispute, required this.me});

  final Dispute dispute;
  final String me;

  @override
  Widget build(BuildContext context) {
    final d = dispute;
    final tally = d.kind == DisputeKind.payment && d.open
        ? '${d.payerVotes + d.collectorVotes} of ${d.eligibleVoters} voted · ${d.votesNeeded} decide'
        : d.open
            ? 'Missing: ${d.payerNames}'
            : d.resolutionNote ?? '';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/circle/${d.circleId}/disputes/${d.id}'),
        child: Padding(
          padding: const EdgeInsets.all(SovaSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.gavel_rounded, color: d.open ? SovaColors.electric : SovaColors.textMuted),
              const SizedBox(width: SovaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(disputeTitle(d, me), style: SovaText.label),
                    const SizedBox(height: 2),
                    Text(d.reason, style: SovaText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: SovaSpacing.sm),
                    Wrap(
                      spacing: SovaSpacing.sm,
                      runSpacing: SovaSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatusChip(d.status),
                        Text(tally, style: SovaText.caption),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: SovaColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);

  final DisputeStatus status;

  @override
  Widget build(BuildContext context) {
    final open = status == DisputeStatus.open;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: open ? SovaColors.navy900 : SovaColors.electricTint,
        borderRadius: BorderRadius.circular(SovaRadius.full),
      ),
      child: Text(
        status.label,
        style: SovaText.caption.copyWith(color: open ? SovaColors.white : SovaColors.electric, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// One dispute: what is claimed, the evidence, the vote and the history.
class DisputeScreen extends ConsumerWidget {
  const DisputeScreen({super.key, required this.circleId, required this.disputeId});

  final String circleId;
  final String disputeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(disputeProvider(disputeId));
    return Scaffold(
      appBar: AppBar(leading: SovaBackButton(fallback: '/circle/$circleId'), title: const Text('Dispute')),
      body: async.when(
        loading: () => const SkeletonList(),
        error: (e, _) => ErrorView(message: e.toString(), onRetry: () => ref.invalidate(disputeProvider(disputeId))),
        data: (d) => RefreshIndicator(
          color: SovaColors.electric,
          onRefresh: () => ref.refresh(disputeProvider(disputeId).future),
          child: _DisputeBody(dispute: d),
        ),
      ),
    );
  }
}

class _DisputeBody extends ConsumerWidget {
  const _DisputeBody({required this.dispute});

  final Dispute dispute;

  /// Runs a dispute action, then refreshes the dispute and its circle.
  static Future<void> _after(WidgetRef ref, Dispute d) async {
    ref.invalidate(disputeProvider(d.id));
    refreshCircle(ref, d.circleId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final d = dispute;
    final onBlue = SovaText.bodySmall.copyWith(color: SovaColors.white.withValues(alpha: 0.85));
    final payer = d.payers.firstOrNull;
    final question = switch (d.kind) {
      DisputeKind.payment =>
        'Did ${payer?.id == me ? 'your' : "${payer?.firstName}'s"} ${naira(d.payment!.amount)} reach '
            '${d.collector.id == me ? 'you' : d.collector.firstName}?',
      DisputeKind.shortfall => 'Turn ${d.turn} payout came up short',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.lg, SovaSpacing.screenH, SovaSpacing.xl4),
      children: [
        AdirePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(
                'Turn ${d.turn} · ${d.kind == DisputeKind.payment ? 'payment' : 'shortfall'} · ${d.status.label}',
                onBlue: true,
              ),
              const SizedBox(height: SovaSpacing.md),
              Text(question, style: SovaText.h2.copyWith(color: SovaColors.white)),
              const SizedBox(height: SovaSpacing.xs),
              Text('“${d.reason}”', style: onBlue),
              const SizedBox(height: SovaSpacing.sm),
              Text('Raised by ${d.raisedBy.id == me ? 'you' : d.raisedBy.name} · ${shortDate(d.createdAt)}', style: onBlue),
            ],
          ),
        ),
        if (!d.open && d.resolutionNote != null) ...[
          const SizedBox(height: SovaSpacing.lg),
          NoticeBox(
            '${d.resolutionNote!} ${switch (d.status) {
              DisputeStatus.resolvedForPayer when d.kind == DisputeKind.payment => 'The payment now counts as confirmed.',
              DisputeStatus.resolvedForCollector => 'The payment is back to unpaid; it can be paid again.',
              _ => '',
            }}'
                .trim(),
            icon: Icons.task_alt_rounded,
          ),
        ],
        const SizedBox(height: SovaSpacing.xl3),
        const Eyebrow('Who is involved'),
        const SizedBox(height: SovaSpacing.md),
        _PartiesCard(dispute: d, me: me),
        if (d.payment != null) ...[
          const SizedBox(height: SovaSpacing.xl3),
          const Eyebrow('The payment'),
          const SizedBox(height: SovaSpacing.md),
          _PaymentCard(payment: d.payment!),
        ],
        if (d.kind == DisputeKind.payment) ...[
          const SizedBox(height: SovaSpacing.xl3),
          const Eyebrow('The circle decides'),
          const SizedBox(height: SovaSpacing.md),
          _VoteCard(dispute: d, onDone: () => _after(ref, d)),
        ],
        if (d.canSettle || (d.open && d.kind == DisputeKind.shortfall && d.myRole == DisputeRole.payer)) ...[
          const SizedBox(height: SovaSpacing.xl3),
          const Eyebrow('Settle it yourself'),
          const SizedBox(height: SovaSpacing.md),
          _SettleCard(dispute: d, onDone: () => _after(ref, d)),
        ],
        const SizedBox(height: SovaSpacing.xl3),
        const Eyebrow('What happened'),
        const SizedBox(height: SovaSpacing.md),
        _Timeline(dispute: d, me: me),
        if (d.open) ...[
          const SizedBox(height: SovaSpacing.md),
          _CommentBox(dispute: d, onDone: () => _after(ref, d)),
        ],
      ],
    );
  }
}

class _PartiesCard extends StatelessWidget {
  const _PartiesCard({required this.dispute, required this.me});

  final Dispute dispute;
  final String me;

  @override
  Widget build(BuildContext context) {
    final d = dispute;
    String named(Person p) => p.id == me ? '${p.name} (you)' : p.name;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SovaSpacing.lg),
        child: Column(
          children: [
            InfoRow('Collector', named(d.collector)),
            const Divider(height: SovaSpacing.xl),
            InfoRow(
              d.kind == DisputeKind.payment ? 'Payer' : 'Still missing',
              d.payers.isEmpty ? 'Nobody' : d.payers.map(named).join(', '),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentCard extends ConsumerWidget {
  const _PaymentCard({required this.payment});

  final DisputePayment payment;

  Future<void> _viewProof(BuildContext context, WidgetRef ref) async {
    try {
      final url = await ref.read(repositoryProvider).proofUrl(payment.contributionId);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = payment;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SovaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoRow('Amount', naira(p.amount), valueStyle: SovaText.moneySmall),
            if (p.paidAt != null) InfoRow('Marked as sent', '${shortDate(p.paidAt!)}, ${clockTime(p.paidAt!)}'),
            InfoRow('Bank reference', p.bankReference ?? 'None given'),
            if (p.hasProof) ...[
              const SizedBox(height: SovaSpacing.md),
              OutlinedButton.icon(
                onPressed: () => _viewProof(context, ref),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('View receipt photo'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VoteCard extends ConsumerWidget {
  const _VoteCard({required this.dispute, required this.onDone});

  final Dispute dispute;
  final Future<void> Function() onDone;

  static String _sideLabel(DisputeSide s) => s == DisputeSide.payer ? 'It arrived' : "It didn't arrive";

  Future<void> _vote(BuildContext context, WidgetRef ref, DisputeSide side) async {
    final repo = ref.read(repositoryProvider);
    final ok = await confirmWithPin(
      context,
      title: 'Vote: ${_sideLabel(side).toLowerCase()}',
      subtitle: 'Your vote is recorded in the circle\'s record. You can change it while the dispute is open.',
      onPin: (pin) => repo.voteDispute(disputeId: dispute.id, side: side, pin: pin),
    );
    if (!ok) return;
    HapticFeedback.mediumImpact();
    await onDone();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = dispute;
    final total = d.eligibleVoters == 0 ? 1 : d.eligibleVoters;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SovaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              d.eligibleVoters == 0
                  ? 'Nobody else is in this circle to vote, so the payer and collector settle it between them.'
                  : '${d.eligibleVoters} member${d.eligibleVoters == 1 ? '' : 's'} can vote. '
                      '${d.votesNeeded} votes for one side decide it.',
              style: SovaText.bodySmall,
            ),
            const SizedBox(height: SovaSpacing.lg),
            _TallyBar(label: 'It arrived', votes: d.payerVotes, of: total, needed: d.votesNeeded),
            const SizedBox(height: SovaSpacing.md),
            _TallyBar(label: "It didn't arrive", votes: d.collectorVotes, of: total, needed: d.votesNeeded),
            if (d.votes.isNotEmpty) ...[
              const SizedBox(height: SovaSpacing.lg),
              for (final v in d.votes)
                Padding(
                  padding: const EdgeInsets.only(bottom: SovaSpacing.xs),
                  child: Text('${v.voter.name}: ${_sideLabel(v.side).toLowerCase()}', style: SovaText.caption),
                ),
            ],
            if (d.canVote) ...[
              const SizedBox(height: SovaSpacing.lg),
              Text(
                d.myVote == null
                    ? 'Check the evidence, then vote.'
                    : 'You voted: ${_sideLabel(d.myVote!).toLowerCase()}. You can change it.',
                style: SovaText.label,
              ),
              const SizedBox(height: SovaSpacing.sm),
              for (final side in DisputeSide.values) ...[
                d.myVote == side
                    ? FilledButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.check_rounded),
                        label: Text(_sideLabel(side)),
                      )
                    : OutlinedButton(onPressed: () => _vote(context, ref, side), child: Text(_sideLabel(side))),
                const SizedBox(height: SovaSpacing.sm),
              ],
            ] else if (d.open && d.myRole != DisputeRole.voter && d.eligibleVoters > 0) ...[
              const SizedBox(height: SovaSpacing.lg),
              const NoticeBox('You are part of this dispute, so the other members decide it.', icon: Icons.groups_outlined),
            ],
          ],
        ),
      ),
    );
  }
}

class _TallyBar extends StatelessWidget {
  const _TallyBar({required this.label, required this.votes, required this.of, required this.needed});

  final String label;
  final int votes;
  final int of;
  final int needed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: SovaText.label)),
            Text('$votes of $needed needed', style: SovaText.caption),
          ],
        ),
        const SizedBox(height: SovaSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(SovaRadius.full),
          child: LinearProgressIndicator(
            value: (votes / of).clamp(0.0, 1.0),
            minHeight: 8,
            color: SovaColors.electric,
            backgroundColor: SovaColors.electricTint,
          ),
        ),
      ],
    );
  }
}

class _SettleCard extends ConsumerWidget {
  const _SettleCard({required this.dispute, required this.onDone});

  final Dispute dispute;
  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = dispute;
    final collector = d.myRole == DisputeRole.collector;
    if (d.kind == DisputeKind.shortfall && !collector) {
      return NoticeBox(
        'Pay ${d.collector.firstName} your turn ${d.turn} contribution and ask them to confirm it. '
        'This closes by itself once every missing payment is confirmed.',
        icon: Icons.north_east_rounded,
      );
    }
    final (label, explain, title) = switch ((d.kind, collector)) {
      (DisputeKind.payment, true) => (
          'The money has arrived',
          'If you have now found the payment, confirm it. The dispute closes and the payment counts as confirmed.',
          'Confirm the money arrived',
        ),
      (DisputeKind.payment, false) => (
          "It didn't arrive; I'll pay again",
          'If the transfer failed, agree with the collector. The dispute closes and you can pay again.',
          'Agree it did not arrive',
        ),
      _ => (
          'Mark as settled',
          'If the missing money reached you some other way, or the circle agreed to forgive it, close the dispute.',
          'Mark the shortfall as settled',
        ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SovaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(explain, style: SovaText.bodySmall),
            const SizedBox(height: SovaSpacing.md),
            OutlinedButton(
              onPressed: () async {
                final repo = ref.read(repositoryProvider);
                final ok = await confirmWithPin(
                  context,
                  title: title,
                  subtitle: 'This closes the dispute for everyone. Enter your PIN.',
                  onPin: (pin) => repo.settleDispute(disputeId: d.id, pin: pin),
                );
                if (ok) await onDone();
              },
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.dispute, required this.me});

  final Dispute dispute;
  final String me;

  static const _kinds = {'opened': 'opened it', 'comment': 'said', 'evidence': 'added evidence', 'resolved': 'closed it'};

  @override
  Widget build(BuildContext context) {
    final events = dispute.timeline;
    if (events.isEmpty) return const NoticeBox('Nothing has been said yet.');
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.lg, vertical: SovaSpacing.sm),
        child: Column(
          children: [
            for (final (i, e) in events.indexed) ...[
              if (i > 0) const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: SovaSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: SovaColors.electricTint,
                      child: Text(e.actor.name.isEmpty ? '?' : e.actor.name[0],
                          style: SovaText.caption.copyWith(color: SovaColors.electric, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: SovaSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${e.actor.id == me ? 'You' : e.actor.firstName} ${_kinds[e.kind] ?? e.kind} · '
                            '${shortDate(e.at)}, ${clockTime(e.at)}',
                            style: SovaText.caption,
                          ),
                          if (e.message != null) ...[
                            const SizedBox(height: 2),
                            Text(e.message!, style: SovaText.bodySmall.copyWith(color: SovaColors.navy900)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommentBox extends ConsumerStatefulWidget {
  const _CommentBox({required this.dispute, required this.onDone});

  final Dispute dispute;
  final Future<void> Function() onDone;

  @override
  ConsumerState<_CommentBox> createState() => _CommentBoxState();
}

class _CommentBoxState extends ConsumerState<_CommentBox> {
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _text.text.trim();
    if (message.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).commentOnDispute(disputeId: widget.dispute.id, message: message);
      _text.clear();
      await widget.onDone();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _text,
            maxLength: 500,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Add what you know', counterText: ''),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: SovaSpacing.sm),
        IconButton.filled(
          tooltip: 'Send',
          onPressed: _busy ? null : _send,
          icon: const Icon(Icons.send_rounded, color: SovaColors.white),
        ),
      ],
    );
  }
}

/// Asks why, then the PIN, then raises the dispute and opens it. Used by the
/// collector ("it hasn't arrived") and by the payer ("it isn't being confirmed").
Future<void> raiseDisputeFlow(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  required String contributionId,
  required bool asCollector,
}) async {
  final reason = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SovaColors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(SovaRadius.xl2))),
    builder: (_) => _ReasonSheet(asCollector: asCollector),
  );
  if (reason == null || !context.mounted) return;
  final repo = ref.read(repositoryProvider);
  Dispute? raised;
  final ok = await confirmWithPin(
    context,
    title: 'Raise a dispute',
    subtitle: 'The payment is frozen and the other members decide whether the money arrived.',
    onPin: (pin) async => raised = await repo.raiseDispute(contributionId: contributionId, reason: reason, pin: pin),
  );
  if (!ok || raised == null || !context.mounted) return;
  refreshCircle(ref, circleId);
  context.push('/circle/$circleId/disputes/${raised!.id}');
}

class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet({required this.asCollector});

  final bool asCollector;

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  late final _text = TextEditingController(
    text: widget.asCollector
        ? 'This payment has not reached my account.'
        : 'I sent this payment but it has not been confirmed.',
  );
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _text.text.trim();
    if (reason.length < 3) {
      setState(() => _error = 'Say what went wrong.');
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.xl2, SovaSpacing.screenH, SovaSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.asCollector ? "This payment hasn't arrived" : "This payment isn't being confirmed",
                  style: SovaText.h2),
              const SizedBox(height: SovaSpacing.xs),
              Text(
                widget.asCollector
                    ? 'Check your bank first. The other members will see the bank reference and any receipt photo, '
                        'and vote on whether the money arrived.'
                    : 'The other members will see your bank reference and receipt photo, and vote on whether the money arrived.',
                style: SovaText.bodySmall,
              ),
              const SizedBox(height: SovaSpacing.lg),
              TextField(
                controller: _text,
                maxLength: 500,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: 'What went wrong?', errorText: _error),
              ),
              const SizedBox(height: SovaSpacing.md),
              FilledButton(onPressed: _submit, child: const Text('Continue')),
            ],
          ),
        ),
      ),
    );
  }
}
