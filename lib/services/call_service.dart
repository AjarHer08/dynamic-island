import 'dart:async';
import 'dart:io';

/// Bantuan untuk panggilan masuk dari aplikasi yang tidak punya API kendali.
class CallService {
  static const _browsers = [
    'firefox', 'navigator', 'librewolf', 'google-chrome', 'chromium',
    'brave', 'vivaldi', 'opera', 'microsoft-edge', 'zen',
  ];

  /// Aktifkan jendela aplikasi penelepon (Linux, butuh `xdotool`) supaya
  /// pengguna bisa menjawab di sana. true bila jendelanya ketemu & diaktifkan.
  static Future<bool> activateApp(String app) async {
    if (!Platform.isLinux) return false;
    final a = app.trim().toLowerCase();
    if (a.isEmpty) return false;
    final isBrowser = _browsers.any((b) => a.contains(b.split('-').last)) ||
        a.contains('whatsapp');
    final classes = isBrowser ? _browsers : [a];
    try {
      for (final c in classes) {
        final id = await _search(['--class', c]);
        if (id != null && await _activate(id)) return true;
      }
      if (!isBrowser) {
        final id = await _search(['--name', a]);
        if (id != null && await _activate(id)) return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<String?> _search(List<String> args) async {
    final r = await Process.run('xdotool', ['search', ...args])
        .timeout(const Duration(seconds: 4));
    if (r.exitCode != 0) return null;
    final ids = (r.stdout as String)
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return ids.isEmpty ? null : ids.last;
  }

  static Future<bool> _activate(String id) async {
    final r = await Process.run('xdotool', ['windowactivate', id])
        .timeout(const Duration(seconds: 4));
    return r.exitCode == 0;
  }
}
