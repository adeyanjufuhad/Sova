import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/demo_repository.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';

/// The rules every member signs. Accepting is recorded with a timestamp, so
/// disagreements later are settled by what was agreed.
class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key, required this.circleId});

  final String circleId;

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).acceptRules(widget.circleId);
      refreshCircle(ref, widget.circleId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You accepted the group rules.')));
      context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(circleProvider(widget.circleId));
    return Scaffold(
      appBar: AppBar(title: const Text('Group rules')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (c) {
          final rules = c.rules;
          if (rules == null) return const ErrorView(message: 'This circle has no written rules yet.');
          final accepted = rules.acceptedBy.contains(DemoRepository.me);
          final pending = c.members.where((m) => !rules.acceptedBy.contains(m.userId)).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.xl, SovaSpacing.screenH, SovaSpacing.xl4),
            children: [
              Eyebrow('${c.name} · version ${rules.version}'),
              const SizedBox(height: SovaSpacing.md),
              const Text('What everyone agreed', style: SovaText.h1),
              const SizedBox(height: SovaSpacing.xl2),
              Card(
                child: Column(
                  children: [
                    _Rule(
                      icon: Icons.payments_outlined,
                      title: 'Contribution',
                      body: '${naira(c.contributionAmount)} every ${c.cycle.unit}, paid to whoever is collecting that turn.',
                    ),
                    const Divider(),
                    _Rule(
                      icon: Icons.timer_outlined,
                      title: 'Late payment',
                      body: rules.lateFee == 0
                          ? 'No fine. ${rules.graceDays} day(s) grace.'
                          : '${naira(rules.lateFee)} fine after ${rules.graceDays} day(s) grace.',
                    ),
                    const Divider(),
                    _Rule(icon: Icons.logout_rounded, title: rules.earlyExit.label, body: rules.earlyExit.description),
                    if (rules.emergencyPolicy != null) ...[
                      const Divider(),
                      _Rule(icon: Icons.medical_services_outlined, title: 'Emergencies', body: rules.emergencyPolicy!),
                    ],
                    const Divider(),
                    const _Rule(
                      icon: Icons.gavel_rounded,
                      title: 'Disputes',
                      body: 'Settled by the record: receipts, references and confirmations in Sova. The admin decides.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SovaSpacing.xl2),
              Text(
                '${rules.acceptedBy.length} of ${c.members.length} members accepted',
                style: SovaText.label,
              ),
              if (pending.isNotEmpty) ...[
                const SizedBox(height: SovaSpacing.xs),
                Text('Still to accept: ${pending.map((m) => m.userId == DemoRepository.me ? 'you' : m.firstName).join(', ')}',
                    style: SovaText.caption),
              ],
              const SizedBox(height: SovaSpacing.xl2),
              if (accepted)
                const NoticeBox('You accepted these rules.', icon: Icons.done_all_rounded)
              else ...[
                const NoticeBox(
                  'By accepting, you agree to follow these rules for this circle. Sova records the date you accepted.',
                  icon: Icons.draw_outlined,
                ),
                const SizedBox(height: SovaSpacing.lg),
                FilledButton(
                  onPressed: _busy ? null : _accept,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: SovaColors.white))
                      : const Text('I accept these rules'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(SovaSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: SovaColors.electric, size: 22),
          const SizedBox(width: SovaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SovaText.label),
                const SizedBox(height: SovaSpacing.xs),
                Text(body, style: SovaText.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
