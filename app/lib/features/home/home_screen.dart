import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/insights.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/app_shell.dart' show tabBarInset;
import '../../shared/widgets/adire_painter.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/polish.dart';

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

void comingNext(BuildContext context, String what) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what is coming in the next build.')));
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _actionsOnly = false;

  @override
  Widget build(BuildContext context) {
    final circles = ref.watch(circlesProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White status-bar icons over the blue header.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: circles.when(
          loading: () => const SafeArea(child: SkeletonList()),
          error: (e, _) => ErrorView(message: e.toString(), onRetry: () => ref.invalidate(circlesProvider)),
          data: (list) {
            final me = ref.watch(meProvider);
            final items = paymentItems(list, me);
            final shown = _actionsOnly ? items.where((i) => i.needsAction).toList() : items;
            final firstPay = items.where((i) => i.kind == PaymentKind.pay).firstOrNull;

            return RefreshIndicator(
              color: SovaColors.electric,
              onRefresh: () => ref.refresh(circlesProvider.future),
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _Header(circles: list, me: me, firstPay: firstPay, actionCount: items.where((i) => i.needsAction).length),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      SovaSpacing.screenH,
                      SovaSpacing.xl2,
                      SovaSpacing.screenH,
                      SovaSpacing.xl3 + tabBarInset(context),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionHeader('Payments', action: 'See all', onAction: () => context.go('/activity')),
                        const SizedBox(height: SovaSpacing.sm),
                        SegmentedChips<bool>(
                          options: const {false: 'All', true: 'Needs action'},
                          selected: _actionsOnly,
                          onChanged: (v) => setState(() => _actionsOnly = v),
                        ),
                        const SizedBox(height: SovaSpacing.md),
                        if (shown.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: SovaSpacing.lg),
                            child: NoticeBox('Nothing needs your attention right now.', icon: Icons.check_circle_outline_rounded),
                          ),
                        for (final (i, item) in shown.indexed)
                          StaggeredIn(index: i, child: _PaymentRow(item)),
                      ],
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

class _Header extends ConsumerWidget {
  const _Header({required this.circles, required this.me, required this.firstPay, required this.actionCount});

  final List<Circle> circles;
  final String me;
  final PaymentItem? firstPay;
  final int actionCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider).session;
    final name = session?.fullName ?? '';
    final hidden = ref.watch(hideAmountsProvider);
    final next = nextPayout(circles, me);
    final top = MediaQuery.paddingOf(context).top;
    final onBlueMuted = SovaColors.white.withValues(alpha: 0.75);

    return Stack(
      children: [
        // Solid blue block behind everything except the lower half of the nudge card.
        Positioned.fill(
          bottom: 92,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(SovaRadius.xl2 + 8)),
            child: ColoredBox(
              color: SovaColors.electric,
              child: CustomPaint(painter: AdirePainter(color: SovaColors.white.withValues(alpha: 0.07), tile: 110)),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(SovaSpacing.screenH, top + SovaSpacing.md, SovaSpacing.screenH, 0),
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
                      color: SovaColors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: SovaColors.white.withValues(alpha: 0.4), width: 3),
                    ),
                    child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: SovaText.h3.copyWith(color: SovaColors.electric)),
                  ),
                  const SizedBox(width: SovaSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_greeting(), style: SovaText.caption.copyWith(color: onBlueMuted)),
                        Text(name, style: SovaText.h3.copyWith(color: SovaColors.white), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  _RoundIcon(icon: Icons.search_rounded, label: 'Find a circle', onTap: () => context.go('/circles')),
                  const SizedBox(width: SovaSpacing.sm),
                  _RoundIcon(
                    icon: Icons.notifications_none_rounded,
                    label: '$actionCount things need your attention',
                    badge: actionCount > 0,
                    onTap: () => context.go('/activity'),
                  ),
                ],
              ),
              const SizedBox(height: SovaSpacing.xl3),
              Row(
                children: [
                  Text('Your next payout', style: SovaText.bodySmall.copyWith(color: onBlueMuted)),
                  const SizedBox(width: SovaSpacing.xs),
                  IconButton(
                    tooltip: hidden ? 'Show amounts' : 'Hide amounts',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => ref.read(hideAmountsProvider.notifier).toggle(),
                    icon: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: onBlueMuted),
                  ),
                ],
              ),
              const SizedBox(height: SovaSpacing.xs),
              Money(
                next?.circle.payout ?? 0,
                animate: true,
                style: SovaText.moneyLarge.copyWith(color: SovaColors.white, fontSize: 38),
              ),
              const SizedBox(height: SovaSpacing.sm),
              if (next != null)
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${next.circle.name} · ${shortDate(next.date)}',
                        style: SovaText.bodySmall.copyWith(color: onBlueMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: SovaSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: SovaColors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(SovaRadius.full),
                      ),
                      child: Text(relativeDay(next.date),
                          style: SovaText.caption.copyWith(color: SovaColors.white, fontWeight: FontWeight.w700)),
                    ),
                  ],
                )
              else
                Text('Join or start a circle to get a turn.', style: SovaText.bodySmall.copyWith(color: onBlueMuted)),
              const SizedBox(height: SovaSpacing.xl2),
              Row(
                children: [
                  Expanded(
                    child: _PillButton(
                      icon: Icons.north_east_rounded,
                      label: 'Pay',
                      onTap: firstPay == null
                          ? () => ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('You have nothing to pay right now.')))
                          : () => context.push('/circle/${firstPay!.circle.id}/pay'),
                    ),
                  ),
                  const SizedBox(width: SovaSpacing.md),
                  Expanded(
                    child: _PillButton(icon: Icons.add_rounded, label: 'Start', onTap: () => context.push('/create')),
                  ),
                  const SizedBox(width: SovaSpacing.md),
                  Pressable(
                    onTap: () => context.push('/join'),
                    semanticLabel: 'Join a circle with an invite code',
                    child: Container(
                      width: 54,
                      height: 52,
                      decoration: BoxDecoration(color: SovaColors.navy900, borderRadius: BorderRadius.circular(SovaRadius.lg)),
                      child: const Icon(Icons.qr_code_scanner_rounded, color: SovaColors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SovaSpacing.xl2),
              _NudgeCard(firstPay: firstPay),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.label, required this.onTap, this.badge = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: SovaColors.white.withValues(alpha: 0.14), shape: BoxShape.circle),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: SovaColors.white, size: 22),
            if (badge)
              Positioned(
                top: 10,
                right: 11,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: SovaColors.sky,
                    shape: BoxShape.circle,
                    border: Border.all(color: SovaColors.electric, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(color: SovaColors.white, borderRadius: BorderRadius.circular(SovaRadius.lg)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: SovaColors.navy900),
            const SizedBox(width: SovaSpacing.sm),
            Text(label, style: SovaText.label.copyWith(fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

/// The overlapping white card: one helpful, specific suggestion.
class _NudgeCard extends StatelessWidget {
  const _NudgeCard({required this.firstPay});

  final PaymentItem? firstPay;

  @override
  Widget build(BuildContext context) {
    final pay = firstPay;
    final collector = pay?.counterparty?.firstName ?? 'the collector';
    return Container(
      decoration: BoxDecoration(
        color: SovaColors.white,
        borderRadius: BorderRadius.circular(SovaRadius.xl2),
        border: Border.all(color: SovaColors.border),
      ),
      padding: const EdgeInsets.all(SovaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, size: 20, color: SovaColors.electric),
              const SizedBox(width: SovaSpacing.sm),
              Expanded(child: Text('Keep your record clean', style: SovaText.label.copyWith(fontSize: 15))),
            ],
          ),
          const SizedBox(height: SovaSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SovaSpacing.md),
            decoration: BoxDecoration(color: SovaColors.mist, borderRadius: BorderRadius.circular(SovaRadius.lg)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  pay == null
                      ? const TextSpan(text: 'You have paid everything that is due. Nice work: on-time payments move you up the payout order.')
                      : TextSpan(children: [
                          TextSpan(text: '$collector collects ${relativeDay(pay.date)}. Pay '),
                          TextSpan(
                              text: naira(pay.amount),
                              style: const TextStyle(fontWeight: FontWeight.w700, color: SovaColors.navy900)),
                          const TextSpan(text: ' on time to keep your record at 100%.'),
                        ]),
                  style: SovaText.bodySmall.copyWith(color: SovaColors.textSecondary),
                ),
                if (pay != null) ...[
                  const SizedBox(height: SovaSpacing.md),
                  Pressable(
                    onTap: () => context.push('/circle/${pay.circle.id}/pay'),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: SovaColors.white,
                        borderRadius: BorderRadius.circular(SovaRadius.md),
                        border: Border.all(color: SovaColors.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(child: Text('Pay $collector now', style: SovaText.label, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: SovaSpacing.sm),
                          const Icon(Icons.arrow_forward_rounded, size: 18, color: SovaColors.navy900),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow(this.item);

  final PaymentItem item;

  @override
  Widget build(BuildContext context) {
    final c = item.circle;
    final who = item.counterparty?.firstName ?? '';
    final (icon, title, subtitle, filled, incoming) = switch (item.kind) {
      PaymentKind.pay => (
          Icons.north_east_rounded,
          '${c.name} – $who',
          'Due ${shortDate(item.date)} · ${relativeDay(item.date)}',
          false,
          false,
        ),
      PaymentKind.awaiting => (
          Icons.schedule_rounded,
          '${c.name} – $who',
          'Paid · waiting for $who to confirm',
          false,
          false,
        ),
      PaymentKind.confirm => (
          Icons.call_received_rounded,
          '$who paid you',
          '${c.name} · check your bank, then confirm',
          false,
          true,
        ),
      PaymentKind.collect => (
          Icons.savings_outlined,
          'Your payout – ${c.name}',
          '${shortDate(item.date)} · ${relativeDay(item.date)}',
          true,
          true,
        ),
    };

    return Pressable(
      onTap: () => switch (item.kind) {
        PaymentKind.pay => context.push('/circle/${c.id}/pay'),
        _ => context.push('/circle/${c.id}'),
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SovaSpacing.md),
        child: Row(
          children: [
            IconTile(icon, filled: filled),
            const SizedBox(width: SovaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SovaText.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle, style: SovaText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: SovaSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Money(
                  item.amount,
                  prefix: incoming && item.kind == PaymentKind.confirm ? '+' : '',
                  style: SovaText.moneySmall.copyWith(color: incoming ? SovaColors.electric : SovaColors.navy900),
                ),
                if (item.needsAction) ...[
                  const SizedBox(height: 2),
                  Text(item.kind == PaymentKind.pay ? 'Pay now' : 'Confirm',
                      style: SovaText.caption.copyWith(color: SovaColors.electric, fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
