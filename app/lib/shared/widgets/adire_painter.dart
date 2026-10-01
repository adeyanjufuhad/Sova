import 'package:flutter/material.dart';

/// Flat line pattern inspired by adire (Yoruba indigo-and-white cloth):
/// oniko circles, lafun diamonds, river waves and dotted fields. Same motif
/// as the website's AdirePattern.
class AdirePainter extends CustomPainter {
  const AdirePainter({required this.color, this.tile = 120});

  final Color color;
  final double tile;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final fill = Paint()..color = color;
    final s = tile / 120; // motif drawn on a 120 grid

    for (double ox = 0; ox < size.width; ox += tile) {
      for (double oy = 0; oy < size.height; oy += tile) {
        Offset p(double x, double y) => Offset(ox + x * s, oy + y * s);

        // oniko circles
        for (final r in [22.0, 14.0, 6.0]) {
          canvas.drawCircle(p(30, 30), r * s, stroke);
        }
        // lafun diamond with cross
        final diamond = Path()
          ..moveTo(p(30, 66).dx, p(30, 66).dy)
          ..lineTo(p(54, 90).dx, p(54, 90).dy)
          ..lineTo(p(30, 114).dx, p(30, 114).dy)
          ..lineTo(p(6, 90).dx, p(6, 90).dy)
          ..close();
        canvas.drawPath(diamond, stroke);
        canvas.drawLine(p(30, 74), p(30, 106), stroke);
        canvas.drawLine(p(14, 90), p(46, 90), stroke);
        // river waves
        for (final y in [76.0, 90.0, 104.0]) {
          final wave = Path()..moveTo(p(60, y).dx, p(60, y).dy);
          for (var i = 0; i < 4; i++) {
            final x0 = 60 + i * 15.0;
            wave.quadraticBezierTo(p(x0 + 7.5, y - 8).dx, p(x0 + 7.5, y - 8).dy, p(x0 + 15, y).dx, p(x0 + 15, y).dy);
          }
          canvas.drawPath(wave, stroke);
        }
        // dotted field
        for (final x in [72.0, 90.0, 108.0]) {
          for (final y in [12.0, 30.0, 48.0]) {
            canvas.drawCircle(p(x, y), 2.5 * s, fill);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(AdirePainter oldDelegate) => oldDelegate.color != color || oldDelegate.tile != tile;
}

/// Solid blue panel with the adire pattern, for hero cards.
class AdirePanel extends StatelessWidget {
  const AdirePanel({super.key, required this.child, this.color, this.radius = 20, this.padding});

  final Widget child;
  final Color? color;
  final double radius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: color ?? Theme.of(context).colorScheme.primary,
        child: CustomPaint(
          painter: AdirePainter(color: Colors.white.withValues(alpha: 0.10), tile: 96),
          child: Padding(padding: padding ?? const EdgeInsets.all(20), child: child),
        ),
      ),
    );
  }
}
