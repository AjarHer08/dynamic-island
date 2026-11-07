import 'package:flutter/material.dart';

/// 32 bar vertikal via Canvas — paling murah untuk GPU lemah.
class BarsVisualizer extends StatelessWidget {
  final List<double> spectrum;
  final Color color;
  final double height;

  const BarsVisualizer({
    super.key,
    required this.spectrum,
    required this.color,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: spectrum.length * 5.0,
        child: CustomPaint(painter: _BarsPainter(spectrum, color)),
      );
}

class _BarsPainter extends CustomPainter {
  final List<double> s;
  final Color c;
  _BarsPainter(this.s, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final barW = size.width / s.length - 1.5;
    final paint = Paint()..color = c;
    for (var i = 0; i < s.length; i++) {
      final h = s[i].clamp(0.05, 1.0) * size.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * (barW + 1.5), size.height - h, barW, h),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => old.s != s;
}