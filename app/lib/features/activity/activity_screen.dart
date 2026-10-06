import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/insights.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/app_shell.dart' show tabBarInset;
import '../../shared/widgets/common.dart';
import '../../shared/widgets/polish.dart';

enum _Filter { all, paid, received }

/// Every payment the member made or received, newest first, grouped by day.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  _Filter _filter = _Filter.all;

  String _dayLabel(DateTime d) {
    final rel = relativeDay(d);
    if (rel == 'today' || rel == 'yesterday') return rel[0].toUpperCase() + rel.substring(1);
    return shortDate(d);
  }

  @override
  Widget build(BuildContext context) {
    final circles = ref.watch(circlesProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false, // lists run behind the glass tab bar
        child: circles.when(
          loading: () => const SkeletonList(),
          error: (e, _) => ErrorView(message: e.toString(), onRetry: () => ref.invalidate(circlesProvider)),
          data: (list) {
            final all = activity(list, ref.watch(meProvider));
            final items = switch (_filter) {
              _Filter.all => all,
              _Filter.paid => all.where((a) => !a.incoming).toList(),
              _Filter.received => all.where((a) => a.incoming).toList(),
            };

            // Group by calendar day.
            final groups = <String, List<ActivityItem>>{};
            for (final a in items) {
              groups.putIfAbsent(_dayLabel(a.date), () => []).add(a);
            }

            return RefreshIndicator(
              color: SovaColors.electric,
              onRefresh: () => ref.refresh(circlesProvider.future),
              child: ListView(
                padding: EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.lg, SovaSpacing.screenH, SovaSpacing.xl3 + tabBarInset(context)),
                children: [
                  const Text('Activity', style: SovaText.h1),
                  const SizedBox(height: SovaSpacing.xs),
                  const Text('Every payment you made or received, with its receipt.', style: SovaText.bodySmall),
                  const SizedBox(height: SovaSpacing.xl),
                  SegmentedChips<_Filter>(
                    options: const {_Filter.all: 'All', _Filter.paid: 'Paid', _Filter.received: 'Received'},
                    selected: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                  const SizedBox(height: SovaSpacing.lg),
                  if (items.isEmpty)
                    const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No payments yet',
                      message: 'Payments you make and receive appear here, each with its receipt.',
                    ),
                  for (final (gi, entry) in groups.entries.indexed) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: SovaSpacing.md, bottom: SovaSpacing.xs),
                      child: Text(entry.key, style: SovaText.eyebrow.copyWith(color: SovaColors.textMuted)),
                    ),
                    for (final (i, a) in entry.value.indexed) StaggeredIn(index: gi + i, child: _ActivityRow(a)),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow(this.item);

  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    final a = item;
    final who = a.counterparty;
    final confirmed = a.contribution.status == ContributionStatus.fullyConfirmed;
    final title = a.incoming ? '${who?.firstName ?? 'Member'} paid you' : 'Paid ${who?.firstName ?? 'collector'}';

    return Pressable(
      onTap: () => a.incoming ? context.push('/circle/${a.circle.id}') : context.push('/circle/${a.circle.id}/receipt/${a.round.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SovaSpacing.md),
        child: Row(
          children: [
            if (who != null)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  MemberAvatar(who, size: 44, highlight: a.incoming),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: SovaColors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: SovaColors.border),
                      ),
                      child: Icon(
                        a.incoming ? Icons.south_west_rounded : Icons.north_east_rounded,
                        size: 12,
                        color: SovaColors.electric,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(width: SovaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SovaText.label),
                  const SizedBox(height: 2),
                  Text('${a.circle.name} · turn ${a.round.number}', style: SovaText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Money(
                  a.contribution.amount,
                  prefix: a.incoming ? '+' : '−',
                  style: SovaText.moneySmall.copyWith(color: a.incoming ? SovaColors.electric : SovaColors.navy900),
                ),
                const SizedBox(height: 2),
                Text(
                  confirmed ? 'Confirmed' : 'Awaiting',
                  style: SovaText.caption.copyWith(
                    color: confirmed ? SovaColors.textMuted : SovaColors.electric,
                    fontWeight: confirmed ? FontWeight.w500 : FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
