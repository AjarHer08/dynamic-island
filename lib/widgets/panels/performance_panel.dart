import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/performance_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/island_theme.dart';
import '../liquid_glass.dart';
import '../../utils/tr.dart';

class PerformancePanel extends StatefulWidget {
  const PerformancePanel({super.key});

  @override
  State<PerformancePanel> createState() => _PerformancePanelState();
}

class _PerformancePanelState extends State<PerformancePanel> {
  late final PerformanceProvider _perf;

  @override
  void initState() {
    super.initState();
    _perf = context.read<PerformanceProvider>();
    _perf.acquire(); // polling hanya selama panel ini ada
  }

  @override
  void dispose() {
    _perf.release();
    super.dispose();
  }

  /// Cincin gauge 270 derajat dengan gradasi dan ujung membulat.
  Widget _gauge(double? pct, String center, List<Color> colors) {
    return SizedBox(
      width: 68,
      height: 68,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: const Size(68, 68),
          painter: _GaugePainter(
              value: pct == null ? 0 : (pct / 100).clamp(0.0, 1.0).toDouble(),
              colors: colors),
        ),
        Text(center,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _card(IslandTheme t,
      {required String title, required Widget gauge, String? foot}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
        decoration: cardDecoration(t, radius: 16, plainAlpha: 0.06),
        child: Column(children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
          Expanded(child: Center(child: gauge)),
          SizedBox(
            height: 14,
            child: foot == null
                ? null
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(foot,
                        style: t.subtitleStyle.copyWith(fontSize: 10)),
                  ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PerformanceProvider>();
    final t = context.watch<SettingsProvider>().theme;
    final g = p.gpu;
    final isId = Localizations.localeOf(context).languageCode == 'id';
    String gb(int mb) {
      final s = (mb / 1024).toStringAsFixed(1);
      return isId ? s.replaceAll('.', ',') : s;
    }

    final cpuColors = [t.accentColor, Color.lerp(t.accentColor, Colors.white, 0.4)!];
    final ramPct = p.ramFraction * 100;

    String gpuCenter() {
      if (g == null) return '—';
      if (g.tempC != null) return '${g.tempC!.round()}°C';
      if (g.usage != null) return '${g.usage!.round()}%';
      return g.freqMhz == null ? '—' : '${g.freqMhz}';
    }

    String? gpuFoot() {
      if (g == null) return tr(context, 'Tidak terdeteksi', 'Not detected');
      if (g.memUsedMb != null && g.memTotalMb != null) {
        return 'VRAM ${gb(g.memUsedMb!)}/${gb(g.memTotalMb!)} GB';
      }
      if (g.usage == null && g.freqMhz != null) return 'MHz';
      return g.name.isEmpty ? null : g.name;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: !p.loaded
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr(context, 'Membaca...', 'Reading...'),
                  style: t.subtitleStyle),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                height: 138,
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _card(t,
                      title: 'CPU ${p.cpu.round()}%',
                      gauge: _gauge(
                          p.cpu,
                          p.cpuTemp == null
                              ? '${p.cpu.round()}%'
                              : '${p.cpuTemp!.round()}°C',
                          cpuColors)),
                  const SizedBox(width: 8),
                  _card(t,
                      title: p.ramTotalMb == 0
                          ? 'RAM'
                          : 'RAM ${gb(p.ramUsedMb)} GB',
                      gauge: _gauge(ramPct, '${ramPct.round()}%', t.ramColors),
                      foot: p.ramTotalMb == 0
                          ? null
                          : tr(context, 'dari ${gb(p.ramTotalMb)} GB',
                              'of ${gb(p.ramTotalMb)} GB')),
                  const SizedBox(width: 8),
                  _card(t,
                      title: g?.usage != null ? 'GPU ${g!.usage!.round()}%' : 'GPU',
                      gauge: _gauge(g?.usage, gpuCenter(), t.gpuColors),
                      foot: gpuFoot()),
                ]),
              ),
              const SizedBox(height: 10),
              Container(
                height: 108,
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: cardDecoration(t, radius: 16, plainAlpha: 0.06),
                child: Stack(children: [
                  Positioned(
                    left: 12,
                    top: 10,
                    child: Text(tr(context, 'Riwayat CPU', 'CPU history'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  Positioned.fill(
                    top: 30,
                    child: CustomPaint(
                      painter: _AreaPainter(List.of(p.cpuHistory), t.accentColor),
                    ),
                  ),
                ]),
              ),
            ]),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.colors});
  final double value;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke,
        size.height - stroke);
    const start = math.pi * 0.75; // mulai di kiri-bawah
    const total = math.pi * 1.5; // 270 derajat
    canvas.drawArc(
        rect,
        start,
        total,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.10));
    if (value <= 0) return;
    canvas.drawArc(
        rect,
        start,
        total * value,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: total,
            colors: colors,
            transform: const GradientRotation(start),
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.colors != colors;
}

/// Grafik area halus dengan gradasi ke bawah (riwayat CPU).
class _AreaPainter extends CustomPainter {
  _AreaPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final dx = size.width / 39; // 40 sampel penuh = selebar kanvas
    final startX = size.width - dx * (values.length - 1);
    const top = 6.0;
    final h = size.height - top;
    final pts = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(startX + dx * i,
            top + h - (values[i].clamp(0.0, 100.0) / 100) * h)
    ];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final mx = (a.dx + b.dx) / 2;
      line.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    final fill = Path.from(line)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.6), color.withValues(alpha: 0.03)],
          ).createShader(Offset.zero & size));
    canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _AreaPainter old) => true;
}
