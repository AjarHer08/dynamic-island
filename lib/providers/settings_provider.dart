import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/island_theme.dart';

enum VisualStyle { ios17, macosNotch, materialYou, customGaming }
enum IslandPosition { topCenter, topRight, bottomCenter, followNotch }
enum VisualizerMode { bars, circularWave, particleSystem, adaptive }

class SettingsProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');
  VisualStyle _style = VisualStyle.macosNotch;
  IslandPosition _pos = IslandPosition.topCenter;
  VisualizerMode _viz = VisualizerMode.circularWave;
  double _opacity = 0.92;
  bool _autoLang = true;
  Color? _customAccent, _customBg;

  // Ukuran & sudut pilihan pengguna. null = pakai bawaan gaya visual.
  double? _pillW, _pillH, _expW, _expH, _rPill, _rExp;
  bool _replyAutoSend = false;
  bool _autoHideIdle = true;
  int _idleSeconds = 20;
  bool _hideOnVideo = true;
  bool _autoUpdate = true;
  bool _glass = true; // efek liquid glass, bisa dipadukan dengan gaya apa pun
  Timer? _saveTimer;

  // Batas slider (dipakai juga oleh UI Settings).
  static const pillWidthRange = (min: 90.0, max: 320.0);
  static const pillHeightRange = (min: 24.0, max: 64.0);
  static const expWidthRange = (min: 340.0, max: 700.0);
  static const expHeightRange = (min: 320.0, max: 720.0);
  static const pillRadiusRange = (min: 0.0, max: 40.0);
  static const expRadiusRange = (min: 0.0, max: 48.0);

  Locale get locale => _locale;
  VisualStyle get style => _style;
  IslandPosition get position => _pos;
  VisualizerMode get vizMode => _viz;
  double get opacity => _opacity;
  bool get autoLang => _autoLang;
  Color? get customAccent => _customAccent;
  Color? get customBackground => _customBg;
  bool get replyAutoSend => _replyAutoSend;
  bool get glass => _glass;
  bool get autoHideIdle => _autoHideIdle;
  int get idleSeconds => _idleSeconds;
  bool get hideOnVideo => _hideOnVideo;
  bool get autoUpdate => _autoUpdate;
  bool get hasCustomSize =>
      _pillW != null || _pillH != null || _expW != null ||
      _expH != null || _rPill != null || _rExp != null;

  /// Tema aktif: preset gaya + warna pilihan pengguna (jika ada).
  IslandTheme get theme {
    var t = IslandTheme.from(_style);
    final bg = _customBg;
    if (bg != null) {
      t = t.copyWith(
          pillColor: bg, expandedColor: Color.lerp(bg, Colors.white, 0.05));
    }
    if (_customAccent != null) t = t.copyWith(accentColor: _customAccent);
    return t.copyWith(
      pillWidth: _pillW,
      pillHeight: _pillH,
      expandedWidth: _expW,
      expandedHeight: _expH,
      borderRadius: _rPill,
      expandedRadius: _rExp,
      glass: _glass,
    );
  }

  static int _idx(int? v, int len, int def) =>
      (v == null || v < 0 || v >= len) ? def : v;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _autoLang = p.getBool('auto_lang') ?? true;
    if (_autoLang) {
      _locale = Platform.localeName.split('_').first == 'id'
          ? const Locale('id')
          : const Locale('en');
    } else {
      _locale = Locale(p.getString('locale') ?? 'en');
    }
    _style = VisualStyle.values[_idx(p.getInt('visual_style'), VisualStyle.values.length, 1)];
    _pos = IslandPosition.values[_idx(p.getInt('island_position'), IslandPosition.values.length, 0)];
    _viz = VisualizerMode.values[_idx(p.getInt('viz_mode'), VisualizerMode.values.length, 1)];
    _opacity = p.getDouble('opacity') ?? 0.92;
    final ca = p.getInt('c_accent'), cb = p.getInt('c_bg');
    _customAccent = ca == null ? null : Color(ca);
    _customBg = cb == null ? null : Color(cb);
    _pillW = p.getDouble('sz_pw');
    _pillH = p.getDouble('sz_ph');
    _expW = p.getDouble('sz_ew');
    _expH = p.getDouble('sz_eh');
    _rPill = p.getDouble('r_pill');
    _rExp = p.getDouble('r_exp');
    _replyAutoSend = p.getBool('reply_autosend') ?? false;
    _glass = p.getBool('glass') ?? true;
    _autoHideIdle = p.getBool('auto_hide_idle') ?? true;
    _idleSeconds = (p.getInt('idle_seconds') ?? 20).clamp(5, 300).toInt();
    _hideOnVideo = p.getBool('hide_on_video') ?? true;
    _autoUpdate = p.getBool('auto_update') ?? true;
    // Set ukuran pill secara eksplisit, lalu posisikan berdasarkan ukuran itu
    // (jangan bergantung pada getSize yang bisa belum terbarui).
    final t = theme;
    final pill = Size(t.pillWidth, t.pillHeight);
    try {
      await windowManager.setSize(pill);
    } catch (_) {}
    await reposition(size: pill);
    notifyListeners();
  }

  Future<void> setAutoLang() async {
    _autoLang = true;
    _locale = Platform.localeName.split('_').first == 'id'
        ? const Locale('id')
        : const Locale('en');
    final p = await SharedPreferences.getInstance();
    await p.setBool('auto_lang', true);
    await p.setString('locale', _locale.languageCode);
    notifyListeners();
  }

  Future<void> setLocale(Locale l) async {
    _locale = l;
    _autoLang = false;
    final p = await SharedPreferences.getInstance();
    await p.setBool('auto_lang', false);
    await p.setString('locale', l.languageCode);
    notifyListeners();
  }

  Future<void> setStyle(VisualStyle s) async {
    _style = s;
    final p = await SharedPreferences.getInstance();
    await p.setInt('visual_style', s.index);
    notifyListeners();
  }

  Future<void> setPosition(IslandPosition pos) async {
    _pos = pos;
    final p = await SharedPreferences.getInstance();
    await p.setInt('island_position', pos.index);
    await reposition();
    notifyListeners();
  }

  Future<void> setVizMode(VisualizerMode m) async {
    _viz = m;
    final p = await SharedPreferences.getInstance();
    await p.setInt('viz_mode', m.index);
    notifyListeners();
  }

  Future<void> setCustomAccent(Color? c) async {
    _customAccent = c;
    final p = await SharedPreferences.getInstance();
    c == null ? await p.remove('c_accent') : await p.setInt('c_accent', c.toARGB32());
    notifyListeners();
  }

  Future<void> setCustomBackground(Color? c) async {
    _customBg = c;
    final p = await SharedPreferences.getInstance();
    c == null ? await p.remove('c_bg') : await p.setInt('c_bg', c.toARGB32());
    notifyListeners();
  }

  Future<void> setOpacity(double o) async {
    _opacity = o.clamp(0.5, 1.0);
    final p = await SharedPreferences.getInstance();
    await p.setDouble('opacity', _opacity);
    notifyListeners();
  }

  Future<void> setAutoHideIdle(bool v) async {
    _autoHideIdle = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('auto_hide_idle', v);
    notifyListeners();
  }

  Future<void> setIdleSeconds(int v) async {
    _idleSeconds = v.clamp(5, 300).toInt();
    final p = await SharedPreferences.getInstance();
    await p.setInt('idle_seconds', _idleSeconds);
    notifyListeners();
  }

  Future<void> setHideOnVideo(bool v) async {
    _hideOnVideo = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('hide_on_video', v);
    notifyListeners();
  }

  Future<void> setAutoUpdate(bool v) async {
    _autoUpdate = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('auto_update', v);
    notifyListeners();
  }

  Future<void> setGlass(bool v) async {
    _glass = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('glass', v);
    notifyListeners();
  }

  Future<void> setReplyAutoSend(bool v) async {
    _replyAutoSend = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('reply_autosend', v);
    notifyListeners();
  }

  // ---- Ukuran & sudut ----

  void setPillWidth(double v) {
    _pillW = v.clamp(pillWidthRange.min, pillWidthRange.max).toDouble();
    _changed();
  }

  void setPillHeight(double v) {
    _pillH = v.clamp(pillHeightRange.min, pillHeightRange.max).toDouble();
    _changed();
  }

  void setExpandedWidth(double v) {
    _expW = v.clamp(expWidthRange.min, expWidthRange.max).toDouble();
    _changed();
  }

  void setExpandedHeight(double v) {
    _expH = v.clamp(expHeightRange.min, expHeightRange.max).toDouble();
    _changed();
  }

  void setPillRadius(double v) {
    _rPill = v.clamp(pillRadiusRange.min, pillRadiusRange.max).toDouble();
    _changed();
  }

  void setExpandedRadius(double v) {
    _rExp = v.clamp(expRadiusRange.min, expRadiusRange.max).toDouble();
    _changed();
  }

  /// Kembalikan ukuran & sudut ke bawaan gaya visual.
  void resetSizes() {
    _pillW = _pillH = _expW = _expH = _rPill = _rExp = null;
    _changed();
  }

  void _changed() {
    notifyListeners();
    // Slider memanggil ini puluhan kali per detik; tulis ke disk sekali saja
    // setelah pengguna berhenti menggeser.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveSizes);
  }

  Future<void> _saveSizes() async {
    final p = await SharedPreferences.getInstance();
    Future<void> put(String k, double? v) async =>
        v == null ? await p.remove(k) : await p.setDouble(k, v);
    await put('sz_pw', _pillW);
    await put('sz_ph', _pillH);
    await put('sz_ew', _expW);
    await put('sz_eh', _expH);
    await put('r_pill', _rPill);
    await put('r_exp', _rExp);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  /// Posisikan window overlay di layar sesuai pilihan user.
  Future<void> reposition({Size? size}) async {
    final sz = size ?? await windowManager.getSize();
    double sw = 1920.0, sh = 1080.0;
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      sw = display.size.width;
      sh = display.size.height;
    } catch (_) {/* pakai fallback 1920x1080 */}
    double x, y;
    switch (_pos) {
      case IslandPosition.topCenter:
        x = (sw - sz.width) / 2; y = 8; break;
      case IslandPosition.topRight:
        x = sw - sz.width - 16; y = 8; break;
      case IslandPosition.bottomCenter:
        x = (sw - sz.width) / 2; y = sh - sz.height - 48; break;
      case IslandPosition.followNotch:
        x = (sw - sz.width) / 2; y = 0; break;
    }
    await windowManager.setPosition(Offset(x, y));
  }
}