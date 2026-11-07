import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Mendeteksi aplikasi layar penuh (film, anime, YouTube fullscreen, game).
///
/// Windows: SHQueryUserNotificationState (shell32) lewat FFI, instan dan murah.
/// Linux (X11): properti _NET_WM_STATE_FULLSCREEN pada jendela aktif (xprop).
class FullscreenDetector {
  // ---------------------------------------------------------------- Windows
  static int Function(Pointer<Int32>)? _shQuery;
  static bool _winFailed = false;

  static bool _windows() {
    if (_winFailed) return false;
    try {
      _shQuery ??= DynamicLibrary.open('shell32.dll')
          .lookupFunction<Int32 Function(Pointer<Int32>),
              int Function(Pointer<Int32>)>('SHQueryUserNotificationState');
      final p = calloc<Int32>();
      try {
        if (_shQuery!(p) != 0) return false;
        final v = p.value;
        // 2 = aplikasi layar penuh, 3 = D3D layar penuh, 4 = mode presentasi
        return v == 2 || v == 3 || v == 4;
      } finally {
        calloc.free(p);
      }
    } catch (_) {
      _winFailed = true;
      return false;
    }
  }

  // ------------------------------------------------------------------ Linux
  static DateTime _lastProbe = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _cached = false;
  static bool _noXprop = false;

  static Future<bool> _linux() async {
    if (_noXprop) return false;
    final now = DateTime.now();
    if (now.difference(_lastProbe) < const Duration(milliseconds: 600)) {
      return _cached;
    }
    _lastProbe = now;
    try {
      final root = await Process.run('xprop', ['-root', '_NET_ACTIVE_WINDOW'])
          .timeout(const Duration(seconds: 2));
      final id = RegExp(r'0x[0-9a-fA-F]+').firstMatch(root.stdout.toString())?.group(0);
      if (id == null || id == '0x0') return _cached = false;
      final st = await Process.run('xprop', ['-id', id, '_NET_WM_STATE'])
          .timeout(const Duration(seconds: 2));
      return _cached = st.stdout.toString().contains('_NET_WM_STATE_FULLSCREEN');
    } on ProcessException {
      _noXprop = true; // xprop tidak terpasang (sudo apt install x11-utils)
      return _cached = false;
    } catch (_) {
      return _cached = false;
    }
  }

  static Future<bool> isFullscreen() async {
    if (Platform.isWindows) return _windows();
    if (Platform.isLinux) return _linux();
    return false;
  }
}
