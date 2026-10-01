import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/demo_repository.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/adire_painter.dart';
import '../../shared/widgets/common.dart';

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

sealed class _Todo {
  const _Todo(this.circle);
  final Circle circle;
}

class _PayTodo extends _Todo {
  const _PayTodo(super.circle, this.collector, this.round);
  final Member collector;
  final Round round;
}

class _ConfirmTodo extends _Todo {
  const _ConfirmTodo(super.circle, this.payer, this.contribution);
  final Member payer;
  final Contribution contribution;
}

class _RulesTodo extends _Todo {
  const _RulesTodo(super.circle);
}

List<_Todo> _todosFor(List<Circle> circles, String me) {
  final todos = <_Todo>[];
  for (final c in circles) {
    if (c.rules != null && !c.rules!.acceptedBy.contains(me)) todos.add(_RulesTodo(c));
    final r = c.activeRound;
    if (r == null) continue;
    if (r.collectorId != me && c.statusFor(r.id, me) == ContributionStatus.pending) {
      final collector = c.memberById(r.collectorId);
      if (collector != null) todos.add(_PayTodo(c, collector, r));
    }
    if (r.collectorId == me) {
      for (final x in c.contributions) {
        if (x.roundId == r.id && x.status == ContributionStatus.payerConfirmed) {
          final payer = c.memberById(x.userId);
          if (payer != null) todos.add(_ConfirmTodo(c, payer, x));
        }
      }
    }
  }
  return todos;
}

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider).session;
    final circles = ref.watch(circlesProvider);
    final firstName = (session?.fullName ?? '').split(' ').first;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: SovaColors.electric,
          onRefresh: () => ref.refresh(circlesProvider.future),
          child: circles.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(message: e.toString(), onRetry: () => ref.invalidate(circlesProvider)),
            data: (list) {
              const me = DemoRepository.me;
              final todos = _todosFor(list, me);
              return ListView(
                padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.lg, SovaSpacing.screenH, SovaSpacing.xl3),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_greeting(), style: SovaText.bodySmall),
                            Text(firstName.isEmpty ? 'Welcome' : firstName, style: SovaText.h1),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sign out',
                        onPressed: () => ref.read(authProvider.notifier).signOut(),
                        icon: const Icon(Icons.logout_rounded, color: SovaColors.navy900),
                      ),
                    ],
                  ),
                  const SizedBox(height: SovaSpacing.xl),
                  _NextPayoutCard(circles: list, me: me),
                  const SizedBox(height: SovaSpacing.xl3),
                  const Eyebrow('To do'),
                  const SizedBox(height: SovaSpacing.md),
                  if (todos.isEmpty)
                    const NoticeBox('You are all caught up. Nothing to pay or confirm right now.',
                        icon: Icons.check_circle_outline_rounded)
                  else
                    Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < todos.length; i++) ...[
                            if (i > 0) const Divider(indent: SovaSpacing.lg, endIndent: SovaSpacing.lg),
                            _TodoTile(todos[i]),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: SovaSpacing.xl3),
                  const Eyebrow('My circles'),
                  const SizedBox(height: SovaSpacing.md),
                  for (final c in list) ...[
                    _CircleCard(circle: c, me: me),
                    const SizedBox(height: SovaSpacing.md),
                  ],
                  const SizedBox(height: SovaSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _comingNext(context, 'Starting a circle'),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Start'),
                        ),
                      ),
                      const SizedBox(width: SovaSpacing.md),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _comingNext(context, 'Joining with a code'),
                          icon: const Icon(Icons.qr_code_rounded),
                          label: const Text('Join'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _comingNext(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what is coming in the next build.')));
  }
}

class _NextPayoutCard extends StatelessWidget {
  const _NextPayoutCard({required this.circles, required this.me});

  final List<Circle> circles;
  final String me;

  @override
  Widget build(BuildContext context) {
    // The soonest payout that hasn't been completed yet.
    Circle? best;
    DateTime? bestDate;
    for (final c in circles) {
      final mine = c.memberById(me);
      if (mine == null) continue;
      final done = c.rounds.any((r) => r.number == mine.position && r.status == RoundStatus.completed);
      if (done) continue;
      final date = payoutDateFor(c, mine.position);
      if (bestDate == null || date.isBefore(bestDate)) {
        best = c;
        bestDate = date;
      }
    }

    return AdirePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Your next payout', onBlue: true),
          const SizedBox(height: SovaSpacing.md),
          if (best == null) ...[
            Text('No payout scheduled', style: SovaText.h2.copyWith(color: SovaColors.white)),
            const SizedBox(height: SovaSpacing.xs),
            Text('Join or start a circle to get a turn.',
                style: SovaText.bodySmall.copyWith(color: SovaColors.white.withValues(alpha: 0.8))),
          ] else ...[
            Text(naira(best.payout), style: SovaText.moneyLarge.copyWith(color: SovaColors.white)),
            const SizedBox(height: SovaSpacing.xs),
            Text(
              '${best.name} · ${longDate(bestDate!)} (${relativeDay(bestDate)})',
              style: SovaText.bodySmall.copyWith(color: SovaColors.white.withValues(alpha: 0.85)),
            ),
          ],
        ],
      ),
    );
  }
}

class _TodoTile extends ConsumerWidget {
  const _TodoTile(this.todo);

  final _Todo todo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = todo.circle;
    final (icon, title, subtitle, action) = switch (todo) {
      _PayTodo(:final collector, :final round) => (
          Icons.north_east_rounded,
          'Pay ${collector.firstName} ${naira(c.contributionAmount)}',
          '${c.name} · due ${relativeDay(round.dueDate)}',
          'Pay',
        ),
      _ConfirmTodo(:final payer, :final contribution) => (
          Icons.call_received_rounded,
          'Did ${payer.firstName} pay you ${naira(contribution.amount)}?',
          '${c.name} · check your bank, then confirm',
          'Check',
        ),
      _RulesTodo() => (
          Icons.draw_rounded,
          'Accept the group rules',
          c.name,
          'Read',
        ),
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: SovaSpacing.lg, vertical: SovaSpacing.xs),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: SovaColors.electricTint, borderRadius: BorderRadius.circular(SovaRadius.md)),
        child: Icon(icon, color: SovaColors.electric, size: 20),
      ),
      title: Text(title, style: SovaText.label),
      subtitle: Text(subtitle, style: SovaText.caption),
      trailing: Text(action, style: SovaText.label.copyWith(color: SovaColors.electric)),
      onTap: () => switch (todo) {
        _PayTodo() => context.push('/circle/${c.id}/pay'),
        _RulesTodo() => context.push('/circle/${c.id}/rules'),
        _ConfirmTodo() => context.push('/circle/${c.id}'),
      },
    );
  }
}

class _CircleCard extends StatelessWidget {
  const _CircleCard({required this.circle, required this.me});

  final Circle circle;
  final String me;

  @override
  Widget build(BuildContext context) {
    final c = circle;
    final round = c.activeRound;
    final mine = c.memberById(me);
    final progress = c.payersThisRound == 0 ? 0.0 : c.paidThisRound / c.payersThisRound;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/circle/${c.id}'),
        child: Padding(
          padding: const EdgeInsets.all(SovaSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(c.name, style: SovaText.h3, overflow: TextOverflow.ellipsis)),
                  if (c.isAdmin(me))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: SovaColors.borderStrong),
                        borderRadius: BorderRadius.circular(SovaRadius.full),
                      ),
                      child: const Text('Admin', style: SovaText.caption),
                    ),
                ],
              ),
              const SizedBox(height: SovaSpacing.xs),
              Text(
                '${naira(c.contributionAmount)} ${c.cycle.label.toLowerCase()} · ${c.memberCount} members'
                '${mine == null ? '' : ' · your turn: ${mine.position}'}',
                style: SovaText.caption,
              ),
              const SizedBox(height: SovaSpacing.lg),
              if (round != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Turn ${round.number} of ${c.memberCount}', style: SovaText.label),
                    Text('${c.paidThisRound} of ${c.payersThisRound} paid', style: SovaText.caption),
                  ],
                ),
                const SizedBox(height: SovaSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(SovaRadius.full),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: SovaColors.electric,
                    backgroundColor: SovaColors.electricTint,
                  ),
                ),
              ] else
                const Text('Waiting for the first turn to start', style: SovaText.caption),
            ],
          ),
        ),
      ),
    );
  }
}
