import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/adire_painter.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/pin_pad.dart';

/// The public page that shows a shared score card.
String scoreLink(String token) => '$siteUrl/score/?t=$token';

/// "Ada Obi" -> "Ada O.", as the shared card and the public record show people.
String shortName(String? fullName) {
  final parts = (fullName ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 'Member';
  return parts.length == 1 ? parts.first : '${parts.first} ${parts[1][0].toUpperCase()}.';
}

/// The Sova Score at the top of the Record tab: the score and what it's made
/// of, or progress towards a first score, and the way to share it.
class ScoreCard extends ConsumerWidget {
  const ScoreCard({super.key, required this.footer});

  /// Extra figures shown under the score (contributed, circles, turns).
  final Widget footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(scoreProvider);
    final onBlue = SovaText.bodySmall.copyWith(color: SovaColors.white.withValues(alpha: 0.8));
    return AdirePanel(
      color: SovaColors.navy900,
      radius: SovaRadius.xl2,
      child: async.when(
        loading: () => const SizedBox(height: 180, child: Center(child: CircularProgressIndicator(color: SovaColors.white))),
        error: (e, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('Sova Score', onBlue: true),
            const SizedBox(height: SovaSpacing.md),
            Text(e.toString(), style: onBlue),
            TextButton(
              onPressed: () => ref.invalidate(scoreProvider),
              child: const Text('Try again', style: TextStyle(color: SovaColors.white)),
            ),
          ],
        ),
        data: (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Eyebrow('Sova Score', onBlue: true)),
                if (s.band != null) _Chip(s.band!),
              ],
            ),
            const SizedBox(height: SovaSpacing.md),
            if (s.ready) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: s.score!.toDouble()),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => Text(
                      '${v.round()}',
                      style: SovaText.moneyLarge.copyWith(color: SovaColors.white, fontSize: 56, height: 1),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: SovaSpacing.xs, bottom: SovaSpacing.sm),
                    child: Text('/ 100', style: onBlue),
                  ),
                ],
              ),
              const SizedBox(height: SovaSpacing.xs),
              Text(
                'From ${s.confirmedPayments} confirmed payments in '
                '${s.activeCircles + s.completedCircles} circle${s.activeCircles + s.completedCircles == 1 ? '' : 's'}.',
                style: onBlue,
              ),
              const SizedBox(height: SovaSpacing.lg),
              _Part(label: 'Paid on time', weight: 60, value: s.onTimeRate),
              _Part(label: 'Paid every turn', weight: 25, value: s.consistencyRate),
              _Part(label: 'Circles finished', weight: 15, value: s.completionRate),
            ] else ...[
              Text(
                'Your score starts after ${s.minimumPayments} confirmed payments',
                style: SovaText.h2.copyWith(color: SovaColors.white),
              ),
              const SizedBox(height: SovaSpacing.xs),
              Text(
                '${s.confirmedPayments} of ${s.minimumPayments} so far. Pay on time and ask the collector to confirm.',
                style: onBlue,
              ),
              const SizedBox(height: SovaSpacing.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(SovaRadius.full),
                child: LinearProgressIndicator(
                  value: (s.confirmedPayments / s.minimumPayments).clamp(0.0, 1.0),
                  minHeight: 6,
                  color: SovaColors.white,
                  backgroundColor: SovaColors.white.withValues(alpha: 0.2),
                ),
              ),
            ],
            const SizedBox(height: SovaSpacing.lg),
            footer,
            if (s.ready) ...[
              const SizedBox(height: SovaSpacing.lg),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: SovaColors.white, foregroundColor: SovaColors.navy900),
                onPressed: () => showShareScoreSheet(context),
                icon: Icon(s.share == null ? Icons.ios_share_rounded : Icons.link_rounded),
                label: Text(s.share == null ? 'Share my score' : 'Sharing on · manage link'),
              ),
            ],
            const SizedBox(height: SovaSpacing.md),
            Text(
              'Your record, not a credit rating. Sova never lends.',
              style: SovaText.caption.copyWith(color: SovaColors.white.withValues(alpha: 0.65)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.md, vertical: SovaSpacing.xs),
        decoration: BoxDecoration(
          color: SovaColors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(SovaRadius.full),
          border: Border.all(color: SovaColors.white.withValues(alpha: 0.25)),
        ),
        child: Text(text, style: SovaText.caption.copyWith(color: SovaColors.white, fontWeight: FontWeight.w700)),
      );
}

/// One part of the score: what it measures, its weight and the member's rate.
class _Part extends StatelessWidget {
  const _Part({required this.label, required this.weight, required this.value});

  final String label;
  final int weight;
  final double value;

  @override
  Widget build(BuildContext context) {
    final muted = SovaText.caption.copyWith(color: SovaColors.white.withValues(alpha: 0.7));
    return Padding(
      padding: const EdgeInsets.only(bottom: SovaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: SovaText.label.copyWith(color: SovaColors.white))),
              Text('${(value * 100).round()}%', style: SovaText.label.copyWith(color: SovaColors.white)),
              const SizedBox(width: SovaSpacing.sm),
              SizedBox(width: 88, child: Text('$weight% of score', style: muted, textAlign: TextAlign.right, maxLines: 1)),
            ],
          ),
          const SizedBox(height: SovaSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(SovaRadius.full),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 6,
              color: SovaColors.sky,
              backgroundColor: SovaColors.white.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showShareScoreSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      // Above the tab bar, so the sheet's buttons are never hidden behind it.
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: SovaColors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(SovaRadius.xl2))),
      builder: (_) => const _ShareSheet(),
    );

/// Shows exactly what a shared card reveals, then creates, shows or stops the link.
class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet();

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  bool _busy = false;

  Future<void> _create() async {
    final repo = ref.read(repositoryProvider);
    final ok = await confirmWithPin(
      context,
      title: 'Share your Sova Score',
      subtitle: 'Anyone with the link will see the card above. You can stop sharing at any time.',
      onPin: (pin) => repo.shareScore(pin: pin),
    );
    if (ok) ref.invalidate(scoreProvider);
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).stopSharingScore();
      ref.invalidate(scoreProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stopped sharing. The link no longer works.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(scoreProvider);
    final name = shortName(ref.watch(authProvider).session?.fullName);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.xl2, SovaSpacing.screenH, SovaSpacing.xl),
        child: async.when(
          loading: () => const SizedBox(height: 200, child: LoadingView()),
          error: (e, _) => NoticeBox(e.toString()),
          data: (s) {
            final share = s.share;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Share your Sova Score', style: SovaText.h2),
                const SizedBox(height: SovaSpacing.xs),
                const Text(
                  'A lender, landlord or new circle can open the link and see this card, checked by Sova.',
                  style: SovaText.bodySmall,
                ),
                const SizedBox(height: SovaSpacing.lg),
                _SharedPreview(name: name, score: s),
                const SizedBox(height: SovaSpacing.md),
                const _WhatIsShared(),
                const SizedBox(height: SovaSpacing.xl),
                if (share == null)
                  FilledButton.icon(
                    onPressed: s.ready ? _create : null,
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Create a private link'),
                  )
                else ...[
                  _LinkBox(share: share),
                  const SizedBox(height: SovaSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _stop,
                          icon: const Icon(Icons.link_off_rounded),
                          label: const Text('Stop sharing'),
                        ),
                      ),
                      const SizedBox(width: SovaSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _create,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('New link'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: SovaSpacing.sm),
                  const Text(
                    'A new link shows your score as it is now and stops the old link working.',
                    style: SovaText.caption,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The card as others will see it on the website.
class _SharedPreview extends StatelessWidget {
  const _SharedPreview({required this.name, required this.score});

  final String name;
  final SovaScore score;

  @override
  Widget build(BuildContext context) {
    final s = score;
    final white = SovaText.caption.copyWith(color: SovaColors.white.withValues(alpha: 0.8));
    return ClipRRect(
      borderRadius: BorderRadius.circular(SovaRadius.xl),
      child: ColoredBox(
        color: SovaColors.electric,
        child: CustomPaint(
          painter: AdirePainter(color: SovaColors.white.withValues(alpha: 0.10), tile: 96),
          child: Padding(
            padding: const EdgeInsets.all(SovaSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: SovaText.h3.copyWith(color: SovaColors.white)),
                      const SizedBox(height: 2),
                      Text(
                        '${(s.onTimeRate * 100).round()}% on time · ${s.confirmedPayments} payments · '
                        '${s.completedCircles} circle${s.completedCircles == 1 ? '' : 's'} finished',
                        style: white,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SovaSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      s.score == null ? '–' : '${s.score}',
                      style: SovaText.moneyLarge.copyWith(color: SovaColors.white, fontSize: 40, height: 1),
                    ),
                    Text(s.band ?? 'Not yet', style: white),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WhatIsShared extends StatelessWidget {
  const _WhatIsShared();

  @override
  Widget build(BuildContext context) {
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: SovaSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: SovaColors.electric),
              const SizedBox(width: SovaSpacing.sm),
              Expanded(child: Text(text, style: SovaText.bodySmall.copyWith(color: SovaColors.navy900))),
            ],
          ),
        );
    return Column(
      children: [
        line(Icons.visibility_outlined, 'Shown: first name and initial, score, on-time rate, payments and circles counted.'),
        line(Icons.visibility_off_outlined, 'Never shown: your phone number, circle names, amounts or bank details.'),
      ],
    );
  }
}

class _LinkBox extends StatelessWidget {
  const _LinkBox({required this.share});

  final ScoreShare share;

  @override
  Widget build(BuildContext context) {
    final link = scoreLink(share.token);
    return Container(
      padding: const EdgeInsets.all(SovaSpacing.md),
      decoration: BoxDecoration(
        color: SovaColors.mist,
        borderRadius: BorderRadius.circular(SovaRadius.md),
        border: Border.all(color: SovaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Live link · made ${shortDate(share.sharedAt)} · score ${share.score}', style: SovaText.caption),
          const SizedBox(height: SovaSpacing.xs),
          SelectableText(link, style: SovaText.bodySmall.copyWith(color: SovaColors.navy900)),
          const SizedBox(height: SovaSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: link));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied.')));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(text: 'My Sova Score, checked by Sova: $link', subject: 'My Sova Score'),
                  ),
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('Share'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
