import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/polish.dart';
import '../../shared/widgets/pin_pad.dart';

/// The collector says how much actually reached their account and closes the
/// turn. Less than expected opens a dispute; the circle moves on either way.
class PayoutScreen extends ConsumerWidget {
  const PayoutScreen({super.key, required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(circleProvider(circleId));
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm your payout')),
      body: async.when(
        loading: () => const SkeletonList(),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (c) {
          final round = c.activeRound;
          if (round == null || round.collectorId != me) {
            return const ErrorView(message: 'You are not collecting a turn in this circle right now.');
          }
          return _PayoutForm(circle: c, round: round);
        },
      ),
    );
  }
}

class _PayoutForm extends ConsumerStatefulWidget {
  const _PayoutForm({required this.circle, required this.round});

  final Circle circle;
  final Round round;

  @override
  ConsumerState<_PayoutForm> createState() => _PayoutFormState();
}

class _PayoutFormState extends ConsumerState<_PayoutForm> {
  late final _amount = TextEditingController(text: '${widget.circle.confirmedThisRound}');

  int get _value => int.tryParse(_amount.text) ?? 0;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final c = widget.circle;
    final repo = ref.read(repositoryProvider);
    PayoutResult? result;
    final ok = await confirmWithPin(
      context,
      title: 'Confirm ${naira(_value)} received',
      subtitle: 'This closes turn ${widget.round.number}. It can\'t be undone.',
      onPin: (pin) async {
        result = await repo.confirmPayout(circleId: c.id, roundNumber: widget.round.number, amount: _value, pin: pin);
      },
    );
    if (!mounted || !ok || result == null) return;
    HapticFeedback.mediumImpact();
    final r = result!;
    final next = r.nextRound == null ? 'That was the last turn: the circle is complete.' : 'Turn ${r.nextRound} has started.';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(r.shortfall == 0 ? 'Payout confirmed' : '${naira(r.shortfall)} short'),
        content: Text(
          r.shortfall == 0
              ? 'Everyone can see you received the full ${naira(c.payout)}. $next'
              : 'Sova opened a dispute so the group can see who hasn\'t paid. $next',
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
      ),
    );
    // Refresh only now: the refreshed circle has a new collector, which would
    // replace this form before it could navigate.
    if (!mounted) return;
    refreshCircle(ref, c.id);
    context.go('/circle/${c.id}');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.circle;
    final short = c.payout - _value;
    return ListView(
      padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.xl, SovaSpacing.screenH, SovaSpacing.xl4),
      children: [
        Text('${c.name} · turn ${widget.round.number}', style: SovaText.bodySmall),
        const SizedBox(height: SovaSpacing.xs),
        Text(naira(c.payout), style: SovaText.moneyLarge),
        Text('Expected: ${naira(c.contributionAmount)} from each of the other ${c.memberCount - 1} members',
            style: SovaText.caption),
        const SizedBox(height: SovaSpacing.xl2),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.lg, vertical: SovaSpacing.sm),
            child: Column(
              children: [
                InfoRow('Payments you confirmed', '${c.paidThisRound} of ${c.payersThisRound}'),
                InfoRow('Total confirmed', naira(c.confirmedThisRound), valueStyle: SovaText.moneySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: SovaSpacing.xl2),
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
          style: SovaText.h2,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Amount that reached your account', prefixText: '₦ '),
        ),
        const SizedBox(height: SovaSpacing.lg),
        NoticeBox(
          short > 0
              ? 'That is ${naira(short)} less than expected. Sova will open a dispute so the group can see who '
                  'hasn\'t paid. The next turn starts either way.'
              : 'Only confirm money that has actually reached your account. The next turn starts when you confirm.',
          icon: short > 0 ? Icons.gavel_rounded : Icons.shield_outlined,
        ),
        const SizedBox(height: SovaSpacing.xl),
        FilledButton(onPressed: _submit, child: Text('Confirm ${naira(_value)} received')),
      ],
    );
  }
}
