import 'package:flutter/material.dart';
import '../providers/settings_provider.dart';

/// Token gaya per preset. blurSigma dibatasi <= 8 demi GPU Intel HD.
class IslandTheme {
  final Color pillColor, expandedColor, accentColor;
  final double pillHeight, pillWidth, expandedWidth, expandedHeight;
  final double borderRadius, blurSigma;
  final TextStyle titleStyle, subtitleStyle;

  /// Bingkai HUD bersudut (gaya Gaming).
  final bool hud;

  /// Gradasi cincin gauge RAM dan GPU di panel Performa.
  final List<Color> ramColors, gpuColors;

  /// Warna chip tab aktif: aksen yang digelapkan supaya teks putih terbaca.
  Color get chipFill => Color.lerp(accentColor, Colors.black,
      accentColor.computeLuminance() > 0.6 ? 0.45 : 0.22)!;

  /// Gaya liquid glass (kaca tembus pandang dengan kilau & tepi specular).
  final bool glass;
  final double? _expandedRadius;

  /// Sudut panel saat terbuka. Bila tidak diatur pengguna: 1.4x sudut pill.
  double get expandedRadius => _expandedRadius ?? borderRadius * 1.4;

  const IslandTheme({
    required this.pillColor,
    required this.expandedColor,
    required this.accentColor,
    required this.pillHeight,
    required this.pillWidth,
    required this.expandedWidth,
    required this.expandedHeight,
    required this.borderRadius,
    required this.blurSigma,
    required this.titleStyle,
    required this.subtitleStyle,
    double? expandedRadius,
    this.glass = false,
    this.hud = false,
    this.ramColors = const [Color(0xFFFF9F0A), Color(0xFFFFD60A)],
    this.gpuColors = const [Color(0xFF30D158), Color(0xFFFFD60A)],
  }) : _expandedRadius = expandedRadius;

  /// Ganti warna, ukuran, dan sudut. Warna judul yang mengikuti aksen
  /// (mis. Gaming) ikut diganti.
  IslandTheme copyWith({
    Color? pillColor,
    Color? expandedColor,
    Color? accentColor,
    double? pillWidth,
    double? pillHeight,
    double? expandedWidth,
    double? expandedHeight,
    double? borderRadius,
    double? expandedRadius,
    bool? glass,
  }) =>
      IslandTheme(
        pillColor: pillColor ?? this.pillColor,
        expandedColor: expandedColor ?? this.expandedColor,
        accentColor: accentColor ?? this.accentColor,
        pillHeight: pillHeight ?? this.pillHeight,
        pillWidth: pillWidth ?? this.pillWidth,
        expandedWidth: expandedWidth ?? this.expandedWidth,
        expandedHeight: expandedHeight ?? this.expandedHeight,
        borderRadius: borderRadius ?? this.borderRadius,
        expandedRadius: expandedRadius ?? _expandedRadius,
        blurSigma: blurSigma,
        titleStyle: (accentColor != null && titleStyle.color == this.accentColor)
            ? titleStyle.copyWith(color: accentColor)
            : titleStyle,
        subtitleStyle: subtitleStyle,
        glass: glass ?? this.glass,
        hud: hud,
        ramColors: ramColors,
        gpuColors: gpuColors,
      );

  static IslandTheme from(VisualStyle s) => switch (s) {
        VisualStyle.ios17 => const IslandTheme(
              pillColor: Color(0xFF000000),
              expandedColor: Color(0xFF1C1C1E),
              accentColor: Color(0xFF0A84FF),
              pillHeight: 38, pillWidth: 214,
              expandedWidth: 420, expandedHeight: 420,
              borderRadius: 19, blurSigma: 6,
              gpuColors: [Color(0xFF30D158), Color(0xFFFFD60A)],
              titleStyle: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              subtitleStyle: TextStyle(color: Color(0xFFAEAEB2), fontSize: 11),
            ),
        VisualStyle.macosNotch => const IslandTheme(
              pillColor: Color(0xFF0D0D0F),
              expandedColor: Color(0xFF161618),
              accentColor: Color(0xFF30D158),
              pillHeight: 36, pillWidth: 220,
              expandedWidth: 430, expandedHeight: 460,
              borderRadius: 18, blurSigma: 4,
              gpuColors: [Color(0xFF30D158), Color(0xFFFFD60A)],
              titleStyle: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              subtitleStyle: TextStyle(color: Color(0xFF8E8E93), fontSize: 11),
            ),
        VisualStyle.materialYou => const IslandTheme(
              pillColor: Color(0xFF2B2935),
              expandedColor: Color(0xFF232130),
              accentColor: Color(0xFFA98BF5),
              pillHeight: 42, pillWidth: 220,
              expandedWidth: 420, expandedHeight: 440,
              borderRadius: 21, blurSigma: 8,
              gpuColors: [Color(0xFF7C4DFF), Color(0xFFFF5C8A)],
              titleStyle: TextStyle(color: Color(0xFFEADDFF), fontSize: 13, fontWeight: FontWeight.w600),
              subtitleStyle: TextStyle(color: Color(0xFFCAC4D0), fontSize: 11),
            ),
        VisualStyle.customGaming => const IslandTheme(
              pillColor: Color(0xFF0A0A12),
              expandedColor: Color(0xFF0F0F1A),
              accentColor: Color(0xFF00FFF7),
              pillHeight: 38, pillWidth: 224,
              expandedWidth: 440, expandedHeight: 480,
              borderRadius: 19, blurSigma: 2,
              expandedRadius: 14,
              hud: true,
              gpuColors: [Color(0xFF00E5FF), Color(0xFF00FFA3)],
              titleStyle: TextStyle(color: Color(0xFF00FFF7), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.2),
              subtitleStyle: TextStyle(color: Color(0xFF7F8C9B), fontSize: 11, letterSpacing: 0.5),
            ),
      };
}