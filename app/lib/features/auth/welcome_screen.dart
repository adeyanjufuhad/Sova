import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../data/providers.dart';
import '../../shared/widgets/adire_painter.dart';
import '../../shared/widgets/common.dart';

class _Slide {
  const _Slide(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

const _slides = [
  _Slide(
    Icons.receipt_long_rounded,
    'Your ajo, on record.',
    'Every contribution gets a receipt and every member knows their turn. No more lost notebooks.',
  ),
  _Slide(
    Icons.draw_rounded,
    'Everyone signs the rules.',
    'Late fines, leaving early, emergencies: agreed up front, so nobody argues later.',
  ),
  _Slide(
    Icons.account_balance_rounded,
    'Your money stays in your bank.',
    'Members pay each other directly. Sova never holds your money; it just keeps the record.',
  ),
];

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      ref.read(authProvider.notifier).finishOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.screenH, vertical: SovaSpacing.lg),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SovaLogo(size: 28),
                  if (!last)
                    TextButton(
                      onPressed: () => ref.read(authProvider.notifier).finishOnboarding(),
                      child: const Text('Skip'),
                    ),
                ],
              ),
              const SizedBox(height: SovaSpacing.xl2),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    final s = _slides[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AdirePanel(
                            radius: SovaRadius.xl2,
                            child: Center(
                              child: Container(
                                width: 104,
                                height: 104,
                                decoration: const BoxDecoration(color: SovaColors.white, shape: BoxShape.circle),
                                child: Icon(s.icon, size: 48, color: SovaColors.electric),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: SovaSpacing.xl3),
                        Text(s.title, style: SovaText.display),
                        const SizedBox(height: SovaSpacing.md),
                        Text(s.body, style: SovaText.body),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: SovaSpacing.xl2),
              Row(
                children: [
                  for (var i = 0; i < _slides.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: SovaSpacing.sm),
                      width: i == _page ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? SovaColors.electric : SovaColors.borderStrong,
                        borderRadius: BorderRadius.circular(SovaRadius.full),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: SovaSpacing.xl2),
              FilledButton(onPressed: _next, child: Text(last ? 'Get started' : 'Next')),
            ],
          ),
        ),
      ),
    );
  }
}
