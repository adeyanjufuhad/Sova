import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/demo_repository.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';

/// Bank-statement style receipt for the signed-in member's payment in a round.
class ReceiptScreen extends ConsumerWidget {
  const ReceiptScreen({super.key, required this.circleId, required this.roundId});

  final String circleId;
  final String roundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(circleProvider(circleId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
        leading: CloseButton(onPressed: () => context.go('/circle/$circleId')),
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (c) {
          const me = DemoRepository.me;
          final x = c.contributionFor(roundId, me);
          final round = c.rounds.where((r) => r.id == roundId).firstOrNull;
          if (x == null || round == null) return const ErrorView(message: 'We could not find this payment.');
          final payer = c.memberById(me);
          final collector = c.memberById(round.collectorId);

          return ListView(
            padding: const EdgeInsets.all(SovaSpacing.screenH),
            children: [
              const SizedBox(height: SovaSpacing.lg),
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(color: SovaColors.electric, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, color: SovaColors.white, size: 34),
                ),
              ),
              const SizedBox(height: SovaSpacing.lg),
              Text('Payment recorded', style: SovaText.h1, textAlign: TextAlign.center),
              const SizedBox(height: SovaSpacing.xs),
              Text(
                x.status == ContributionStatus.fullyConfirmed
                    ? 'Confirmed by you and ${collector?.firstName ?? 'the collector'}.'
                    : 'Waiting for ${collector?.firstName ?? 'the collector'} to confirm it arrived.',
                style: SovaText.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SovaSpacing.xl2),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(SovaSpacing.lg, SovaSpacing.lg, SovaSpacing.lg, SovaSpacing.md),
                      child: Row(
                        children: [
                          const SovaLogo(size: 22),
                          const Spacer(),
                          Text(x.reference ?? '', style: SovaText.caption.copyWith(letterSpacing: 1)),
                        ],
                      ),
                    ),
                    const _Perforation(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.lg, vertical: SovaSpacing.md),
                      child: Column(
                        children: [
                          InfoRow('Amount', nairaExact(x.amount), valueStyle: SovaText.moneySmall),
                          InfoRow('From', payer?.name ?? 'You'),
                          InfoRow('To', collector?.name ?? 'Collector'),
                          InfoRow('Circle', c.name),
                          InfoRow('Turn', '${round.number} of ${c.memberCount}'),
                          if (x.bankReference != null) InfoRow('Bank reference', x.bankReference!),
                          InfoRow('Receipt photo', x.hasProof ? 'Attached' : 'Not attached'),
                          if (x.payerConfirmedAt != null)
                            InfoRow('Recorded', '${shortDate(x.payerConfirmedAt!)}, ${clockTime(x.payerConfirmedAt!)}'),
                        ],
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      color: x.status == ContributionStatus.fullyConfirmed ? SovaColors.electric : SovaColors.mist,
                      padding: const EdgeInsets.all(SovaSpacing.md),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [StatusPill(x.status)],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SovaSpacing.xl2),
              FilledButton(onPressed: () => context.go('/circle/$circleId'), child: const Text('Done')),
            ],
          );
        },
      ),
    );
  }
}

/// Dashed tear line, like a printed receipt.
class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / 10).floor();
        return Row(
          children: [
            for (var i = 0; i < count; i++)
              Expanded(
                child: Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  color: SovaColors.borderStrong,
                ),
              ),
          ],
        );
      },
    );
  }
}
