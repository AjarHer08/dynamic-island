import 'package:flutter/material.dart';
import '../providers/settings_provider.dart';

/// Token gaya per preset. blurSigma dibatasi <= 8 demi GPU Intel HD.
class IslandTheme {
  final Color pillColor, expandedColor, accentColor;
  final double pillHeight, pillWidth, expandedWidth, expandedHeight;
  final double borderRadius, blurSigma;
  final TextStyle titleStyle, subtitleStyle;

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
      );

  static IslandTheme from(VisualStyle s) => switch (s) {
        VisualStyle.ios17 => const IslandTheme(
              pillColor: Color(0xFF000000),
              expandedColor: Color(0xFF1C1C1E),
              accentColor: Color(0xFF0A84FF),
              pillHeight: 36, pillWidth: 126,
              expandedWidth: 380, expandedHeight: 420,
              borderRadius: 22, blurSigma: 6,
              titleStyle: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              subtitleStyle: TextStyle(color: Color(0xFFAEAEB2), fontSize: 11),
            ),
        VisualStyle.macosNotch => const IslandTheme(
              pillColor: Color(0xFF0D0D0F),
              expandedColor: Color(0xFF161618),
              accentColor: Color(0xFF30D158),
              pillHeight: 32, pillWidth: 140,
              expandedWidth: 400, expandedHeight: 460,
              borderRadius: 18, blurSigma: 4,
              titleStyle: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              subtitleStyle: TextStyle(color: Color(0xFF8E8E93), fontSize: 11),
            ),
        VisualStyle.materialYou => const IslandTheme(
              pillColor: Color(0xFF2B2935),
              expandedColor: Color(0xFF232130),
              accentColor: Color(0xFFD0BCFF),
              pillHeight: 40, pillWidth: 130,
              expandedWidth: 390, expandedHeight: 440,
              borderRadius: 28, blurSigma: 8,
              titleStyle: TextStyle(color: Color(0xFFEADDFF), fontSize: 13, fontWeight: FontWeight.w600),
              subtitleStyle: TextStyle(color: Color(0xFFCAC4D0), fontSize: 11),
            ),
        VisualStyle.customGaming => const IslandTheme(
              pillColor: Color(0xFF0A0A12),
              expandedColor: Color(0xFF0F0F1A),
              accentColor: Color(0xFF00FFF7),
              pillHeight: 34, pillWidth: 150,
              expandedWidth: 420, expandedHeight: 480,
              borderRadius: 12, blurSigma: 2,
              titleStyle: TextStyle(color: Color(0xFF00FFF7), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.2),
              subtitleStyle: TextStyle(color: Color(0xFF7F8C9B), fontSize: 11, letterSpacing: 0.5),
            ),
      };
}