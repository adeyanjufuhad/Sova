import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/pin_pad.dart';

/// Sova never moves money: the member pays from their own bank app, then
/// records it here with a reference and (optionally) a receipt photo.
class PayScreen extends ConsumerWidget {
  const PayScreen({super.key, required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(circleProvider(circleId));
    return Scaffold(
      appBar: AppBar(title: const Text('Record a payment')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (c) {
          final round = c.activeRound;
          final collector = c.currentCollector;
          if (round == null || collector == null) {
            return const ErrorView(message: 'There is no turn in progress for this circle.');
          }
          return _PayForm(circle: c, round: round, collector: collector);
        },
      ),
    );
  }
}

class _PayForm extends ConsumerStatefulWidget {
  const _PayForm({required this.circle, required this.round, required this.collector});

  final Circle circle;
  final Round round;
  final Member collector;

  @override
  ConsumerState<_PayForm> createState() => _PayFormState();
}

class _PayFormState extends ConsumerState<_PayForm> {
  final _reference = TextEditingController();
  bool _hasProof = false;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final c = widget.circle;
    final repo = ref.read(repositoryProvider);
    final ok = await confirmWithPin(
      context,
      title: 'Record ${naira(c.contributionAmount)} to ${widget.collector.firstName}',
      subtitle: 'Only do this after the money has left your account.',
      onPin: (pin) async {
        await repo.verifyPin(pin);
        await repo.confirmMyPayment(
          circleId: c.id,
          roundId: widget.round.id,
          bankReference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
          hasProof: _hasProof,
        );
      },
    );
    if (!mounted || !ok) return;
    refreshCircle(ref, c.id);
    context.pushReplacement('/circle/${c.id}/receipt/${widget.round.id}');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.circle;
    final bank = widget.collector.bank;

    return ListView(
      padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.xl, SovaSpacing.screenH, SovaSpacing.xl4),
      children: [
        Text('Pay ${widget.collector.name}', style: SovaText.bodySmall),
        const SizedBox(height: SovaSpacing.xs),
        Text(naira(c.contributionAmount), style: SovaText.moneyLarge),
        Text('${c.name} · turn ${widget.round.number} · due ${relativeDay(widget.round.dueDate)}', style: SovaText.caption),
        const SizedBox(height: SovaSpacing.xl2),
        const _Step(number: 1, title: 'Send the money from your bank app'),
        const SizedBox(height: SovaSpacing.md),
        if (bank != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.lg, vertical: SovaSpacing.sm),
              child: Column(
                children: [
                  InfoRow('Bank', bank.bankName),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(child: InfoRow('Account number', bank.accountNumber, valueStyle: SovaText.moneySmall)),
                      IconButton(
                        tooltip: 'Copy account number',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: bank.accountNumber));
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Account number copied.')));
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18, color: SovaColors.electric),
                      ),
                    ],
                  ),
                  const Divider(),
                  InfoRow('Account name', bank.accountName),
                ],
              ),
            ),
          )
        else
          NoticeBox(
            '${widget.collector.firstName} has not added bank details yet. Ask them directly, or pay cash in person.',
          ),
        const SizedBox(height: SovaSpacing.xl2),
        const _Step(number: 2, title: 'Add the transfer reference (optional)'),
        const SizedBox(height: SovaSpacing.md),
        TextField(
          controller: _reference,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'e.g. FT2610ABC123', labelText: 'Bank reference'),
        ),
        const SizedBox(height: SovaSpacing.xl2),
        const _Step(number: 3, title: 'Attach your receipt (recommended)'),
        const SizedBox(height: SovaSpacing.md),
        // TODO: pick a real photo with image_picker once uploads are wired to the server.
        OutlinedButton.icon(
          onPressed: () => setState(() => _hasProof = !_hasProof),
          icon: Icon(_hasProof ? Icons.check_circle_rounded : Icons.photo_camera_outlined,
              color: _hasProof ? SovaColors.electric : null),
          label: Text(_hasProof ? 'Receipt photo attached' : 'Add a photo of your receipt'),
        ),
        const SizedBox(height: SovaSpacing.xl2),
        NoticeBox(
          'Only continue after the money has left your account. ${widget.collector.firstName} will confirm when it arrives, '
          'and you will both get a receipt.',
          icon: Icons.shield_outlined,
        ),
        const SizedBox(height: SovaSpacing.xl),
        FilledButton(onPressed: _submit, child: const Text('I have paid')),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: SovaColors.electric, shape: BoxShape.circle),
          child: Text('$number', style: SovaText.caption.copyWith(color: SovaColors.white, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: SovaSpacing.md),
        Expanded(child: Text(title, style: SovaText.h3)),
      ],
    );
  }
}
