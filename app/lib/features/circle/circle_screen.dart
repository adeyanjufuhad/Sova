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
import '../../shared/widgets/pin_pad.dart';

class CircleScreen extends ConsumerWidget {
  const CircleScreen({super.key, required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(circleProvider(circleId));
    return Scaffold(
      appBar: AppBar(title: Text(async.value?.name ?? '')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: e.toString(), onRetry: () => ref.invalidate(circleProvider(circleId))),
        data: (c) => RefreshIndicator(
          color: SovaColors.electric,
          onRefresh: () => ref.refresh(circleProvider(circleId).future),
          child: _CircleBody(circle: c),
        ),
      ),
    );
  }
}

class _CircleBody extends ConsumerWidget {
  const _CircleBody({required this.circle});

  final Circle circle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final c = circle;
    final round = c.activeRound;
    final collector = c.currentCollector;
    final iCollect = round != null && round.collectorId == me;

    return ListView(
      padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.lg, SovaSpacing.screenH, SovaSpacing.xl4),
      children: [
        Text(
          '${naira(c.contributionAmount)} ${c.cycle.label.toLowerCase()} · ${c.memberCount} members',
          style: SovaText.bodySmall,
        ),
        const SizedBox(height: SovaSpacing.lg),
        if (c.forming)
          AdirePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('Waiting for members', onBlue: true),
                const SizedBox(height: SovaSpacing.md),
                Text(
                  '${c.members.length} of ${c.memberCount} joined',
                  style: SovaText.h2.copyWith(color: SovaColors.white),
                ),
                const SizedBox(height: SovaSpacing.xs),
                Text(
                  'When everyone has joined and accepted the rules, Sova draws the turns fairly and turn 1 starts '
                  '(planned for ${longDate(c.startDate)}). Share the invite code below with people you trust.',
                  style: SovaText.bodySmall.copyWith(color: SovaColors.white.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: SovaSpacing.lg),
                ClipRRect(
                  borderRadius: BorderRadius.circular(SovaRadius.full),
                  child: LinearProgressIndicator(
                    value: c.members.length / c.memberCount,
                    minHeight: 6,
                    color: SovaColors.white,
                    backgroundColor: SovaColors.white.withValues(alpha: 0.25),
                  ),
                ),
              ],
            ),
          ),
        if (c.status == CircleStatus.completed)
          AdirePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('Circle complete', onBlue: true),
                const SizedBox(height: SovaSpacing.md),
                Text('All ${c.memberCount} turns paid out', style: SovaText.h2.copyWith(color: SovaColors.white)),
                const SizedBox(height: SovaSpacing.xs),
                Text(
                  "Every payment stays on the record and counts towards each member's Sova Score.",
                  style: SovaText.bodySmall.copyWith(color: SovaColors.white.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        if (round != null && collector != null)
          AdirePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow('Turn ${round.number} of ${c.memberCount}', onBlue: true),
                const SizedBox(height: SovaSpacing.md),
                Text(
                  iCollect ? 'You collect ${naira(c.payout)}' : '${collector.firstName} collects ${naira(c.payout)}',
                  style: SovaText.h2.copyWith(color: SovaColors.white),
                ),
                const SizedBox(height: SovaSpacing.xs),
                Text(
                  'Due ${longDate(round.dueDate)} (${relativeDay(round.dueDate)})',
                  style: SovaText.bodySmall.copyWith(color: SovaColors.white.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: SovaSpacing.lg),
                ClipRRect(
                  borderRadius: BorderRadius.circular(SovaRadius.full),
                  child: LinearProgressIndicator(
                    value: c.payersThisRound == 0 ? 0 : c.paidThisRound / c.payersThisRound,
                    minHeight: 6,
                    color: SovaColors.white,
                    backgroundColor: SovaColors.white.withValues(alpha: 0.25),
                  ),
                ),
                const SizedBox(height: SovaSpacing.sm),
                Text(
                  '${c.paidThisRound} of ${c.payersThisRound} payments confirmed',
                  style: SovaText.caption.copyWith(color: SovaColors.white.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        const SizedBox(height: SovaSpacing.lg),
        if (c.openDisputes > 0) ...[
          NoticeBox(
            c.openDisputes == 1
                ? 'There is an open dispute in this circle.'
                : 'There are ${c.openDisputes} open disputes in this circle.',
            icon: Icons.gavel_rounded,
          ),
          const SizedBox(height: SovaSpacing.lg),
        ],
        if (round != null) _MyAction(circle: c, round: round, me: me),
        const SizedBox(height: SovaSpacing.xl3),
        Eyebrow(c.forming ? 'Members' : 'Payout order'),
        const SizedBox(height: SovaSpacing.md),
        Card(
          child: Column(
            children: [
              for (final (i, m) in c.membersByPosition.indexed) ...[
                if (i > 0) const Divider(indent: SovaSpacing.lg, endIndent: SovaSpacing.lg),
                _MemberRow(circle: c, member: m, round: round, me: me),
              ],
            ],
          ),
        ),
        const SizedBox(height: SovaSpacing.xl3),
        const Eyebrow('Group rules'),
        const SizedBox(height: SovaSpacing.md),
        _RulesCard(circle: c, me: me),
        // Only circles on the server have a public record to check.
        if (apiUrl.isNotEmpty) ...[
          const SizedBox(height: SovaSpacing.xl3),
          const Eyebrow('Tamper-evident record'),
          const SizedBox(height: SovaSpacing.md),
          _VerifyCard(circleId: c.id),
        ],
        const SizedBox(height: SovaSpacing.xl3),
        if (c.forming) ...[
          const Eyebrow('Invite members'),
          const SizedBox(height: SovaSpacing.md),
          _InviteCard(code: c.inviteCode),
        ],
      ],
    );
  }
}

/// The one thing the signed-in member should do in this round.
class _MyAction extends ConsumerWidget {
  const _MyAction({required this.circle, required this.round, required this.me});

  final Circle circle;
  final Round round;
  final String me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = circle;
    if (round.collectorId == me) {
      final toConfirm = c.contributions
          .where((x) => x.roundId == round.id && x.status == ContributionStatus.payerConfirmed)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (toConfirm.isEmpty)
            const NoticeBox('You are collecting this turn. Payments members mark as sent will appear here.',
                icon: Icons.call_received_rounded)
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(SovaSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Check your bank, then confirm', style: SovaText.h3),
                    const SizedBox(height: SovaSpacing.xs),
                    const Text('Only confirm money that has actually arrived in your account.',
                        style: SovaText.bodySmall),
                    const SizedBox(height: SovaSpacing.md),
                    for (final x in toConfirm) _ConfirmRow(circle: c, contribution: x),
                  ],
                ),
              ),
            ),
          const SizedBox(height: SovaSpacing.md),
          OutlinedButton.icon(
            onPressed: () => context.push('/circle/${c.id}/payout'),
            icon: const Icon(Icons.task_alt_rounded),
            label: Text('Confirm payout received (${c.paidThisRound} of ${c.payersThisRound} paid)'),
          ),
        ],
      );
    }

    final status = c.statusFor(round.id, me);
    return switch (status) {
      ContributionStatus.pending => FilledButton.icon(
          onPressed: () => context.push('/circle/${c.id}/pay'),
          icon: const Icon(Icons.north_east_rounded),
          label: Text('Pay ${c.currentCollector?.firstName ?? 'collector'} ${naira(c.contributionAmount)}'),
        ),
      ContributionStatus.payerConfirmed => NoticeBox(
          'You recorded your payment. Waiting for ${c.currentCollector?.firstName ?? 'the collector'} to confirm it arrived.',
          icon: Icons.schedule_rounded,
        ),
      ContributionStatus.fullyConfirmed => const NoticeBox('Your payment for this turn is confirmed by both sides.',
          icon: Icons.done_all_rounded),
      ContributionStatus.disputed => const NoticeBox('Your payment for this turn is in dispute. The admin will review it.',
          icon: Icons.gavel_rounded),
    };
  }
}

class _ConfirmRow extends ConsumerStatefulWidget {
  const _ConfirmRow({required this.circle, required this.contribution});

  final Circle circle;
  final Contribution contribution;

  @override
  ConsumerState<_ConfirmRow> createState() => _ConfirmRowState();
}

class _ConfirmRowState extends ConsumerState<_ConfirmRow> {
  Future<void> _confirm() async {
    final payer = widget.circle.memberById(widget.contribution.userId);
    final repo = ref.read(repositoryProvider);
    final ok = await confirmWithPin(
      context,
      title: 'Confirm ${naira(widget.contribution.amount)} received',
      subtitle: 'From ${payer?.name ?? 'member'}. Enter your PIN to confirm.',
      onPin: (pin) => repo.confirmReceived(circleId: widget.circle.id, contributionId: widget.contribution.id, pin: pin),
    );
    if (!mounted || !ok) return;
    refreshCircle(ref, widget.circle.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Confirmed. ${payer?.firstName ?? 'They'} will get a receipt.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.contribution;
    final payer = widget.circle.memberById(x.userId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SovaSpacing.sm),
      child: Row(
        children: [
          if (payer != null) MemberAvatar(payer, size: 36),
          const SizedBox(width: SovaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payer?.name ?? 'Member', style: SovaText.label),
                Text(
                  [naira(x.amount), if (x.bankReference != null) 'Ref ${x.bankReference}', if (x.hasProof) 'receipt attached']
                      .join(' · '),
                  style: SovaText.caption,
                ),
              ],
            ),
          ),
          TextButton(onPressed: _confirm, child: const Text('Confirm')),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.circle, required this.member, required this.round, required this.me});

  final Circle circle;
  final Member member;
  final Round? round;
  final String me;

  @override
  Widget build(BuildContext context) {
    final c = circle;
    final m = member;
    final collected =
        m.position != null && c.rounds.any((r) => r.number == m.position && r.status == RoundStatus.completed);
    final collecting = round?.collectorId == m.userId;
    final voucher = m.vouchedBy == null ? null : c.memberById(m.vouchedBy!);

    final Widget trailing;
    if (collecting) {
      trailing = const _Tag('Collecting');
    } else if (round != null) {
      trailing = StatusPill(c.statusFor(round!.id, m.userId), compact: true);
    } else {
      trailing = const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.lg, vertical: SovaSpacing.md),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(m.position == null ? '–' : '${m.position}',
                style: SovaText.label.copyWith(color: SovaColors.textMuted)),
          ),
          MemberAvatar(m, size: 36, highlight: collecting),
          const SizedBox(width: SovaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.userId == me ? '${m.name} (you)' : m.name, style: SovaText.label),
                Text(
                  [
                    if (collected) 'Collected',
                    if (c.isAdmin(m.userId)) 'Admin',
                    if (voucher != null) 'Vouched for by ${voucher.firstName}',
                    if (m.owesAfterCollecting) 'Collected, then missed a payment',
                  ].join(' · ').ifEmpty(m.position == null ? 'Turn drawn when the circle is full' : 'Turn ${m.position}'),
                  style: SovaText.caption,
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.sm, vertical: SovaSpacing.xs),
        decoration: BoxDecoration(color: SovaColors.navy900, borderRadius: BorderRadius.circular(SovaRadius.full)),
        child: Text(text, style: SovaText.caption.copyWith(color: SovaColors.white, fontWeight: FontWeight.w600)),
      );
}

class _RulesCard extends StatelessWidget {
  const _RulesCard({required this.circle, required this.me});

  final Circle circle;
  final String me;

  @override
  Widget build(BuildContext context) {
    final rules = circle.rules;
    if (rules == null) {
      return const NoticeBox('This circle has no written rules yet. The admin can add them.');
    }
    final accepted = rules.acceptedBy.length;
    final iAccepted = rules.acceptedBy.contains(me);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/circle/${circle.id}/rules'),
        child: Padding(
          padding: const EdgeInsets.all(SovaSpacing.lg),
          child: Row(
            children: [
              const Icon(Icons.draw_rounded, color: SovaColors.electric),
              const SizedBox(width: SovaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rules version ${rules.version}', style: SovaText.label),
                    Text(
                      '$accepted of ${circle.members.length} members accepted'
                      '${iAccepted ? '' : ' · you have not accepted yet'}',
                      style: SovaText.caption,
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

/// Opens the public page that rechecks this circle's hash chain and fair draw.
class _VerifyCard extends StatelessWidget {
  const _VerifyCard({required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => launchUrl(Uri.parse('$siteUrl/verify?c=$circleId'), mode: LaunchMode.externalApplication),
        child: const Padding(
          padding: EdgeInsets.all(SovaSpacing.lg),
          child: Row(
            children: [
              Icon(Icons.verified_user_outlined, color: SovaColors.electric),
              SizedBox(width: SovaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Verify this circle', style: SovaText.label),
                    Text(
                      'Every payment and payout is chained with SHA-256. Anyone can recheck the record and the fair draw.',
                      style: SovaText.caption,
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, color: SovaColors.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SovaSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Invite code', style: SovaText.caption),
                  Text(code, style: SovaText.h2.copyWith(letterSpacing: 4)),
                  const Text('New members join on a member\'s word: whoever invites them vouches for them.',
                      style: SovaText.caption),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Copy code',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite code copied.')));
              },
              icon: const Icon(Icons.copy_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
