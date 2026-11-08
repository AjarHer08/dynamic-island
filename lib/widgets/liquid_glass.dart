import 'package:flutter/material.dart';

import '../theme/island_theme.dart';

/// Efek "liquid glass" untuk island.
///
/// Flutter di desktop tidak bisa mengaburkan wallpaper di belakang jendela
/// transparan, jadi kacanya digambar langsung: tint tembus pandang, gradasi
/// cahaya, kilau atas (sheen), semburat warna tipis di tepi, cahaya dalam
/// (inner glow), dan garis tepi specular yang terang di sudut kiri-atas.
class LiquidGlassPainter extends CustomPainter {
  const LiquidGlassPainter({
    required this.radius,
    required this.tint,
    required this.opacity,
    required this.accent,
  });

  final double radius;
  final Color tint;
  final double opacity;

  /// Warna aksen gaya aktif: dipakai untuk semburat cahaya di tepi.
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final r = radius.clamp(0.0, size.shortestSide / 2).toDouble();
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(r));
    const clear = Color(0x00FFFFFF);

    // 1. Tint dasar tembus pandang.
    canvas.drawRRect(
        rr, Paint()..color = tint.withValues(alpha: (opacity * 0.74).clamp(0.0, 1.0)));

    canvas.save();
    canvas.clipRRect(rr);

    // 2. Gradasi cahaya dari kiri-atas.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.20),
            Colors.white.withValues(alpha: 0.03),
            Colors.white.withValues(alpha: 0.09),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );

    // 3. Semburat warna tipis (iridescent) di dua sudut.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.bottomRight,
          radius: 1.1,
          colors: [accent.withValues(alpha: 0.18), clear],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-1, -0.3),
          radius: 0.9,
          colors: [const Color(0xFFB784FF).withValues(alpha: 0.12), clear],
        ).createShader(rect),
    );

    // 4. Kilau di bagian atas (sheen).
    final sheen = Rect.fromLTWH(0, 0, size.width, size.height * 0.5);
    canvas.drawRect(
      sheen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.16), clear],
        ).createShader(sheen),
    );

    // 5. Cahaya dalam di sepanjang tepi.
    canvas.drawRRect(
      rr.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = Colors.white.withValues(alpha: 0.13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.restore();

    // 5b. Tepi berwarna aksen (cahaya tipis sesuai gaya visual).
    canvas.drawRRect(
      rr.deflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = accent.withValues(alpha: 0.42),
    );

    // 6. Garis tepi specular: terang di kiri-atas, redup di tengah,
    //    sedikit terang lagi di kanan-bawah.
    canvas.drawRRect(
      rr.deflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.75),
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.03),
            Colors.white.withValues(alpha: 0.38),
          ],
          stops: const [0, 0.35, 0.65, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant LiquidGlassPainter old) =>
      old.radius != radius ||
      old.tint != tint ||
      old.opacity != opacity ||
      old.accent != accent;
}

/// Dekorasi kartu di dalam panel: kaca bila tema liquid glass, polos bila tidak.
BoxDecoration cardDecoration(IslandTheme t,
    {double radius = 12, double plainAlpha = 0.05}) {
  if (!t.glass) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: plainAlpha),
      borderRadius: BorderRadius.circular(radius),
    );
  }
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: 0.17),
        Colors.white.withValues(alpha: 0.05),
      ],
    ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
  );
}


/// Bingkai HUD untuk gaya Gaming: garis dalam bersudut potong dan
/// penanda siku di empat sudut. [visible] 0..1 mengikuti animasi buka.
class HudFramePainter extends CustomPainter {
  const HudFramePainter({required this.color, required this.visible});
  final Color color;
  final double visible;

  @override
  void paint(Canvas canvas, Size size) {
    if (visible <= 0.01 || size.width < 120) return;
    final a = visible.clamp(0.0, 1.0).toDouble();
    const inset = 6.0, cut = 9.0;
    final r = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);
    final frame = Path()
      ..moveTo(r.left + cut, r.top)
      ..lineTo(r.right - cut, r.top)
      ..lineTo(r.right, r.top + cut)
      ..lineTo(r.right, r.bottom - cut)
      ..lineTo(r.right - cut, r.bottom)
      ..lineTo(r.left + cut, r.bottom)
      ..lineTo(r.left, r.bottom - cut)
      ..lineTo(r.left, r.top + cut)
      ..close();
    canvas.drawPath(
        frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.38 * a));

    final br = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square
      ..color = color.withValues(alpha: 0.95 * a);
    const o = 3.0, l = 16.0;
    final w = size.width, h = size.height;
    for (final c in [
      [Offset(o, o + l), Offset(o, o), Offset(o + l, o)],
      [Offset(w - o - l, o), Offset(w - o, o), Offset(w - o, o + l)],
      [Offset(o, h - o - l), Offset(o, h - o), Offset(o + l, h - o)],
      [Offset(w - o - l, h - o), Offset(w - o, h - o), Offset(w - o, h - o - l)],
    ]) {
      canvas.drawPath(
          Path()
            ..moveTo(c[0].dx, c[0].dy)
            ..lineTo(c[1].dx, c[1].dy)
            ..lineTo(c[2].dx, c[2].dy),
          br);
    }
  }

  @override
  bool shouldRepaint(covariant HudFramePainter old) =>
      old.color != color || old.visible != visible;
}
