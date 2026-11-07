import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Max 40 partikel orbit — hard cap agar aman di Intel HD.
class ParticleVisualizer extends StatefulWidget {
  final List<double> spectrum;
  final Color color;
  final double size;

  const ParticleVisualizer({
    super.key,
    required this.spectrum,
    required this.color,
    this.size = 80,
  });

  @override
  State<ParticleVisualizer> createState() => _ParticleVisualizerState();
}

class _ParticleVisualizerState extends State<ParticleVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => CustomPaint(
            painter: _ParticlePainter(widget.spectrum, widget.color, _ctrl.value),
          ),
        ),
      );
}

class _ParticlePainter extends CustomPainter {
  final List<double> s;
  final Color c;
  final double t;
  _ParticlePainter(this.s, this.c, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final k = (math.min(size.width, size.height) / 80).clamp(0.3, 1.0).toDouble();
    final rng = math.Random(42); // seed tetap -> deterministik & murah
    for (var i = 0; i < 40; i++) {
      final amp = s[i % s.length];
      final baseR = (8.0 + rng.nextDouble() * 28.0) * k;
      final r = baseR + amp * 14.0 * k;
      final angle = t * (0.4 + rng.nextDouble() * 0.8) * 2 * math.pi + i * 0.37;
      canvas.drawCircle(
        Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)),
        (1.2 + amp * 2.5) * (k < 0.6 ? 0.6 : 1.0),
        Paint()..color = c.withValues(alpha: 0.4 + amp * 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => true;
}