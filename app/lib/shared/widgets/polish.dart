import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';

/// Hide every naira amount at once (eye toggle), e.g. when others can see the screen.
class HideAmounts extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
}

final hideAmountsProvider = NotifierProvider<HideAmounts, bool>(HideAmounts.new);

/// Scales down slightly while pressed, with a light haptic: the tactile feel
/// of top banking apps.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap, this.scale = 0.97, this.semanticLabel});

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    // With a label (icon-only buttons) the label replaces the child's semantics;
    // without one, the child's visible text is merged into a single button so
    // screen readers announce e.g. a payment row's title, date and amount once.
    final semantics = widget.semanticLabel == null
        ? (Widget child) => MergeSemantics(child: Semantics(button: true, child: child))
        : (Widget child) => Semantics(button: true, label: widget.semanticLabel, excludeSemantics: true, child: child);
    return semantics(
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Naira amount that counts up when it first appears and respects the
/// hide-amounts toggle.
class Money extends ConsumerWidget {
  const Money(this.amount, {super.key, required this.style, this.prefix = '', this.animate = false});

  final int amount;
  final TextStyle style;
  final String prefix;
  final bool animate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(hideAmountsProvider)) {
      return Text('$prefix₦ ••••••', style: style);
    }
    if (!animate) return Text('$prefix${naira(amount)}', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: amount.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text('$prefix${naira(v.round())}', style: style),
    );
  }
}

/// Pulsing grey blocks shown while data loads, instead of a spinner.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 16, this.radius = SovaRadius.sm});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: SovaColors.mist, borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
  }
}

/// A placeholder list while a screen loads.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 5});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(SovaSpacing.screenH),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const Skeleton(height: 160, radius: SovaRadius.xl2),
        const SizedBox(height: SovaSpacing.xl2),
        for (var i = 0; i < rows; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: SovaSpacing.lg),
            child: Row(
              children: [
                Skeleton(width: 44, height: 44, radius: SovaRadius.md),
                SizedBox(width: SovaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Skeleton(width: 160), SizedBox(height: SovaSpacing.sm), Skeleton(width: 100, height: 12)],
                  ),
                ),
                Skeleton(width: 70),
              ],
            ),
          ),
      ],
    );
  }
}

/// Pill filter chips (one selected), as in the "All / Needs action" pattern.
class SegmentedChips<T> extends StatelessWidget {
  const SegmentedChips({super.key, required this.options, required this.selected, required this.onChanged});

  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: SovaSpacing.sm,
      children: [
        for (final e in options.entries)
          Pressable(
            onTap: () => onChanged(e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.lg, vertical: SovaSpacing.sm),
              decoration: BoxDecoration(
                color: e.key == selected ? SovaColors.navy900 : SovaColors.mist,
                borderRadius: BorderRadius.circular(SovaRadius.full),
              ),
              child: Text(
                e.value,
                style: SovaText.label.copyWith(
                  fontSize: 13,
                  color: e.key == selected ? SovaColors.white : SovaColors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Section title with an optional trailing action ("See all").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: SovaText.h3.copyWith(fontSize: 17))),
        if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
      ],
    );
  }
}

/// Rounded icon tile used at the start of list rows.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.size = 44, this.filled = false});

  final IconData icon;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? SovaColors.electric : SovaColors.electricTint,
        borderRadius: BorderRadius.circular(SovaRadius.md),
      ),
      child: Icon(icon, size: size * 0.45, color: filled ? SovaColors.white : SovaColors.electric),
    );
  }
}

/// Fades and slides children in, staggered, the first time a screen builds.
class StaggeredIn extends StatelessWidget {
  const StaggeredIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + index * 60),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
      ),
      child: child,
    );
  }
}
