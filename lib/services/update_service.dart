import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Versi aplikasi ini. Samakan dengan `version:` di pubspec.yaml saat rilis.
const kAppVersion = '1.1.2';

/// Repositori GitHub tempat rilis diunggah.
const kRepo = 'AjarHer08/dynamic-island';

enum UpdateStatus { idle, checking, upToDate, available, noRelease, failed }

/// Memeriksa rilis terbaru di GitHub (https://github.com/AjarHer08/dynamic-island).
class UpdateService extends ChangeNotifier {
  UpdateStatus status = UpdateStatus.idle;
  String latest = '';
  String url = 'https://github.com/$kRepo/releases';
  DateTime? checkedAt;

  Timer? _timer;

  /// Periksa sekali beberapa detik setelah aplikasi jalan, lalu tiap 6 jam.
  void start(bool Function() enabled) {
    Future<void>.delayed(const Duration(seconds: 15), () {
      if (enabled()) check();
    });
    _timer ??= Timer.periodic(const Duration(hours: 6), (_) {
      if (enabled()) check();
    });
  }

  Future<void> check() async {
    if (status == UpdateStatus.checking) return;
    status = UpdateStatus.checking;
    notifyListeners();
    try {
      final res = await http.get(
        Uri.https('api.github.com', '/repos/$kRepo/releases/latest'),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'DynamicIsland/$kAppVersion',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 404) {
        status = UpdateStatus.noRelease; // repo/rilis belum ada
      } else if (res.statusCode == 200) {
        final j = jsonDecode(utf8.decode(res.bodyBytes));
        final tag = (j is Map ? j['tag_name'] : null)?.toString() ?? '';
        latest = tag.replaceFirst(RegExp(r'^[vV]'), '');
        final html = (j is Map ? j['html_url'] : null)?.toString();
        if (html != null && html.isNotEmpty) url = html;
        status = _newer(latest, kAppVersion)
            ? UpdateStatus.available
            : UpdateStatus.upToDate;
      } else {
        status = UpdateStatus.failed;
      }
    } catch (_) {
      status = UpdateStatus.failed;
    }
    checkedAt = DateTime.now();
    notifyListeners();
  }

  static List<int> _parts(String v) {
    final n = RegExp(r'\d+').allMatches(v).map((m) => int.parse(m.group(0)!)).toList();
    while (n.length < 3) {
      n.add(0);
    }
    return n;
  }

  static bool _newer(String a, String b) {
    final x = _parts(a), y = _parts(b);
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i] > y[i];
    }
    return false;
  }

  /// Buka halaman rilis di browser.
  Future<void> openRelease() async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
