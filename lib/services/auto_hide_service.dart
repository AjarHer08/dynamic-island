import 'dart:async';
import 'dart:ui' show Rect;

import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'fullscreen_detector.dart';

enum _Hidden { none, idle, video }

/// Menyembunyikan island secara otomatis:
///  * Saat menonton (aplikasi layar penuh / video yang sedang diputar):
///    hilang seketika, muncul lagi setelah selesai.
///  * Saat tidak dipakai beberapa detik: hilang, lalu muncul lagi bila ada
///    notifikasi/alarm/musik, kursor digerakkan ke tempat island, atau lewat
///    menu tray.
class AutoHideService {
  AutoHideService._();
  static final AutoHideService instance = AutoHideService._();

  // Diisi oleh aplikasi.
  bool Function() idleEnabled = () => true;
  int Function() idleSeconds = () => 20;
  bool Function() videoEnabled = () => true;

  /// Island sedang dipakai: terbuka, ada notifikasi, alarm, atau musik.
  bool Function() isActive = () => false;

  /// Harus tampil walau sedang menonton (alarm berbunyi).
  bool Function() isUrgent = () => false;

  /// Video/anime/YouTube sedang diputar (terdeteksi dari pemutar media).
  bool Function() isVideoPlaying = () => false;

  Timer? _timer;
  bool _busy = false;
  _Hidden _state = _Hidden.none;
  DateTime _last = DateTime.now();
  DateTime _suppressUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Rect? _rect;

  void start() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 300), (_) => _tick());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// Dipakai menu tray "Show": tampilkan dan jangan sembunyikan dulu 30 detik.
  Future<void> wake() async {
    _suppressUntil = DateTime.now().add(const Duration(seconds: 30));
    _last = DateTime.now();
    _state = _Hidden.none;
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  Future<void> _hide(_Hidden why) async {
    try {
      _rect = await windowManager.getBounds();
    } catch (_) {}
    _state = why;
    try {
      await windowManager.hide();
    } catch (_) {}
  }

  Future<void> _show() async {
    _state = _Hidden.none;
    _last = DateTime.now();
    try {
      // Tampil tanpa merebut fokus (agar tidak mengganggu yang sedang diketik).
      await (windowManager as dynamic).show(inactive: true);
    } catch (_) {
      try {
        await windowManager.show();
      } catch (_) {}
    }
  }

  Future<bool> _cursorInZone() async {
    final r = _rect;
    if (r == null) return false;
    try {
      final p = await screenRetriever.getCursorScreenPoint();
      return r.inflate(3).contains(p);
    } catch (_) {
      return false;
    }
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final now = DateTime.now();
      var active = isActive();
      if (!active && _state == _Hidden.none) {
        // Kursor di atas island = sedang dipakai.
        try {
          _rect = await windowManager.getBounds();
          if (await _cursorInZone()) active = true;
        } catch (_) {}
      }
      if (active) _last = now;
      if (now.isBefore(_suppressUntil)) return;

      // 1) Menonton -> hilang seketika.
      final urgent = isUrgent();
      final watching =
          videoEnabled() && (await FullscreenDetector.isFullscreen() || isVideoPlaying());
      if (watching && !urgent) {
        if (_state != _Hidden.video) await _hide(_Hidden.video);
        return;
      }
      if (_state == _Hidden.video) await _show();

      // 2) Tidak dipakai -> hilang setelah beberapa detik.
      if (!idleEnabled()) {
        if (_state == _Hidden.idle) await _show();
        return;
      }
      if (_state == _Hidden.idle) {
        if (active || await _cursorInZone()) await _show();
      } else if (!active &&
          now.difference(_last).inSeconds >= idleSeconds()) {
        await _hide(_Hidden.idle);
      }
    } catch (_) {
      // Jangan pernah menjatuhkan aplikasi karena fitur sembunyi otomatis.
    } finally {
      _busy = false;
    }
  }
}
