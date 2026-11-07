import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Membaca notifikasi desktop asli (WhatsApp Web, Telegram, Discord, email, dll)
/// dengan memantau panggilan `org.freedesktop.Notifications.Notify` di D-Bus
/// lewat `dbus-monitor` (sudah terpasang di Linux Mint).
class NotificationListenerService {
  Process? _proc;
  StreamSubscription<String>? _sub;

  Future<void> start(
      void Function(String app, String summary, String body) onNotify) async {
    if (!Platform.isLinux || _proc != null) return;
    try {
      _proc = await Process.start('dbus-monitor', [
        '--session',
        "interface='org.freedesktop.Notifications',member='Notify'",
      ]);
    } catch (_) {
      return; // dbus-monitor tidak ada
    }
    _proc!.stderr.drain<void>();

    var inCall = false;
    final strings = <String>[];
    StringBuffer? cur; // string multi-baris yang sedang dibaca

    _sub = _proc!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.startsWith('method call') && line.contains('member=Notify')) {
        inCall = true;
        strings.clear();
        cur = null;
        return;
      }
      if (!inCall) return;

      if (cur != null) {
        if (line.endsWith('"')) {
          cur!.write('\n${line.substring(0, line.length - 1)}');
          strings.add(cur.toString());
          cur = null;
        } else {
          cur!.write('\n$line');
        }
        return;
      }

      final t = line.trimLeft();
      if (t.startsWith('string "')) {
        final rest = t.substring(8);
        if (rest.endsWith('"')) {
          strings.add(rest.substring(0, rest.length - 1));
        } else {
          cur = StringBuffer(rest);
        }
      } else if (t.startsWith('array [')) {
        // Urutan argumen: app_name, (uint32 id), app_icon, summary, body, actions...
        if (strings.length >= 4) {
          onNotify(strings[0], strings[2], strings[3]);
        }
        inCall = false;
      }
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _proc?.kill();
    _proc = null;
  }
}
