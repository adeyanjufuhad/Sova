import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';

/// Marks a widget as a stop on a guided tour, found by [id].
class TourTarget extends StatefulWidget {
  const TourTarget({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  /// Live targets by id. A tab kept alive offstage stays registered; the tour
  /// switches to the right tab before it looks.
  static final _targets = <String, GlobalKey>{};

  static BuildContext? contextOf(String id) => _targets[id]?.currentContext;

  @override
  State<TourTarget> createState() => _TourTargetState();
}

class _TourTargetState extends State<TourTarget> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    TourTarget._targets[widget.id] = _key;
  }

  @override
  void didUpdateWidget(TourTarget old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      if (TourTarget._targets[old.id] == _key) TourTarget._targets.remove(old.id);
      TourTarget._targets[widget.id] = _key;
    }
  }

  @override
  void dispose() {
    if (TourTarget._targets[widget.id] == _key) TourTarget._targets.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: _key, child: widget.child);
}

/// One stop: a title and a sentence or two, pointing at [target] when given
/// (otherwise a card in the middle). [before] runs first, e.g. to switch tab.
class TourStep {
  const TourStep({required this.title, required this.body, this.target, this.before});

  final String title;
  final String body;
  final String? target;
  final VoidCallback? before;
}

/// Shows [steps] one at a time over everything, dimming the screen around the
/// highlighted part. [onFinish] runs once, whether the tour was finished or
/// skipped. A step whose target never appears is passed over.
void showTour(BuildContext context, List<TourStep> steps, {required VoidCallback onFinish}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  var finished = false;
  entry = OverlayEntry(
    builder: (_) => _TourOverlay(
      steps: steps,
      onFinish: () {
        if (finished) return;
        finished = true;
        entry.remove();
        onFinish();
      },
    ),
  );
  overlay.insert(entry);
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({required this.steps, required this.onFinish});

  final List<TourStep> steps;
  final VoidCallback onFinish;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

/// The app's buttons are full width; the tour's sit side by side.
final _compact = ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(64, 44)),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: SovaSpacing.lg)),
);

class _TourOverlayState extends State<_TourOverlay> {
  int _index = 0;
  Rect? _hole;

  /// False while a step is being prepared (tab switch, scrolling, waiting for data).
  bool _ready = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    // The first step may switch tab, which can't happen while the overlay builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _show(0, forward: true);
    });
  }

  Future<void> _show(int index, {required bool forward}) async {
    final generation = ++_generation;
    setState(() {
      _index = index;
      _ready = false;
    });
    final step = widget.steps[index];
    step.before?.call();
    Rect? hole;
    if (step.target != null) {
      hole = await _locate(step.target!);
      if (!mounted || generation != _generation) return;
      if (hole == null) {
        // Not on this screen (e.g. no turn running yet): move past it.
        final next = forward ? index + 1 : index - 1;
        if (next < 0) return _show(0, forward: true);
        if (next >= widget.steps.length) return widget.onFinish();
        return _show(next, forward: forward);
      }
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted || generation != _generation) return;
    }
    setState(() {
      _hole = hole;
      _ready = true;
    });
  }

  /// Waits up to 2 seconds for the target (screens load their data first),
  /// scrolls it into view, and returns where it is on screen.
  Future<Rect?> _locate(String id) async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return null;
      final target = TourTarget.contextOf(id);
      final box = target?.findRenderObject();
      if (target == null || !target.mounted || box is! RenderBox || !box.attached || !box.hasSize) continue;
      if (Scrollable.maybeOf(target) != null) {
        await Scrollable.ensureVisible(target, alignment: 0.3, duration: const Duration(milliseconds: 250));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        if (!mounted || !box.attached) return null;
      }
      final me = context.findRenderObject() as RenderBox?;
      final origin = box.localToGlobal(Offset.zero, ancestor: me);
      final rect = origin & box.size;
      // Offstage tabs report a size but sit outside the screen.
      if (me != null && !(Offset.zero & me.size).overlaps(rect)) continue;
      return rect.inflate(6);
    }
    return null;
  }

  void _next() {
    if (_index >= widget.steps.length - 1) return widget.onFinish();
    _show(_index + 1, forward: true);
  }

  void _back() {
    if (_index > 0) _show(_index - 1, forward: false);
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_index];
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final hole = _ready ? _hole : null;
    final last = _index == widget.steps.length - 1;

    // The card sits below the highlight when there's room, otherwise above it.
    const cardGap = 14.0;
    double? top;
    double? bottom;
    if (hole != null) {
      final below = size.height - hole.bottom - padding.bottom;
      if (below > 230) {
        top = hole.bottom + cardGap;
      } else {
        bottom = size.height - hole.top + cardGap;
      }
    }

    final card = Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(SovaSpacing.xl, SovaSpacing.lg, SovaSpacing.xl, SovaSpacing.md),
        decoration: BoxDecoration(
          color: SovaColors.white,
          borderRadius: BorderRadius.circular(SovaRadius.xl),
          border: Border.all(color: SovaColors.border),
        ),
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_index + 1} of ${widget.steps.length}', style: SovaText.caption),
              const SizedBox(height: SovaSpacing.xs),
              Text(step.title, style: SovaText.h3),
              const SizedBox(height: SovaSpacing.xs),
              Text(step.body, style: SovaText.bodySmall.copyWith(color: SovaColors.textPrimary)),
              const SizedBox(height: SovaSpacing.md),
              // Wraps onto two lines on narrow screens or with large text.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: SovaSpacing.xs,
                children: [
                  if (!last)
                    TextButton(onPressed: widget.onFinish, style: _compact, child: const Text('Skip tour'))
                  else
                    const SizedBox.shrink(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_index > 0) ...[
                        OutlinedButton(onPressed: _ready ? _back : null, style: _compact, child: const Text('Back')),
                        const SizedBox(width: SovaSpacing.sm),
                      ],
                      FilledButton(onPressed: _ready ? _next : null, style: _compact, child: Text(last ? 'Done' : 'Next')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onFinish(); // system back ends the tour
      },
      child: Stack(
        children: [
          // Taps on the dimmed page are swallowed; the card has the controls.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: CustomPaint(painter: _ScrimPainter(hole)),
            ),
          ),
          if (_ready)
            if (hole == null)
              Center(
                child: Padding(padding: const EdgeInsets.all(SovaSpacing.screenH), child: card),
              )
            else
              Positioned(
                left: SovaSpacing.screenH,
                right: SovaSpacing.screenH,
                top: top,
                bottom: bottom,
                child: Align(alignment: Alignment.center, child: card),
              ),
        ],
      ),
    );
  }
}

/// Navy scrim with a rounded window around the highlighted part and a sky hairline.
class _ScrimPainter extends CustomPainter {
  const _ScrimPainter(this.hole);

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h != null) {
      final window = RRect.fromRectAndRadius(h, const Radius.circular(SovaRadius.lg));
      scrim
        ..addRRect(window)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(scrim, Paint()..color = SovaColors.navy900.withValues(alpha: 0.72));
      canvas.drawRRect(
        window,
        Paint()
          ..color = SovaColors.sky
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    } else {
      canvas.drawPath(scrim, Paint()..color = SovaColors.navy900.withValues(alpha: 0.72));
    }
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole;
}

/// Fires [onStart] once, after the first frame, when [when] is true.
/// Used by screens that start a tour on their first visit.
class TourLauncher {
  bool _started = false;

  void maybeStart(bool when, VoidCallback onStart) {
    if (_started || !when) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(Future<void>.delayed(const Duration(milliseconds: 400), onStart)),
    );
  }
}
