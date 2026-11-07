import 'dart:async';
import 'dart:io';

/// Bunyi sistem lewat `paplay` (PulseAudio/PipeWire) atau `canberra-gtk-play`.
/// Tidak butuh paket Flutter tambahan.
class SoundService {
  SoundService._();

  static Process? _proc;
  static Timer? _loop;

  static Future<void> _play(String name) async {
    if (!Platform.isLinux) return;
    final file = '/usr/share/sounds/freedesktop/stereo/$name.oga';
    try {
      if (await File(file).exists()) {
        _proc = await Process.start('paplay', [file]);
        return;
      }
    } catch (_) {}
    try {
      _proc = await Process.start('canberra-gtk-play', ['-i', name]);
    } catch (_) {}
  }

  /// Bunyi singkat untuk pengingat.
  static void chime() => _play('complete');

  /// Alarm: berulang tiap 2 detik, berhenti sendiri setelah ~40 detik.
  static void startAlarm() {
    stop();
    var n = 0;
    _play('alarm-clock-elapsed');
    _loop = Timer.periodic(const Duration(seconds: 2), (_) {
      if (++n >= 20) {
        stop();
        return;
      }
      _play('alarm-clock-elapsed');
    });
  }

  static void stop() {
    _loop?.cancel();
    _loop = null;
    _proc?.kill();
    _proc = null;
  }
}
