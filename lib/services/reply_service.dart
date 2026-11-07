import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'reply_bridge.dart';

enum ReplyOutcome {
  /// Teks ditempel ke jendela aplikasi lalu Enter ditekan otomatis.
  sent,

  /// Teks ditempel ke jendela aplikasi; tinggal tekan Enter di sana.
  pasted,

  /// Teks hanya disalin ke clipboard (jendela aplikasi tidak ditemukan).
  copied,
}

class ReplyResult {
  const ReplyResult(this.outcome,
      {this.window = '',
      this.xdotoolMissing = false,
      this.tabMissing = false,
      this.error = ''});
  final ReplyOutcome outcome;

  /// Notifikasi berasal dari browser (mis. WhatsApp Web di Firefox), tetapi
  /// tab aplikasinya tidak ditemukan di jendela browser mana pun.
  final bool tabMissing;

  /// Pesan galat dari ekstensi browser (chat tidak ditemukan, dll.).
  final String error;

  /// Pola jendela yang cocok (untuk pesan status).
  final String window;
  final bool xdotoolMissing;
}

class _Run {
  const _Run(this.code, this.out);
  final int code;
  final String out;
}

/// Membalas pesan dari island.
///
/// Notifikasi desktop (WhatsApp Web, Telegram, LINE, ...) tidak menyediakan
/// API balasan yang bisa dipakai aplikasi lain, jadi caranya: teks balasan
/// disalin ke clipboard, jendela aplikasi tujuan dicari dan diaktifkan lewat
/// `xdotool`, lalu ditempel (Ctrl+V). Enter ditekan otomatis hanya bila
/// pengguna menyalakan "Kirim otomatis" di Settings.
class ReplyService {
  /// Kata kunci -> pola nama/kelas jendela. Urutan = prioritas.
  static const _apps = <_AppHint>[
    _AppHint(['whatsapp', 'web.whatsapp'], ['WhatsApp'], ['whatsapp', 'zapzap']),
    _AppHint(['telegram'], ['Telegram'], ['TelegramDesktop', 'telegram']),
    _AppHint(['line'], ['(^|[^[:alpha:]])LINE(\$|[^[:alpha:]])'], ['^line\$']),
    _AppHint(['discord'], ['Discord'], ['discord']),
    _AppHint(['signal'], ['Signal'], ['signal']),
    _AppHint(['messenger', 'facebook'], ['Messenger'], ['messenger']),
    _AppHint(['instagram'], ['Instagram'], ['instagram']),
    _AppHint(['slack'], ['Slack'], ['slack']),
    _AppHint(['teams'], ['Microsoft Teams'], ['teams']),
    _AppHint(['skype'], ['Skype'], ['skype']),
  ];

  static Future<_Run?> _run(String exe, List<String> args) async {
    try {
      final p = await Process.start(exe, args);
      p.stderr.drain<void>();
      final outF = p.stdout.transform(utf8.decoder).join();
      final code = await p.exitCode.timeout(const Duration(seconds: 4),
          onTimeout: () {
        p.kill();
        return -1;
      });
      final out = await outF.timeout(const Duration(seconds: 1),
          onTimeout: () => '');
      return _Run(code, out);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _hasXdotool() async {
    final r = await _run('which', ['xdotool']);
    return r != null && r.code == 0 && r.out.trim().isNotEmpty;
  }

  static _AppHint? _detect(String app, String sender, String body) {
    final hay = '$app $sender $body'.toLowerCase();
    for (final h in _apps) {
      for (final k in h.keywords) {
        if (k == 'line') {
          // "line" terlalu umum ("online", "deadline"): cocokkan kata utuh.
          if (RegExp(r'\bline\b').hasMatch(hay)) return h;
        } else if (hay.contains(k)) {
          return h;
        }
      }
    }
    return null;
  }

  static Future<String?> _search(String mode, String pattern) async {
    final r = await _run(
        'xdotool', ['search', '--onlyvisible', mode, pattern]);
    if (r == null || r.code != 0) return null;
    final ids = r.out
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return ids.isEmpty ? null : ids.last;
  }

  /// Cari jendela aplikasi tujuan: kelas -> judul (kata kunci app) -> judul
  /// (nama pengirim, hanya bila aplikasinya tidak dikenali).
  static Future<(String id, String label)?> _findWindow(
      String app, String sender, String body) async {
    final hint = _detect(app, sender, body);
    if (hint != null) {
      for (final c in hint.classes) {
        final id = await _search('--class', c);
        if (id != null) return (id, c);
      }
      for (final n in hint.names) {
        final id = await _search('--name', n);
        if (id != null) return (id, n);
      }
      return null;
    }
    final name = sender.trim();
    if (name.length >= 3) {
      final id = await _search('--name', RegExp.escape(name));
      if (id != null) return (id, name);
    }
    return null;
  }

  // -------------------------------------------------- Aplikasi web (browser)

  static const _browserWords = [
    'firefox', 'librewolf', 'chrome', 'chromium', 'brave', 'vivaldi',
    'opera', 'edge', 'zen',
  ];

  /// Kelas jendela (WM_CLASS) browser yang dicari.
  static const _browserClasses = [
    'firefox', 'navigator', 'librewolf', 'google-chrome', 'chromium',
    'brave', 'vivaldi', 'opera', 'microsoft-edge', 'zen',
  ];

  static bool _isBrowser(String app) {
    final a = app.toLowerCase();
    return _browserWords.any(a.contains);
  }

  static Future<String?> _activeWindow() async {
    final r = await _run('xdotool', ['getactivewindow']);
    final id = r?.out.trim() ?? '';
    return r != null && r.code == 0 && id.isNotEmpty ? id : null;
  }

  static Future<String> _windowName(String id) async {
    final r = await _run('xdotool', ['getwindowname', id]);
    return r == null || r.code != 0 ? '' : r.out.trim();
  }

  /// Semua jendela browser yang punya judul (tanpa --onlyvisible agar jendela
  /// yang diminimalkan tetap ketemu).
  static Future<List<(String id, String title)>> _browserWindows() async {
    final seen = <String>{};
    final out = <(String, String)>[];
    for (final c in _browserClasses) {
      final r = await _run('xdotool', ['search', '--class', c]);
      if (r == null || r.code != 0) continue;
      for (final id in r.out.split('\n').map((e) => e.trim())) {
        if (id.isEmpty || !seen.add(id)) continue;
        final title = await _windowName(id);
        if (title.isNotEmpty) out.add((id, title));
      }
    }
    return out;
  }

  /// Jendela browser memperlihatkan judul tab yang AKTIF saja. Jadi: cek judul
  /// semua jendela dulu; kalau tab tujuan tidak sedang aktif, aktifkan jendela
  /// browser lalu geser tab (Ctrl+PageDown) sampai judulnya cocok.
  static Future<(String id, String label, int steps)?> _findBrowserTab(
      List<RegExp> titles) async {
    final wins = await _browserWindows();
    if (wins.isEmpty) return null;
    bool match(String t) => titles.any((re) => re.hasMatch(t));

    for (final w in wins) {
      if (match(w.$2)) return (w.$1, w.$2, 0);
    }

    // Tab tujuan ada di latar belakang -> telusuri tab satu per satu.
    for (final w in wins) {
      final act = await _run('xdotool', ['windowactivate', '--sync', w.$1]);
      if (act == null || act.code != 0) continue;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final start = await _windowName(w.$1);
      if (match(start)) return (w.$1, start, 0);
      for (var i = 0; i < 40; i++) {
        await _run('xdotool', ['key', '--clearmodifiers', 'ctrl+Next']);
        await Future<void>.delayed(const Duration(milliseconds: 160));
        final t = await _windowName(w.$1);
        if (match(t)) return (w.$1, t, i + 1);
        if (t == start) break; // sudah satu putaran penuh
      }

    }
    return null;
  }

  /// WhatsApp Web membuka chat terakhir yang dipakai, belum tentu chat si
  /// pengirim. Pakai pencarian bawaan WA Web (Ctrl+Alt+/) untuk membuka chat
  /// yang benar; kolom tulis pesan otomatis terfokus setelahnya.
  static Future<void> _openWaChat(String sender) async {
    final name = sender.trim();
    if (name.isEmpty) return;
    await _run('xdotool', ['key', '--clearmodifiers', 'ctrl+alt+slash']);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _run('xdotool', ['type', '--clearmodifiers', '--delay', '20', '--', name]);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await _run('xdotool', ['key', '--clearmodifiers', 'Return']);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  /// Teks sudah ada di clipboard (diatur UI lewat Clipboard.setData).
  static Future<ReplyResult> pasteReply({
    required String app,
    required String sender,
    required String body,
    required bool autoSend,
    String text = '',
  }) async {
    // WhatsApp Web di browser: kirim langsung lewat ekstensi, tanpa membuka
    // jendela browser. Bila ekstensi tidak tersambung, pakai cara xdotool.
    if (_isBrowser(app) && text.isNotEmpty && ReplyBridge.connected) {
      final r = await ReplyBridge.sendWhatsApp(sender, text);
      if (r.ok) return const ReplyResult(ReplyOutcome.sent);
      if (r.connected) {
        return ReplyResult(ReplyOutcome.copied,
            error: r.error.isEmpty ? 'Gagal mengirim lewat ekstensi.' : r.error);
      }
    }

    if (!Platform.isLinux) return const ReplyResult(ReplyOutcome.copied);
    if (!await _hasXdotool()) {
      return const ReplyResult(ReplyOutcome.copied, xdotoolMissing: true);
    }

    final prev = await _activeWindow(); // jendela yang sedang dipakai pengguna
    var isWaWeb = false;
    var tabSteps = 0;
    (String, String)? w;
    if (_isBrowser(app)) {
      // Notifikasi dari browser = aplikasi web (WhatsApp Web, dll.).
      final hint = _detect('', sender, body);
      final titles = <RegExp>[
        RegExp('whatsapp', caseSensitive: false),
        if (hint != null && !hint.keywords.contains('whatsapp'))
          for (final n in hint.names) RegExp(n, caseSensitive: false),
      ];
      final tab = await _findBrowserTab(titles);
      if (tab == null) {
        return const ReplyResult(ReplyOutcome.copied, tabMissing: true);
      }
      w = (tab.$1, tab.$2);
      tabSteps = tab.$3;
      isWaWeb = RegExp('whatsapp', caseSensitive: false).hasMatch(tab.$2);
    } else {
      w = await _findWindow(app, sender, body);
      if (w == null) return const ReplyResult(ReplyOutcome.copied);
    }

    final act = await _run('xdotool', ['windowactivate', '--sync', w.$1]);
    if (act == null || act.code != 0) {
      return ReplyResult(ReplyOutcome.copied, window: w.$2);
    }
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (isWaWeb) await _openWaChat(sender);
    final paste =
        await _run('xdotool', ['key', '--clearmodifiers', 'ctrl+v']);
    if (paste == null || paste.code != 0) {
      return ReplyResult(ReplyOutcome.copied, window: w.$2);
    }

    // Balasan ke WA Web selalu langsung dikirim lalu fokus dikembalikan;
    // aplikasi lain mengikuti pengaturan "Kirim otomatis".
    final send = autoSend || isWaWeb;
    if (!send) return ReplyResult(ReplyOutcome.pasted, window: w.$2);

    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _run('xdotool', ['key', '--clearmodifiers', 'Return']);

    if (isWaWeb) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      // Kembalikan tab browser ke posisi semula, lalu jendela sebelumnya.
      for (var i = 0; i < tabSteps; i++) {
        await _run('xdotool', ['key', '--clearmodifiers', 'ctrl+Prior']);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (prev != null && prev != w.$1) {
        await _run('xdotool', ['windowactivate', prev]);
      }
    }
    return ReplyResult(ReplyOutcome.sent, window: w.$2);
  }
}

class _AppHint {
  const _AppHint(this.keywords, this.names, this.classes);
  final List<String> keywords, names, classes;
}
