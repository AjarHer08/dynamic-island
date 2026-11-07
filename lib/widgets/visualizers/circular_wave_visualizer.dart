import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Gelombang radial melingkar — 1 Path + drawPath, sangat murah.
class CircularWaveVisualizer extends StatelessWidget {
  final List<double> spectrum;
  final Color color;
  final double size;

  const CircularWaveVisualizer({
    super.key,
    required this.spectrum,
    required this.color,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _WavePainter(spectrum, color)),
      );
}

class _WavePainter extends CustomPainter {
  final List<double> s;
  final Color c;
  _WavePainter(this.s, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dim = math.min(size.width, size.height);
    final k = (dim / 80).clamp(0.35, 1.0).toDouble(); // skala garis di kotak kecil
    final baseR = dim * 0.30;
    final maxAmp = dim * 0.18;
    final n = s.length;

    canvas.drawCircle(
      center,
      baseR + maxAmp * 0.5,
      Paint()
        ..color = c.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * k,
    );

    final path = Path();
    for (var i = 0; i <= n; i++) {
      final angle = (i % n) / n * 2 * math.pi - math.pi / 2;
      final r = baseR + s[i % n] * maxAmp;
      final pt = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = (2 * k).clamp(1.0, 2.0).toDouble()
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, 4 * k, Paint()..color = c);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.s != s;
}