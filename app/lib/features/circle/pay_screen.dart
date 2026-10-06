import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/polish.dart';
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
        loading: () => const SkeletonList(),
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

  /// The receipt photo: shown as a thumbnail, uploaded as soon as it's picked.
  Uint8List? _photo;
  String? _proofKey;
  bool _uploading = false;
  String? _photoError;

  Future<void> _pickPhoto(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 75);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final type = file.mimeType ?? (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
    setState(() {
      _photo = bytes;
      _proofKey = null;
      _uploading = true;
      _photoError = null;
    });
    try {
      final key = await ref.read(repositoryProvider).uploadProof(
            circleId: widget.circle.id,
            roundNumber: widget.round.number,
            bytes: bytes,
            contentType: type,
          );
      if (mounted) setState(() => _proofKey = key);
    } catch (e) {
      if (mounted) setState(() => _photoError = e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _removePhoto() => setState(() {
        _photo = null;
        _proofKey = null;
        _photoError = null;
      });

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_uploading) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wait for the photo to finish uploading.')));
      return;
    }
    final c = widget.circle;
    final repo = ref.read(repositoryProvider);
    final ok = await confirmWithPin(
      context,
      title: 'Record ${naira(c.contributionAmount)} to ${widget.collector.firstName}',
      subtitle: 'Only do this after the money has left your account.',
      onPin: (pin) => repo.confirmMyPayment(
        circleId: c.id,
        roundNumber: widget.round.number,
        bankReference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        proofKey: _proofKey,
        pin: pin,
      ),
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
        if (_photo == null)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Take photo'),
                ),
              ),
              const SizedBox(width: SovaSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Choose'),
                ),
              ),
            ],
          )
        else
          _PhotoPreview(
            bytes: _photo!,
            uploading: _uploading,
            uploaded: _proofKey != null,
            error: _photoError,
            onRemove: _removePhoto,
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

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({
    required this.bytes,
    required this.uploading,
    required this.uploaded,
    required this.error,
    required this.onRemove,
  });

  final Uint8List bytes;
  final bool uploading;
  final bool uploaded;
  final String? error;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final status = uploading
        ? 'Uploading…'
        : uploaded
            ? 'Receipt photo attached. Only your circle can see it.'
            : (error ?? 'Not uploaded');
    return Container(
      padding: const EdgeInsets.all(SovaSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: uploaded ? SovaColors.electric : SovaColors.border),
        borderRadius: BorderRadius.circular(SovaRadius.lg),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(SovaRadius.md),
            child: Image.memory(bytes, width: 64, height: 64, fit: BoxFit.cover),
          ),
          const SizedBox(width: SovaSpacing.md),
          Expanded(
            child: Row(
              children: [
                if (uploading)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: SovaColors.electric),
                  )
                else
                  Icon(uploaded ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      size: 18, color: uploaded ? SovaColors.electric : SovaColors.navy900),
                const SizedBox(width: SovaSpacing.sm),
                Expanded(child: Text(status, style: SovaText.bodySmall)),
              ],
            ),
          ),
          IconButton(tooltip: 'Remove photo', onPressed: uploading ? null : onRemove, icon: const Icon(Icons.close_rounded)),
        ],
      ),
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
