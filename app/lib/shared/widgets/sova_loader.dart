import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';

/// Newton's cradle: four flat dots, the outer two swinging in turn, like a
/// payment passing along the circle. Adapted from "newtons-cradle" by
/// dovatgabriel on Uiverse.io (MIT), recoloured to the tokens. The web app's
/// loading screen (`web/index.html`) uses the same loader in CSS.
/// Holds still when the system asks for reduced motion.
class SovaLoader extends StatefulWidget {
  const SovaLoader({super.key, this.size = 40, this.color = SovaColors.electric});

  final double size;
  final Color color;

  @override
  State<SovaLoader> createState() => _SovaLoaderState();
}

class _SovaLoaderState extends State<SovaLoader> with SingleTickerProviderStateMixin {
  static const _swing = 70 * math.pi / 180;

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The first dot swings out and back in the first half of the cycle,
  /// the last dot in the second half (same timing as the CSS original).
  double _angle(double t, {required bool first}) {
    final s = first ? t : t - 0.5;
    if (s < 0 || s >= 0.5) return 0;
    final out = s < 0.25 ? Curves.easeOut.transform(s / 0.25) : 1 - Curves.easeIn.transform((s - 0.25) / 0.25);
    return first ? _swing * out : -_swing * out;
  }

  @override
  Widget build(BuildContext context) {
    final dot = widget.size / 4;
    return Semantics(
      label: 'Loading',
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            return Row(
              children: [
                for (var i = 0; i < 4; i++)
                  Transform.rotate(
                    angle: i == 0 ? _angle(t, first: true) : (i == 3 ? _angle(t, first: false) : 0),
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: dot,
                      height: widget.size,
                      child: Center(
                        child: Container(
                          width: dot,
                          height: dot,
                          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
