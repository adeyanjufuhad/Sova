import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../data/providers.dart';
import '../../shared/widgets/adire_painter.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/polish.dart';

class _Slide {
  const _Slide(this.title, this.body, this.cardLabel, this.cardValue, this.cardFoot);
  final String title;
  final String body;
  final String cardLabel;
  final String cardValue;
  final String cardFoot;
}

const _slides = [
  _Slide(
    'Your ajo.\nOn record.',
    'Every contribution gets a receipt and every member knows their turn. No more lost notebooks.',
    'Office Esusu',
    '₦100,000',
    'Your turn · 4 of 6',
  ),
  _Slide(
    'Rules everyone\nsigns.',
    'Late fines, leaving early, emergencies: agreed up front, so nobody argues later.',
    'Group rules · v1',
    '6 of 6',
    'Members accepted',
  ),
  _Slide(
    'Your money stays\nin your bank.',
    'Members pay each other directly. Sova never holds your money; it keeps the record.',
    'Receipt · SV-4821',
    '₦20,000',
    'Confirmed by both',
  ),
];

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _controller = PageController();
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _page = _controller.page ?? 0));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _startingDemo = false;

  void _start() => ref.read(authProvider.notifier).finishOnboarding();

  /// Straight into the shared demo account, for judges and the curious.
  Future<void> _tryDemo() async {
    setState(() => _startingDemo = true);
    try {
      await ref.read(authProvider.notifier).startDemo();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _startingDemo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = _page.round();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.lg, SovaSpacing.sm, 0),
              child: Row(
                children: [
                  const SovaLogo(size: 28),
                  const Spacer(),
                  if (index < _slides.length - 1) TextButton(onPressed: _start, child: const Text('Skip')),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                itemBuilder: (context, i) {
                  final s = _slides[i];
                  // How far this slide is from the centre, for a gentle parallax on the card.
                  final offset = (_page - i).clamp(-1.0, 1.0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.screenH),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: SovaSpacing.xl2),
                        Text(s.title, style: SovaText.display.copyWith(fontSize: 36)),
                        const SizedBox(height: SovaSpacing.md),
                        Text(s.body, style: SovaText.body),
                        Expanded(
                          child: Center(
                            child: Transform.translate(
                              offset: Offset(offset * -60, 0),
                              child: _CardArt(slide: s, tilt: -0.14 + offset * 0.1),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, 0, SovaSpacing.screenH, SovaSpacing.lg),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _slides.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == index ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == index ? SovaColors.electric : SovaColors.borderStrong,
                            borderRadius: BorderRadius.circular(SovaRadius.full),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: SovaSpacing.xl2),
                  Pressable(
                    onTap: index < _slides.length - 1
                        ? () => _controller.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic)
                        : _start,
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(color: SovaColors.navy900, borderRadius: BorderRadius.circular(SovaRadius.full)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(index < _slides.length - 1 ? 'Next' : 'Get started',
                              style: SovaText.button.copyWith(color: SovaColors.white)),
                          const SizedBox(width: SovaSpacing.sm),
                          const Icon(Icons.arrow_forward_rounded, color: SovaColors.white, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: SovaSpacing.md),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Already have an account?', style: SovaText.bodySmall),
                      TextButton(onPressed: _start, child: const Text('Log in')),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: _startingDemo ? null : _tryDemo,
                    icon: _startingDemo
                        ? const SizedBox.square(
                            dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: SovaColors.electric))
                        : const Icon(Icons.play_circle_outline_rounded),
                    label: const Text('Try the demo'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A flat "bank card" for the circle, floating over a soft blue disc.
class _CardArt extends StatelessWidget {
  const _CardArt({required this.slide, required this.tilt});

  final _Slide slide;
  final double tilt;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 260,
            height: 260,
            decoration: const BoxDecoration(color: SovaColors.mist, shape: BoxShape.circle),
          ),
          Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: SovaColors.electricTint, width: 2)),
          ),
          Transform.rotate(
            angle: tilt,
            child: Container(
              width: 270,
              height: 168,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(SovaRadius.xl2),
                border: Border.all(color: SovaColors.navy700),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(SovaRadius.xl2),
                child: ColoredBox(
                  color: SovaColors.navy900,
                  child: CustomPaint(
                    painter: AdirePainter(color: SovaColors.white.withValues(alpha: 0.06), tile: 90),
                    child: Padding(
                      padding: const EdgeInsets.all(SovaSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const SovaLogo(size: 22, onBlue: true),
                              const Spacer(),
                              const Icon(Icons.verified_rounded, color: SovaColors.sky, size: 20),
                            ],
                          ),
                          const Spacer(),
                          Text(slide.cardLabel,
                              style: SovaText.caption.copyWith(color: SovaColors.white.withValues(alpha: 0.7))),
                          const SizedBox(height: 2),
                          Text(slide.cardValue, style: SovaText.moneyMedium.copyWith(color: SovaColors.white, fontSize: 24)),
                          const SizedBox(height: SovaSpacing.xs),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  slide.cardFoot,
                                  style: SovaText.caption.copyWith(color: SovaColors.sky),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Six turns in the circle; the first three have been paid out.
                              for (var t = 0; t < 6; t++)
                                Container(
                                  width: 7,
                                  height: 7,
                                  margin: const EdgeInsets.only(left: 4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: t < 3 ? SovaColors.sky : SovaColors.white.withValues(alpha: 0.25),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
