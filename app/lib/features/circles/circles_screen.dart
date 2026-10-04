import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/insights.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/polish.dart';

class CirclesScreen extends ConsumerStatefulWidget {
  const CirclesScreen({super.key});

  @override
  ConsumerState<CirclesScreen> createState() => _CirclesScreenState();
}

class _CirclesScreenState extends ConsumerState<CirclesScreen> {
  bool _completed = false;

  @override
  Widget build(BuildContext context) {
    final circles = ref.watch(circlesProvider);
    return Scaffold(
      body: SafeArea(
        child: circles.when(
          loading: () => const SkeletonList(),
          error: (e, _) => ErrorView(message: e.toString(), onRetry: () => ref.invalidate(circlesProvider)),
          data: (list) {
            final shown = list.where((c) => (c.activeRound == null && c.rounds.isNotEmpty) == _completed).toList();
            return RefreshIndicator(
              color: SovaColors.electric,
              onRefresh: () => ref.refresh(circlesProvider.future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  SovaSpacing.screenH,
                  SovaSpacing.lg,
                  SovaSpacing.screenH,
                  SovaSpacing.xl3,
                ),
                children: [
                  const Text('Circles', style: SovaText.h1),
                  const SizedBox(height: SovaSpacing.xs),
                  Text('${list.length} circles · your money stays in your bank', style: SovaText.bodySmall),
                  const SizedBox(height: SovaSpacing.xl),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _ActionCard(
                            icon: Icons.add_rounded,
                            title: 'Start a circle',
                            subtitle: 'Set the amount, rules and order',
                            primary: true,
                            onTap: () => context.push('/create'),
                          ),
                        ),
                        const SizedBox(width: SovaSpacing.md),
                        Expanded(
                          child: _ActionCard(
                            icon: Icons.qr_code_rounded,
                            title: 'Join with a code',
                            subtitle: 'From a member who vouches for you',
                            onTap: () => context.push('/join'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SovaSpacing.xl2),
                  SegmentedChips<bool>(
                    options: const {false: 'Active', true: 'Completed'},
                    selected: _completed,
                    onChanged: (v) => setState(() => _completed = v),
                  ),
                  const SizedBox(height: SovaSpacing.lg),
                  if (shown.isEmpty)
                    NoticeBox(
                      _completed ? 'Circles you finish will appear here.' : 'You are not in any active circle yet.',
                    ),
                  for (final (i, c) in shown.indexed)
                    StaggeredIn(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: SovaSpacing.md),
                        child: CircleCard(circle: c, me: ref.watch(meProvider)),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? SovaColors.white : SovaColors.navy900;
    return Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 132),
        padding: const EdgeInsets.all(SovaSpacing.lg),
        decoration: BoxDecoration(
          color: primary ? SovaColors.electric : SovaColors.white,
          borderRadius: BorderRadius.circular(SovaRadius.xl),
          border: primary ? null : Border.all(color: SovaColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: primary ? SovaColors.white.withValues(alpha: 0.18) : SovaColors.electricTint,
                borderRadius: BorderRadius.circular(SovaRadius.md),
              ),
              child: Icon(icon, size: 20, color: primary ? SovaColors.white : SovaColors.electric),
            ),
            const SizedBox(height: SovaSpacing.xl),
            Text(title, style: SovaText.label.copyWith(color: fg)),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: SovaText.caption.copyWith(
                color: primary ? SovaColors.white.withValues(alpha: 0.8) : SovaColors.textMuted,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Up to [max] overlapping initials, then "+N".
class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.members, this.max = 5, this.size = 30});

  final List<Member> members;
  final int max;
  final double size;

  @override
  Widget build(BuildContext context) {
    final shown = members.take(max).toList();
    final extra = members.length - shown.length;
    final step = size * 0.7;
    final count = shown.length + (extra > 0 ? 1 : 0);
    return SizedBox(
      height: size,
      width: step * (count - 1) + size,
      child: Stack(
        children: [
          for (final (i, m) in shown.indexed)
            Positioned(
              left: i * step,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i.isEven ? SovaColors.electricTintSolid : SovaColors.mistSolid,
                  shape: BoxShape.circle,
                  border: Border.all(color: SovaColors.white, width: 2),
                ),
                child: Text(
                  m.initial,
                  style: SovaText.caption.copyWith(color: SovaColors.electric, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * step,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SovaColors.navy900,
                  shape: BoxShape.circle,
                  border: Border.all(color: SovaColors.white, width: 2),
                ),
                child: Text(
                  '+$extra',
                  style: SovaText.caption.copyWith(color: SovaColors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _monogram(String name) {
  final words = name.replaceAll(RegExp(r"[^A-Za-z ]"), ' ').split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
  return (words[0][0] + words[1][0]).toUpperCase();
}

class CircleCard extends StatelessWidget {
  const CircleCard({super.key, required this.circle, required this.me});

  final Circle circle;
  final String me;

  @override
  Widget build(BuildContext context) {
    final c = circle;
    final round = c.activeRound;
    final mine = c.memberById(me);
    // Before the first turn, progress shows how full the circle is.
    final waiting = round == null && c.rounds.isEmpty;
    final progress = waiting
        ? c.members.length / c.memberCount
        : (c.payersThisRound == 0 ? 0.0 : c.paidThisRound / c.payersThisRound);

    return Pressable(
      onTap: () => context.push('/circle/${c.id}'),
      child: Container(
        padding: const EdgeInsets.all(SovaSpacing.lg),
        decoration: BoxDecoration(
          color: SovaColors.white,
          borderRadius: BorderRadius.circular(SovaRadius.xl),
          border: Border.all(color: SovaColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: SovaColors.navy900,
                    borderRadius: BorderRadius.circular(SovaRadius.md),
                  ),
                  child: Text(_monogram(c.name), style: SovaText.label.copyWith(color: SovaColors.white)),
                ),
                const SizedBox(width: SovaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: SovaText.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Money(c.contributionAmount, style: SovaText.caption),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: SovaColors.mist,
                    borderRadius: BorderRadius.circular(SovaRadius.full),
                  ),
                  child: Text(c.isAdmin(me) ? 'Admin · ${c.cycle.label}' : c.cycle.label, style: SovaText.caption),
                ),
              ],
            ),
            const SizedBox(height: SovaSpacing.lg),
            Row(
              children: [
                AvatarStack(members: c.membersByPosition),
                const Spacer(),
                if (round != null)
                  Text('Turn ${round.number} of ${c.memberCount}', style: SovaText.label.copyWith(fontSize: 13))
                else if (waiting)
                  Text('Waiting for members', style: SovaText.label.copyWith(fontSize: 13)),
              ],
            ),
            const SizedBox(height: SovaSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(SovaRadius.full),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                color: SovaColors.electric,
                backgroundColor: SovaColors.electricTint,
              ),
            ),
            const SizedBox(height: SovaSpacing.md),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: SovaSpacing.md,
              runSpacing: SovaSpacing.xs,
              children: [
                Text(
                  waiting
                      ? '${c.members.length} of ${c.memberCount} joined'
                      : '${c.paidThisRound} of ${c.payersThisRound} paid this turn',
                  style: SovaText.caption,
                ),
                if (mine != null)
                  Text(
                    _myTurnLabel(c, mine.position),
                    style: SovaText.caption.copyWith(color: SovaColors.electric, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the member stands in the payout order, in a few words.
String _myTurnLabel(Circle c, int? position) {
  if (position == null) return 'Turns drawn when full';
  final collected = c.rounds.any((r) => r.number == position && r.status == RoundStatus.completed);
  if (collected) return 'You collected (turn $position)';
  return 'Your turn: ${shortDate(payoutDateFor(c, position))}';
}
