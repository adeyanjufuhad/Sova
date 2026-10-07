import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/polish.dart';

/// Reminders worked out from what's due right now, then everything that
/// happened in the member's circles. Opening the list marks it as read.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _marked = false;
  late final ProviderContainer _container = ProviderScope.containerOf(context, listen: false);

  /// Marks everything read once the list has been seen; the unread dots stay
  /// on this visit so the member can tell what's new.
  void _markRead() {
    if (_marked) return;
    _marked = true;
    _container; // captured now, while the screen is mounted
    ref.read(repositoryProvider).markNotificationsRead().catchError((_) {});
  }

  @override
  void dispose() {
    // The bell should drop its count once the list has been seen.
    if (_marked) Future.microtask(() => _container.invalidate(inboxProvider));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(inboxProvider);
    return Scaffold(
      appBar: AppBar(leading: const SovaBackButton(fallback: '/home'), title: const Text('Notifications')),
      body: async.when(
        loading: () => const SkeletonList(),
        error: (e, _) => ErrorView(message: e.toString(), onRetry: () => ref.invalidate(inboxProvider)),
        data: (inbox) {
          _markRead();
          return RefreshIndicator(
            color: SovaColors.electric,
            onRefresh: () => ref.refresh(inboxProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.lg, SovaSpacing.screenH, SovaSpacing.xl4),
              children: [
                if (inbox.reminders.isNotEmpty) ...[
                  const Eyebrow('Needs you now'),
                  const SizedBox(height: SovaSpacing.md),
                  for (final r in inbox.reminders) _ReminderCard(r),
                  const SizedBox(height: SovaSpacing.lg),
                ],
                if (inbox.items.isEmpty && inbox.reminders.isEmpty)
                  const EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'Nothing new',
                    message: 'Payments, turns, votes and swap requests in your circles will appear here.',
                  ),
                if (inbox.items.isNotEmpty) ...[
                  const Eyebrow('Recent'),
                  const SizedBox(height: SovaSpacing.sm),
                  Card(
                    child: Column(
                      children: [
                        for (final (i, n) in inbox.items.indexed) ...[
                          if (i > 0) const Divider(indent: SovaSpacing.lg, endIndent: SovaSpacing.lg),
                          _NotificationRow(n),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: SovaSpacing.lg),
                const Text(
                  'Reminders are in the app for now. SMS and WhatsApp reminders are on the roadmap.',
                  style: SovaText.caption,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

IconData _iconFor(String type) => switch (type) {
      'payment_marked' || 'confirm' => Icons.call_received_rounded,
      'payment_confirmed' => Icons.done_all_rounded,
      'turn_opened' => Icons.event_available_outlined,
      'dispute' || 'dispute_vote' || 'dispute_resolved' || 'payout_shortfall' => Icons.gavel_rounded,
      'swap_request' || 'swap_answered' => Icons.swap_horiz_rounded,
      'handover_request' || 'handover_update' => Icons.person_add_alt_1_outlined,
      'due' || 'overdue' => Icons.north_east_rounded,
      _ => Icons.notifications_none_rounded,
    };

class _ReminderCard extends StatelessWidget {
  const _ReminderCard(this.reminder);

  final Reminder reminder;

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final late = r.kind == 'overdue';
    return Padding(
      padding: const EdgeInsets.only(bottom: SovaSpacing.sm),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SovaRadius.lg),
          side: BorderSide(color: late ? SovaColors.navy900 : SovaColors.electric),
        ),
        child: InkWell(
          onTap: () => context.push(r.link),
          child: Padding(
            padding: const EdgeInsets.all(SovaSpacing.lg),
            child: Row(
              children: [
                IconTile(_iconFor(r.kind), size: 40, filled: true),
                const SizedBox(width: SovaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.title, style: SovaText.label),
                      Text(r.message, style: SovaText.caption),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: SovaColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow(this.n);

  final AppNotification n;

  @override
  Widget build(BuildContext context) {
    final age = DateTime.now().difference(n.createdAt);
    final when = age.inMinutes < 1
        ? 'Just now'
        : age.inHours < 1
            ? '${age.inMinutes} min ago'
            : age.inHours < 24
                ? '${age.inHours} h ago'
                : shortDate(n.createdAt);
    return InkWell(
      onTap: n.link == null ? null : () => context.push(n.link!),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.lg, vertical: SovaSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(_iconFor(n.type), size: 36),
            const SizedBox(width: SovaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.title, style: SovaText.label.copyWith(fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(n.message, style: SovaText.caption),
                  const SizedBox(height: 2),
                  Text(when, style: SovaText.caption.copyWith(color: SovaColors.textMuted)),
                ],
              ),
            ),
            if (!n.read)
              Semantics(
                label: 'New',
                child: Container(
                  margin: const EdgeInsets.only(top: 6, left: SovaSpacing.sm),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: SovaColors.electric, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
