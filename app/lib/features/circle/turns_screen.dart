import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/pin_pad.dart';
import '../../shared/widgets/polish.dart';

bool _turnOpen(Circle c, int? position) =>
    position == null ||
    !c.rounds.any((r) => r.number == position && (r.status == RoundStatus.active || r.status == RoundStatus.completed));

/// Swapping turns with another member, and handing a place to someone new.
class TurnsScreen extends ConsumerWidget {
  const TurnsScreen({super.key, required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circle = ref.watch(circleProvider(circleId));
    final changes = ref.watch(turnChangesProvider(circleId));
    return Scaffold(
      appBar: AppBar(
        leading: SovaBackButton(fallback: '/circle/$circleId'),
        title: const Text('Swaps and handovers'),
      ),
      body: switch ((circle, changes)) {
        (AsyncData(value: final c), AsyncData(value: final t)) => RefreshIndicator(
            color: SovaColors.electric,
            onRefresh: () async {
              refreshCircle(ref, circleId);
              await ref.read(turnChangesProvider(circleId).future);
            },
            child: _TurnsBody(circle: c, changes: t),
          ),
        (AsyncError(:final error), _) || (_, AsyncError(:final error)) => ErrorView(
            message: error.toString(),
            onRetry: () => refreshCircle(ref, circleId),
          ),
        _ => const SkeletonList(),
      },
    );
  }
}

class _TurnsBody extends ConsumerWidget {
  const _TurnsBody({required this.circle, required this.changes});

  final Circle circle;
  final TurnChanges changes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final c = circle;
    final mine = c.memberById(me);
    final myTurn = mine?.position;
    final open = _turnOpen(c, myTurn);
    final toAnswer = changes.swaps.where((s) => s.canAnswer).toList();
    final toApprove = changes.handovers.where((h) => h.canApprove).toList();
    final mineOpen = [
      ...changes.swaps.where((s) => s.canCancel).map((s) => _SwapTile(circle: c, swap: s, me: me)),
      ...changes.handovers.where((h) => h.canCancel).map((h) => _HandoverTile(circle: c, handover: h, me: me)),
    ];
    final history = [
      ...changes.swaps.where((s) => !s.canAnswer && !s.canCancel).map((s) => (s.createdAt, _SwapTile(circle: c, swap: s, me: me) as Widget)),
      ...changes.handovers
          .where((h) => !h.canApprove && !h.canCancel)
          .map((h) => (h.createdAt, _HandoverTile(circle: c, handover: h, me: me) as Widget)),
    ]..sort((a, b) => b.$1.compareTo(a.$1));

    return ListView(
      padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.lg, SovaSpacing.screenH, SovaSpacing.xl4),
      children: [
        Text(
          myTurn == null
              ? 'Turns are drawn when the circle is full.'
              : open
                  ? 'You collect on turn $myTurn. You can swap it with another member whose turn hasn\'t started, '
                      'or hand your place to someone new.'
                  : 'Your turn ($myTurn) has started or passed, so it can\'t be swapped or handed over.',
          style: SovaText.bodySmall,
        ),
        if (toAnswer.isNotEmpty || toApprove.isNotEmpty) ...[
          const SizedBox(height: SovaSpacing.xl),
          const Eyebrow('Needs your answer'),
          const SizedBox(height: SovaSpacing.md),
          for (final s in toAnswer) _SwapTile(circle: c, swap: s, me: me),
          for (final h in toApprove) _HandoverTile(circle: c, handover: h, me: me),
        ],
        if (open && c.status == CircleStatus.active || (c.forming && c.adminId != me)) ...[
          const SizedBox(height: SovaSpacing.xl),
          if (c.status == CircleStatus.active)
            FilledButton.icon(
              onPressed: () => _askSwap(context, ref),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Ask to swap turns'),
            ),
          if (c.adminId != me) ...[
            const SizedBox(height: SovaSpacing.sm),
            OutlinedButton.icon(
              onPressed: () => _handOver(context, ref),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Hand over my place'),
            ),
          ],
        ],
        if (mineOpen.isNotEmpty) ...[
          const SizedBox(height: SovaSpacing.xl),
          const Eyebrow('Your requests'),
          const SizedBox(height: SovaSpacing.md),
          ...mineOpen,
        ],
        const SizedBox(height: SovaSpacing.xl),
        const Eyebrow('History'),
        const SizedBox(height: SovaSpacing.md),
        if (history.isEmpty)
          const EmptyState(
            icon: Icons.swap_horiz_rounded,
            title: 'No swaps or handovers yet',
            message: 'Every agreed swap and handover is kept here and on the circle\'s record.',
          )
        else
          for (final (_, w) in history) w,
      ],
    );
  }

  Future<void> _askSwap(BuildContext context, WidgetRef ref) async {
    final me = ref.read(meProvider);
    final c = circle;
    final choices = [
      for (final m in c.membersByPosition)
        if (m.userId != me && _turnOpen(c, m.position) && !(c.adminCollectsLast && m.userId == c.adminId)) m,
    ];
    final picked = await showModalBottomSheet<(Member, String)>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: SovaColors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(SovaRadius.xl2))),
      builder: (_) => _SwapSheet(choices: choices, myTurn: c.memberById(me)?.position),
    );
    if (picked == null || !context.mounted) return;
    final (target, reason) = picked;
    final repo = ref.read(repositoryProvider);
    final ok = await confirmWithPin(
      context,
      title: 'Ask ${target.firstName} to swap',
      subtitle: 'You would collect on turn ${target.position} and ${target.firstName} on turn '
          '${c.memberById(me)?.position}, if they accept.',
      onPin: (pin) => repo.requestSwap(circleId: c.id, targetId: target.userId, reason: reason, pin: pin),
    );
    if (ok) refreshCircle(ref, c.id);
  }

  Future<void> _handOver(BuildContext context, WidgetRef ref) async {
    final me = ref.read(meProvider);
    final c = circle;
    final paidIn = c.contributions
        .where((x) => x.userId == me && x.status == ContributionStatus.fullyConfirmed)
        .fold(0, (t, x) => t + x.amount);
    final picked = await showModalBottomSheet<(String, String)>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: SovaColors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(SovaRadius.xl2))),
      builder: (_) => _HandoverSheet(paidIn: paidIn, adminName: c.memberById(c.adminId)?.firstName ?? 'the admin'),
    );
    if (picked == null || !context.mounted) return;
    final (phone, reason) = picked;
    final repo = ref.read(repositoryProvider);
    final ok = await confirmWithPin(
      context,
      title: 'Hand over your place',
      subtitle: 'They accept the rules first, then the admin approves. It takes effect when the current turn ends.',
      onPin: (pin) => repo.requestHandover(circleId: c.id, phone: phone, reason: reason, pin: pin),
    );
    if (ok) refreshCircle(ref, c.id);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.text, {this.strong = false});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: strong ? SovaColors.navy900 : SovaColors.electricTint,
          borderRadius: BorderRadius.circular(SovaRadius.full),
        ),
        child: Text(
          text,
          style: SovaText.caption.copyWith(color: strong ? SovaColors.white : SovaColors.electric, fontWeight: FontWeight.w600),
        ),
      );
}

/// Runs a request action, refreshing the circle afterwards and showing errors.
Future<void> _act(BuildContext context, WidgetRef ref, String circleId, Future<void> Function() action) async {
  try {
    await action();
    refreshCircle(ref, circleId);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
  }
}

class _SwapTile extends ConsumerWidget {
  const _SwapTile({required this.circle, required this.swap, required this.me});

  final Circle circle;
  final SwapRequest swap;
  final String me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = swap;
    final repo = ref.read(repositoryProvider);
    String who(TurnPerson p) => p.id == me ? 'you' : p.firstName;
    final title = s.canAnswer
        ? '${s.requester.firstName} asks to swap turns with you'
        : s.canCancel
            ? 'You asked ${s.target.firstName} to swap turns'
            : '${who(s.requester)[0].toUpperCase()}${who(s.requester).substring(1)} and ${who(s.target)}: swap of turns';
    final turns = s.status == SwapStatus.accepted
        ? '${who(s.requester)[0].toUpperCase()}${who(s.requester).substring(1)} now collects on turn ${s.requester.turn ?? '–'}, '
            '${who(s.target)} on turn ${s.target.turn ?? '–'}.'
        : s.requester.turn != null && s.target.turn != null
            ? 'Turn ${s.requester.turn} ⇄ turn ${s.target.turn}'
            : null;
    return _Tile(
      icon: Icons.swap_horiz_rounded,
      title: title,
      lines: [?turns, if (s.reason != null) '“${s.reason}”', shortDate(s.createdAt)],
      chip: _StatusChip(s.status.label, strong: s.canAnswer),
      actions: [
        if (s.canAnswer) ...[
          OutlinedButton(
            onPressed: () => _act(context, ref, circle.id, () => repo.answerSwap(circleId: circle.id, swapId: s.id, accept: false)),
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () async {
              final ok = await confirmWithPin(
                context,
                title: 'Swap turns with ${s.requester.firstName}',
                subtitle: 'You would collect on turn ${s.requester.turn} instead of turn ${s.target.turn}.',
                onPin: (pin) => repo.answerSwap(circleId: circle.id, swapId: s.id, accept: true, pin: pin),
              );
              if (ok) {
                HapticFeedback.mediumImpact();
                refreshCircle(ref, circle.id);
              }
            },
            child: const Text('Accept'),
          ),
        ],
        if (s.canCancel)
          OutlinedButton(
            onPressed: () => _act(context, ref, circle.id, () => repo.cancelSwap(circleId: circle.id, swapId: s.id)),
            child: const Text('Cancel request'),
          ),
      ],
    );
  }
}

class _HandoverTile extends ConsumerWidget {
  const _HandoverTile({required this.circle, required this.handover, required this.me});

  final Circle circle;
  final Handover handover;
  final String me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = handover;
    final repo = ref.read(repositoryProvider);
    final leaving = h.leaving.id == me ? 'You' : h.leaving.firstName;
    return _Tile(
      icon: Icons.person_add_alt_1_outlined,
      title: '$leaving → ${h.replacement.name}${h.leaving.turn == null ? '' : ' (turn ${h.leaving.turn})'}',
      lines: [
        if (h.reason != null) '“${h.reason}”',
        if (h.paidIn > 0) '$leaving paid ${naira(h.paidIn)} into earlier turns; they settle that between themselves.',
        shortDate(h.createdAt),
      ],
      chip: _StatusChip(h.status.label, strong: h.canApprove),
      actions: [
        if (h.canApprove) ...[
          OutlinedButton(
            onPressed: () => _act(
              context,
              ref,
              circle.id,
              () => repo.decideHandover(circleId: circle.id, handoverId: h.id, approve: false),
            ),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () async {
              final ok = await confirmWithPin(
                context,
                title: 'Approve the handover',
                subtitle: '${h.replacement.name} takes ${h.leaving.firstName}\'s place when the current turn ends.',
                onPin: (pin) => repo.decideHandover(circleId: circle.id, handoverId: h.id, approve: true, pin: pin),
              );
              if (ok) refreshCircle(ref, circle.id);
            },
            child: const Text('Approve'),
          ),
        ],
        if (h.canCancel)
          OutlinedButton(
            onPressed: () =>
                _act(context, ref, circle.id, () => repo.cancelHandover(circleId: circle.id, handoverId: h.id)),
            child: const Text('Cancel handover'),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.lines, required this.chip, required this.actions});

  final IconData icon;
  final String title;
  final List<String> lines;
  final Widget chip;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SovaSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(SovaSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconTile(icon, size: 36),
                  const SizedBox(width: SovaSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: SovaText.label),
                        const SizedBox(height: SovaSpacing.xs),
                        chip,
                        for (final l in lines) ...[
                          const SizedBox(height: SovaSpacing.xs),
                          Text(l, style: SovaText.caption),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: SovaSpacing.md),
                Row(
                  children: [
                    for (final (i, a) in actions.indexed) ...[
                      if (i > 0) const SizedBox(width: SovaSpacing.sm),
                      Expanded(child: a),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Choose the member to ask, and say why.
class _SwapSheet extends StatefulWidget {
  const _SwapSheet({required this.choices, required this.myTurn});

  final List<Member> choices;
  final int? myTurn;

  @override
  State<_SwapSheet> createState() => _SwapSheetState();
}

class _SwapSheetState extends State<_SwapSheet> {
  Member? _picked;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.xl2, SovaSpacing.screenH, SovaSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Ask to swap turns', style: SovaText.h2),
              const SizedBox(height: SovaSpacing.xs),
              Text(
                'You collect on turn ${widget.myTurn}. Only turns that haven\'t started can be swapped.',
                style: SovaText.bodySmall,
              ),
              const SizedBox(height: SovaSpacing.lg),
              if (widget.choices.isEmpty)
                const NoticeBox('No other turn is open for a swap right now.')
              else
                RadioGroup<Member>(
                  groupValue: _picked,
                  onChanged: (m) => setState(() => _picked = m),
                  child: Column(
                    children: [
                      for (final m in widget.choices)
                        RadioListTile<Member>(
                          value: m,
                          contentPadding: EdgeInsets.zero,
                          title: Text(m.name, style: SovaText.label),
                          subtitle: Text('Turn ${m.position}', style: SovaText.caption),
                          secondary: MemberAvatar(m, size: 36),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: SovaSpacing.md),
              TextField(
                controller: _reason,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Why? (optional)', hintText: 'My rent is due before my turn…'),
              ),
              const SizedBox(height: SovaSpacing.md),
              FilledButton(
                onPressed: _picked == null ? null : () => Navigator.of(context).pop((_picked!, _reason.text.trim())),
                child: Text(_picked == null ? 'Choose a member' : 'Ask ${_picked!.firstName}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who takes the place, and the money to settle between the two of them.
class _HandoverSheet extends StatefulWidget {
  const _HandoverSheet({required this.paidIn, required this.adminName});

  final int paidIn;
  final String adminName;

  @override
  State<_HandoverSheet> createState() => _HandoverSheetState();
}

class _HandoverSheetState extends State<_HandoverSheet> {
  final _phone = TextEditingController();
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final phone = normalisePhone(_phone.text);
    if (phone == null) {
      setState(() => _error = 'Enter a Nigerian mobile number, like 0803 123 4567.');
      return;
    }
    Navigator.of(context).pop((phone, _reason.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.xl2, SovaSpacing.screenH, SovaSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Hand over your place', style: SovaText.h2),
              const SizedBox(height: SovaSpacing.xs),
              Text(
                'Someone with a Sova account takes your place and your turn. They accept the rules, then '
                '${widget.adminName} approves. It takes effect when the current turn ends.',
                style: SovaText.bodySmall,
              ),
              if (widget.paidIn > 0) ...[
                const SizedBox(height: SovaSpacing.md),
                NoticeBox(
                  'You have paid ${naira(widget.paidIn)} into earlier turns. Agree with them how you get it back; '
                  'Sova only records the handover and never moves money.',
                  icon: Icons.handshake_outlined,
                ),
              ],
              const SizedBox(height: SovaSpacing.lg),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: InputDecoration(labelText: 'Their phone number', hintText: '0803 123 4567', errorText: _error),
              ),
              const SizedBox(height: SovaSpacing.md),
              TextField(
                controller: _reason,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Why? (optional)', hintText: 'I\'m moving to Abuja…'),
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
