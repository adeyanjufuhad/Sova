import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../core/theme/theme.dart';

class GlassTab {
  const GlassTab({required this.icon, required this.selectedIcon, required this.label});
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// The bottom tab bar, in the style of iOS "liquid glass" (an owner decision
/// for this one element): a frosted, translucent pill that blurs what scrolls
/// behind it, with a lighter glass lens over the current tab.
///
/// The lens can be dragged along the bar: it swells a little while held,
/// the icons under it take the brand colour as it passes, and on release it
/// snaps to the nearest tab and opens it. Tapping a tab works as usual.
class GlassTabBar extends StatefulWidget {
  const GlassTabBar({super.key, required this.tabs, required this.currentIndex, required this.onSelect});

  final List<GlassTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const height = 66.0;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar> with TickerProviderStateMixin {
  static const _pad = 5.0;

  /// Lens position in tab units: 0 is the first tab, tabs.length - 1 the last.
  late final AnimationController _pos = AnimationController.unbounded(vsync: this, value: widget.currentIndex.toDouble());

  /// 0 at rest, 1 while the lens is held (it grows and clears slightly).
  late final AnimationController _held = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));

  bool _dragging = false;
  int _lastNearest = 0;
  double _itemWidth = 1;

  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

  @override
  void didUpdateWidget(GlassTabBar old) {
    super.didUpdateWidget(old);
    if (!_dragging && old.currentIndex != widget.currentIndex) _slideTo(widget.currentIndex);
  }

  @override
  void dispose() {
    _pos.dispose();
    _held.dispose();
    super.dispose();
  }

  void _slideTo(int index) {
    if (_reduceMotion) {
      _pos.value = index.toDouble();
      return;
    }
    // A short spring with a little overshoot, like a drop of liquid settling.
    _pos.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 420, damping: 30),
      _pos.value,
      index.toDouble(),
      _pos.velocity,
    ));
  }

  double _positionAt(double dx) => ((dx - _pad) / _itemWidth - 0.5).clamp(0.0, widget.tabs.length - 1.0);

  void _dragStart(DragStartDetails d) {
    _dragging = true;
    _pos.stop();
    _lastNearest = widget.currentIndex;
    if (!_reduceMotion) _held.forward();
    _pos.value = _positionAt(d.localPosition.dx);
  }

  void _dragUpdate(DragUpdateDetails d) {
    _pos.value = _positionAt(d.localPosition.dx);
    final nearest = _pos.value.round();
    if (nearest != _lastNearest) {
      _lastNearest = nearest;
      HapticFeedback.selectionClick();
    }
  }

  void _dragEnd([DragEndDetails? _]) {
    _dragging = false;
    _held.reverse();
    final target = _pos.value.round();
    _slideTo(target);
    if (target != widget.currentIndex) widget.onSelect(target);
  }

  void _tap(int i) {
    HapticFeedback.selectionClick();
    if (i == widget.currentIndex) {
      widget.onSelect(i); // lets the shell return the tab to its first screen
    } else {
      _slideTo(i);
      widget.onSelect(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.tabs.length;
    return LayoutBuilder(
      builder: (context, box) {
        _itemWidth = (box.maxWidth - _pad * 2) / n;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _dragStart,
          onHorizontalDragUpdate: _dragUpdate,
          onHorizontalDragEnd: _dragEnd,
          onHorizontalDragCancel: _dragEnd,
          child: SizedBox(
            height: GlassTabBar.height,
            child: DecoratedBox(
              // The only shadow in Sova: soft and short, to lift the glass off the page.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(SovaRadius.full),
                boxShadow: [
                  BoxShadow(color: SovaColors.navy900.withValues(alpha: 0.10), blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(SovaRadius.full),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(SovaRadius.full),
                      // Frosted body with light catching the top edge.
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          SovaColors.white.withValues(alpha: 0.84),
                          SovaColors.white.withValues(alpha: 0.70),
                        ],
                      ),
                      border: Border.all(color: SovaColors.white.withValues(alpha: 0.9), width: 1.2),
                    ),
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_pos, _held]),
                      builder: (context, _) => Stack(
                        children: [
                          _lens(),
                          Row(
                            children: [
                              const SizedBox(width: _pad),
                              for (var i = 0; i < n; i++) Expanded(child: _item(i)),
                              const SizedBox(width: _pad),
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
        );
      },
    );
  }

  /// The glass lens over the current tab.
  Widget _lens() {
    final held = Curves.easeOut.transform(_held.value);
    final scale = lerpDouble(1, 1.12, held)!;
    return Positioned(
      left: _pad + _pos.value * _itemWidth,
      top: _pad,
      bottom: _pad,
      width: _itemWidth,
      child: Transform.scale(
        scale: scale,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SovaRadius.full),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                SovaColors.electric.withValues(alpha: lerpDouble(0.14, 0.08, held)!),
                SovaColors.sky.withValues(alpha: lerpDouble(0.16, 0.10, held)!),
              ],
            ),
            border: Border.all(color: SovaColors.white.withValues(alpha: 0.95), width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget _item(int i) {
    final tab = widget.tabs[i];
    // How close the lens is to this tab: 1 under it, 0 a whole tab away.
    final near = (1 - (_pos.value - i).abs()).clamp(0.0, 1.0);
    final colour = Color.lerp(SovaColors.textMuted, SovaColors.electric, near)!;
    final selected = i == widget.currentIndex;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: () => _tap(i),
        highlightShape: BoxShape.rectangle,
        radius: 0,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(near > 0.5 ? tab.selectedIcon : tab.icon, color: colour, size: 24),
            const SizedBox(height: 2),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: SovaText.caption.copyWith(color: colour, fontWeight: near > 0.5 ? FontWeight.w700 : FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
