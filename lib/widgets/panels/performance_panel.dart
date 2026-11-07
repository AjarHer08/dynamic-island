import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/performance_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/island_theme.dart';
import '../liquid_glass.dart';
import '../../utils/tr.dart';

Color _loadColor(double pct, IslandTheme t) {
  if (pct >= 90) return const Color(0xFFFF453A);
  if (pct >= 70) return const Color(0xFFFF9F0A);
  return t.accentColor;
}

String _gb(int mb) => (mb / 1024).toStringAsFixed(1);

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

  Widget _gauge(IslandTheme t, double? pct, String center, Color color) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(
            value: pct == null ? 0 : (pct / 100).clamp(0.0, 1.0).toDouble(),
            strokeWidth: 5,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        Text(center,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _card(IslandTheme t,
      {required IconData icon,
      required String title,
      required Widget gauge,
      required List<String> lines}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: cardDecoration(t, radius: 14, plainAlpha: 0.06),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 12, color: t.accentColor),
            const SizedBox(width: 4),
            Text(title, style: t.subtitleStyle.copyWith(letterSpacing: 1)),
          ]),
          const SizedBox(height: 8),
          gauge,
          const SizedBox(height: 8),
          for (final l in lines)
            Text(l,
                style: t.subtitleStyle.copyWith(fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PerformanceProvider>();
    final t = context.watch<SettingsProvider>().theme;
    final g = p.gpu;
    final na = tr(context, 'N/A', 'N/A');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.speed, size: 14, color: t.accentColor),
          const SizedBox(width: 6),
          Text(tr(context, 'PERFORMA', 'PERFORMANCE'),
              style: t.subtitleStyle.copyWith(letterSpacing: 1)),
        ]),
        const SizedBox(height: 12),
        if (!p.loaded)
          Text(tr(context, 'Membaca...', 'Reading...'), style: t.subtitleStyle)
        else ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _card(t,
                icon: Icons.memory,
                title: 'CPU',
                gauge: _gauge(t, p.cpu, '${p.cpu.round()}%', _loadColor(p.cpu, t)),
                lines: [
                  p.cpuTemp == null ? na : '${p.cpuTemp!.round()}°C',
                ]),
            const SizedBox(width: 8),
            _card(t,
                icon: Icons.developer_board,
                title: 'RAM',
                gauge: _gauge(t, p.ramFraction * 100,
                    '${(p.ramFraction * 100).round()}%',
                    _loadColor(p.ramFraction * 100, t)),
                lines: [
                  p.ramTotalMb == 0
                      ? na
                      : '${_gb(p.ramUsedMb)} / ${_gb(p.ramTotalMb)} GB',
                ]),
            const SizedBox(width: 8),
            _card(t,
                icon: Icons.videogame_asset,
                title: 'GPU',
                gauge: g == null
                    ? _gauge(t, null, '—', Colors.white24)
                    : g.usage != null
                        ? _gauge(t, g.usage, '${g.usage!.round()}%',
                            _loadColor(g.usage!, t))
                        : _gauge(
                            t,
                            null,
                            g.freqMhz == null ? '—' : '${g.freqMhz}',
                            t.accentColor),
                lines: g == null
                    ? [tr(context, 'Tidak terdeteksi', 'Not detected')]
                    : [
                        if (g.name.isNotEmpty) g.name,
                        if (g.tempC != null) '${g.tempC!.round()}°C',
                        if (g.memUsedMb != null && g.memTotalMb != null)
                          'VRAM ${_gb(g.memUsedMb!)}/${_gb(g.memTotalMb!)} GB',
                        if (g.usage == null && g.freqMhz != null) 'MHz',
                      ]),
          ]),
          const SizedBox(height: 12),
          Text(tr(context, 'Riwayat CPU', 'CPU history'),
              style: t.titleStyle.copyWith(fontSize: 11, color: Colors.white54)),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparkPainter(List.of(p.cpuHistory), t.accentColor),
            ),
          ),
        ],
      ]),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final dx = size.width / 39; // 40 sampel penuh = selebar kanvas
    final startX = size.width - dx * (values.length - 1);
    final line = Path();
    final fill = Path();
    for (var i = 0; i < values.length; i++) {
      final x = startX + dx * i;
      final y = size.height - (values[i].clamp(0.0, 100.0) / 100) * size.height;
      if (i == 0) {
        line.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        line.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, size.height);
    fill.close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.15));
    canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => true;
}
