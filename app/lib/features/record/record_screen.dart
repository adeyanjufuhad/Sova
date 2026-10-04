import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/insights.dart';
import '../../data/providers.dart';
import '../../shared/widgets/adire_painter.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/polish.dart';
import '../home/home_screen.dart' show comingNext;

/// The member's own savings record: the thing that earns trust (and, later,
/// better payout positions and credit), shown like a banking insights page.
class RecordScreen extends ConsumerWidget {
  const RecordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circles = ref.watch(circlesProvider);
    return Scaffold(
      body: SafeArea(
        child: circles.when(
          loading: () => const SkeletonList(),
          error: (e, _) => ErrorView(message: e.toString(), onRetry: () => ref.invalidate(circlesProvider)),
          data: (list) {
            final s = recordStats(list, ref.watch(meProvider));
            final pct = (s.onTimeRate * 100).round();
            return ListView(
              padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.lg, SovaSpacing.screenH, SovaSpacing.xl3),
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('My record', style: SovaText.h1)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.md, vertical: SovaSpacing.sm),
                      decoration: BoxDecoration(
                        border: Border.all(color: SovaColors.border),
                        borderRadius: BorderRadius.circular(SovaRadius.full),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 14, color: SovaColors.textSecondary),
                          const SizedBox(width: SovaSpacing.xs),
                          Text('Last 6 months', style: SovaText.caption.copyWith(color: SovaColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: SovaSpacing.xl),
                StaggeredIn(
                  index: 0,
                  child: AdirePanel(
                    radius: SovaRadius.xl2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('On-time payments', onBlue: true),
                        const SizedBox(height: SovaSpacing.md),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.end,
                          spacing: SovaSpacing.md,
                          children: [
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: pct.toDouble()),
                              duration: const Duration(milliseconds: 900),
                              curve: Curves.easeOutCubic,
                              builder: (_, v, _) => Text(
                                '${v.round()}%',
                                style: SovaText.moneyLarge.copyWith(color: SovaColors.white, fontSize: 44),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: SovaSpacing.sm),
                              child: Text(
                                '${s.onTimePayments} of ${s.confirmedPayments} payments',
                                style: SovaText.bodySmall.copyWith(color: SovaColors.white.withValues(alpha: 0.8)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: SovaSpacing.lg),
                        Row(
                          children: [
                            _Stat(label: 'Contributed', child: Money(s.totalContributed, style: _statStyle)),
                            _Stat(label: 'Active circles', child: Text('${s.circlesActive}', style: _statStyle)),
                            _Stat(label: 'Turns collected', child: Text('${s.turnsCollected}', style: _statStyle)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: SovaSpacing.xl),
                StaggeredIn(index: 1, child: _MonthlyChart(stats: s)),
                const SizedBox(height: SovaSpacing.xl2),
                const SectionHeader('By circle'),
                const SizedBox(height: SovaSpacing.sm),
                for (final (i, share) in s.byCircle.indexed)
                  StaggeredIn(
                    index: i + 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: SovaSpacing.sm),
                      child: Row(
                        children: [
                          const IconTile(Icons.groups_rounded),
                          const SizedBox(width: SovaSpacing.md),
                          Expanded(child: Text(share.circle.name, style: SovaText.label, overflow: TextOverflow.ellipsis)),
                          SizedBox(
                            width: 48,
                            child: Text('${(share.share * 100).round()}%', style: SovaText.caption, textAlign: TextAlign.right),
                          ),
                          const SizedBox(width: SovaSpacing.lg),
                          Money(share.amount, style: SovaText.moneySmall),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: SovaSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(SovaSpacing.lg),
                  decoration: BoxDecoration(color: SovaColors.mist, borderRadius: BorderRadius.circular(SovaRadius.xl)),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline_rounded, color: SovaColors.electric),
                      const SizedBox(width: SovaSpacing.md),
                      Expanded(
                        child: Text(
                          pct == 100
                              ? 'Every payment on time. Your record is yours: share it with a lender or landlord only when you choose.'
                              : 'Paying before the due date lifts your record and moves you up the payout order.',
                          style: SovaText.bodySmall.copyWith(color: SovaColors.navy900),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SovaSpacing.xl3),
                const SectionHeader('Settings'),
                const SizedBox(height: SovaSpacing.sm),
                const _Settings(),
              ],
            );
          },
        ),
      ),
    );
  }
}

const _statStyle = TextStyle(
  fontFamily: SovaText.family,
  fontSize: 16,
  fontWeight: FontWeight.w700,
  color: SovaColors.white,
  fontFeatures: [FontFeature.tabularFigures()],
);

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          const SizedBox(height: 2),
          Text(label, style: SovaText.caption.copyWith(color: SovaColors.white.withValues(alpha: 0.75))),
        ],
      ),
    );
  }
}

/// Flat bar chart of what the member paid each month; the latest month is solid blue.
class _MonthlyChart extends ConsumerWidget {
  const _MonthlyChart({required this.stats});

  final RecordStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final months = stats.monthly;
    final peak = months.fold<int>(0, (m, e) => e.amount > m ? e.amount : m);
    final total = months.fold<int>(0, (t, e) => t + e.amount);
    // Highlight the most recent month that actually had payments.
    final highlight = months.lastIndexWhere((m) => m.amount > 0);
    final month = DateFormat('MMM');
    const chartHeight = 120.0;

    return Container(
      padding: const EdgeInsets.all(SovaSpacing.lg),
      decoration: BoxDecoration(
        color: SovaColors.white,
        borderRadius: BorderRadius.circular(SovaRadius.xl),
        border: Border.all(color: SovaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Paid each month', style: SovaText.caption),
          const SizedBox(height: SovaSpacing.xs),
          Money(total, style: SovaText.moneyMedium),
          const Text('in the last 6 months', style: SovaText.caption),
          const SizedBox(height: SovaSpacing.lg),
          SizedBox(
            // Room under the bars for month labels, even with enlarged text.
            height: chartHeight + 36,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, m) in months.indexed)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: peak == 0 ? 0 : m.amount / peak),
                          duration: Duration(milliseconds: 600 + i * 80),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, _) => Container(
                            width: 22,
                            height: 6 + v * (chartHeight - 6),
                            decoration: BoxDecoration(
                              color: i == highlight ? SovaColors.electric : SovaColors.electricTint,
                              borderRadius: BorderRadius.circular(SovaRadius.sm),
                            ),
                          ),
                        ),
                        const SizedBox(height: SovaSpacing.sm),
                        Text(month.format(m.month), style: SovaText.caption.copyWith(fontSize: 11)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Settings extends ConsumerWidget {
  const _Settings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hideAmountsProvider);
    final session = ref.watch(authProvider).session;

    Widget row(IconData icon, String title, {String? subtitle, Widget? trailing, VoidCallback? onTap}) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: SovaSpacing.lg),
          leading: Icon(icon, color: SovaColors.navy900),
          title: Text(title, style: SovaText.label),
          subtitle: subtitle == null ? null : Text(subtitle, style: SovaText.caption),
          trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: SovaColors.textMuted),
          onTap: onTap,
        );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SovaRadius.xl),
        border: Border.all(color: SovaColors.border),
      ),
      child: Column(
        children: [
          row(
            Icons.person_outline_rounded,
            session?.fullName ?? 'Profile',
            subtitle: session == null ? null : displayPhone(session.phone),
            onTap: () => comingNext(context, 'Editing your profile'),
          ),
          const Divider(),
          row(
            hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            'Hide amounts',
            subtitle: 'Useful when others can see your screen',
            trailing: Switch(
              value: hidden,
              activeTrackColor: SovaColors.electric,
              onChanged: (_) => ref.read(hideAmountsProvider.notifier).toggle(),
            ),
            onTap: () => ref.read(hideAmountsProvider.notifier).toggle(),
          ),
          const Divider(),
          row(Icons.account_balance_outlined, 'Bank details', subtitle: 'Where members send your payout',
              onTap: () => comingNext(context, 'Editing bank details')),
          const Divider(),
          row(Icons.lock_outline_rounded, 'Change PIN', onTap: () => comingNext(context, 'Changing your PIN')),
          const Divider(),
          row(Icons.logout_rounded, 'Sign out', trailing: const SizedBox.shrink(),
              onTap: () => ref.read(authProvider.notifier).signOut()),
        ],
      ),
    );
  }
}
