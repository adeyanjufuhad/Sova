import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/adire_painter.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/pin_pad.dart';
import '../../shared/widgets/polish.dart';

/// Someone offered the signed-in person their place in a circle. Accepting
/// means agreeing to the rules; the admin approves afterwards.
class HandoverOfferScreen extends ConsumerStatefulWidget {
  const HandoverOfferScreen({super.key, required this.offerId});

  final String offerId;

  @override
  ConsumerState<HandoverOfferScreen> createState() => _HandoverOfferScreenState();
}

class _HandoverOfferScreenState extends ConsumerState<HandoverOfferScreen> {
  bool _agreed = false;
  String? _error;

  Future<void> _accept(HandoverOffer o) async {
    if (!_agreed) {
      setState(() => _error = 'Tick the box to accept the circle\'s rules.');
      return;
    }
    final repo = ref.read(repositoryProvider);
    final ok = await confirmWithPin(
      context,
      title: 'Take ${o.leavingName.split(' ').first}\'s place',
      subtitle: 'You agree to pay ${naira(o.contributionAmount)} every ${o.cycle.unit}. The admin approves next.',
      onPin: (pin) => repo.answerHandover(handoverId: o.id, accept: true, rulesVersion: o.rules.version, pin: pin),
    );
    if (!ok || !mounted) return;
    HapticFeedback.mediumImpact();
    ref.invalidate(handoverOffersProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Accepted. You join the circle once the admin approves and the current turn ends.')),
    );
    context.go('/home');
  }

  Future<void> _decline(HandoverOffer o) async {
    try {
      await ref.read(repositoryProvider).answerHandover(handoverId: o.id, accept: false);
      ref.invalidate(handoverOffersProvider);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(handoverOffersProvider);
    return Scaffold(
      appBar: AppBar(leading: const SovaBackButton(fallback: '/home'), title: const Text('A place offered to you')),
      body: async.when(
        loading: () => const SkeletonList(),
        error: (e, _) => ErrorView(message: e.toString(), onRetry: () => ref.invalidate(handoverOffersProvider)),
        data: (offers) {
          final o = offers.where((x) => x.id == widget.offerId).firstOrNull;
          if (o == null) {
            return const Padding(
              padding: EdgeInsets.all(SovaSpacing.screenH),
              child: EmptyState(
                icon: Icons.link_off_rounded,
                title: 'This offer is no longer open',
                message: 'It may have been answered or cancelled.',
              ),
            );
          }
          final onBlue = SovaText.bodySmall.copyWith(color: SovaColors.white.withValues(alpha: 0.85));
          final r = o.rules;
          return ListView(
            padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.lg, SovaSpacing.screenH, SovaSpacing.xl4),
            children: [
              AdirePanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow(o.circleName, onBlue: true),
                    const SizedBox(height: SovaSpacing.md),
                    Text(
                      '${o.leavingName.split(' ').first} offers you their place',
                      style: SovaText.h2.copyWith(color: SovaColors.white),
                    ),
                    const SizedBox(height: SovaSpacing.xs),
                    Text(
                      o.turn == null
                          ? 'Turns are drawn when the circle is full.'
                          : 'You would collect ${naira(o.payoutAmount)} on turn ${o.turn}.',
                      style: onBlue,
                    ),
                    if (o.reason != null) ...[
                      const SizedBox(height: SovaSpacing.sm),
                      Text('“${o.reason}”', style: onBlue),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: SovaSpacing.xl),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(SovaSpacing.lg),
                  child: Column(
                    children: [
                      InfoRow('You pay', '${naira(o.contributionAmount)} ${o.cycle.label.toLowerCase()}'),
                      InfoRow('Members', '${o.memberCount}'),
                      InfoRow('Payout on your turn', naira(o.payoutAmount)),
                      InfoRow('Late fee', r.lateFee == 0 ? 'None' : naira(r.lateFee)),
                      InfoRow('Grace period', '${r.graceDays} day${r.graceDays == 1 ? '' : 's'}'),
                      InfoRow('Leaving early', r.earlyExit.label),
                    ],
                  ),
                ),
              ),
              if (o.paidIn > 0) ...[
                const SizedBox(height: SovaSpacing.md),
                NoticeBox(
                  '${o.leavingName.split(' ').first} has paid ${naira(o.paidIn)} into earlier turns. Agree between you how '
                  'that is settled; Sova only records the handover and never moves money.',
                  icon: Icons.handshake_outlined,
                ),
              ],
              const SizedBox(height: SovaSpacing.lg),
              CheckboxListTile(
                value: _agreed,
                onChanged: (v) => setState(() {
                  _agreed = v ?? false;
                  _error = null;
                }),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('I accept rules version ${r.version} of this circle', style: SovaText.label),
              ),
              if (_error != null) ...[
                const SizedBox(height: SovaSpacing.sm),
                NoticeBox(_error!),
              ],
              const SizedBox(height: SovaSpacing.lg),
              FilledButton(onPressed: () => _accept(o), child: const Text('Accept the place')),
              const SizedBox(height: SovaSpacing.sm),
              OutlinedButton(onPressed: () => _decline(o), child: const Text('Decline')),
            ],
          );
        },
      ),
    );
  }
}

/// On the home screen: places offered to the signed-in person.
class HandoverOffersCard extends ConsumerWidget {
  const HandoverOffersCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers = ref.watch(handoverOffersProvider).value ?? const [];
    if (offers.isEmpty) return const SizedBox.shrink();
    final o = offers.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: SovaSpacing.lg),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SovaRadius.lg),
          side: const BorderSide(color: SovaColors.electric),
        ),
        child: InkWell(
          onTap: () => context.push('/handover/${o.id}'),
          child: Padding(
            padding: const EdgeInsets.all(SovaSpacing.lg),
            child: Row(
              children: [
                const IconTile(Icons.person_add_alt_1_outlined, size: 40),
                const SizedBox(width: SovaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${o.leavingName.split(' ').first} offered you a place', style: SovaText.label),
                      Text(
                        offers.length == 1 ? 'In ${o.circleName}. See the rules and decide.' : '${offers.length} offers waiting.',
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
      ),
    );
  }
}
