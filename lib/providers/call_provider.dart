import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/call_service.dart';
import '../services/reply_bridge.dart';

enum CallPhase { ringing, answered, rejected }

class IncomingCall {
  IncomingCall({
    required this.id,
    required this.caller,
    required this.app,
    required this.video,
    required this.viaBridge,
  }) : started = DateTime.now();

  final String id;
  String caller;
  String app;
  bool video;

  /// Terdeteksi oleh ekstensi WhatsApp Web, jadi bisa diterima/ditolak
  /// langsung dari island.
  bool viaBridge;
  final DateTime started;
}

/// Panggilan masuk di island: tampil banner dengan tombol Terima / Tolak.
///
/// Sumber panggilan:
///  * Ekstensi WA Bridge (WhatsApp Web di Firefox): terima/tolak benar-benar
///    menekan tombolnya di WhatsApp Web.
///  * Notifikasi desktop aplikasi lain (Telegram, Discord, Signal, ...):
///    aplikasi tidak menyediakan kendali dari luar, jadi "Terima" membuka
///    jendela aplikasinya dan "Tolak" menutup banner di island saja.
class CallProvider extends ChangeNotifier {
  static const _ringTimeout = Duration(seconds: 60);

  IncomingCall? _call;
  CallPhase _phase = CallPhase.ringing;
  bool _busy = false;
  String _note = '';
  Timer? _timeout, _clear;

  /// Dicatat ke riwayat notifikasi. event: incoming | ended | accepted |
  /// rejected | dismissed.
  void Function(String caller, String app, String event)? onLog;

  IncomingCall? get call => _call;
  CallPhase get phase => _phase;
  bool get busy => _busy;

  /// Kode hasil: answered | opened | unsupported | rejected | dismissed,
  /// atau pesan galat mentah dari ekstensi.
  String get note => _note;

  // ---------------------------------------------------------- Deteksi teks

  static final _callRe = RegExp(
      r'(incoming\s+(whatsapp\s+)?(voice\s+|video\s+|group\s+)?call|'
      r'(voice|video)\s+call\s+from|calling\s+you|is\s+calling|'
      r'panggilan\s+(suara\s+|video\s+|grup\s+|whatsapp\s+)?masuk|'
      r'panggilan\s+(suara|video)\s+dari|'
      r'menelepon\s+(anda|kamu)|sedang\s+memanggil|memanggil\s+(anda|kamu))',
      caseSensitive: false);
  static final _missedRe = RegExp(
      r'(missed|tak\s+terjawab|tidak\s+terjawab|terlewat|declined|ditolak|ended|berakhir)',
      caseSensitive: false);

  /// Notifikasi desktop ini panggilan masuk yang sedang berdering?
  static bool looksLikeCall(String summary, String body) {
    final text = '$summary\n$body';
    if (body.length > 100 || _missedRe.hasMatch(text)) return false;
    return _callRe.hasMatch(text);
  }

  static bool looksLikeVideo(String summary, String body) =>
      RegExp('video', caseSensitive: false).hasMatch('$summary $body');

  /// Nama penelepon dari teks notifikasi ("Incoming call from Budi", dll.).
  static String callerFrom(String app, String summary, String body) {
    final m = RegExp(r'(?:from|dari)\s+(.+)$', caseSensitive: false)
        .firstMatch(body.trim().split('\n').first);
    if (m != null && m.group(1)!.trim().isNotEmpty) return m.group(1)!.trim();
    final s = summary.trim();
    final sl = s.toLowerCase();
    final generic = s.isEmpty ||
        sl == app.toLowerCase() ||
        sl == 'whatsapp' ||
        _callRe.hasMatch(s);
    if (!generic) return s;
    final first = body.trim().split('\n').first.trim();
    if (first.isNotEmpty && !_callRe.hasMatch(first)) return first;
    return s.isEmpty ? app : s;
  }

  // ------------------------------------------------------------- Kejadian

  void onIncoming({
    required String caller,
    required String app,
    bool video = false,
    bool bridge = false,
    bool silent = false,
  }) {
    if (silent) {
      onLog?.call(caller, app, 'incoming'); // DND: hanya masuk riwayat
      return;
    }
    final c = _call;
    if (c != null) {
      if (_phase != CallPhase.ringing) return;
      // Notifikasi desktop + ekstensi bisa melaporkan dering yang sama.
      final dup = (bridge != c.viaBridge &&
              DateTime.now().difference(c.started) <
                  const Duration(seconds: 25)) ||
          (c.app.toLowerCase() == app.toLowerCase() && c.caller == caller);
      if (dup) {
        if (bridge) {
          c.viaBridge = true;
          c.app = 'WhatsApp';
          if (caller.isNotEmpty && caller.toLowerCase() != 'whatsapp') {
            c.caller = caller;
          }
        }
        c.video = c.video || video;
        _arm();
        notifyListeners();
      }
      return;
    }
    _clear?.cancel();
    _call = IncomingCall(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      caller: caller.isEmpty ? app : caller,
      app: bridge ? 'WhatsApp' : app,
      video: video,
      viaBridge: bridge,
    );
    _phase = CallPhase.ringing;
    _busy = false;
    _note = '';
    _arm();
    notifyListeners();
  }

  /// Dering berhenti (dijawab di perangkat lain, ditutup penelepon, dll.).
  void onEnded() {
    final c = _call;
    if (c == null || _phase != CallPhase.ringing) return;
    onLog?.call(c.caller, c.app, 'ended');
    _finish();
  }

  void _arm() {
    _timeout?.cancel();
    _timeout = Timer(_ringTimeout, onEnded);
  }

  bool _isWhatsApp(IncomingCall c) =>
      c.viaBridge || c.app.toLowerCase().contains('whatsapp');

  Future<void> accept() async {
    final c = _call;
    if (c == null || _busy || _phase != CallPhase.ringing) return;
    _busy = true;
    notifyListeners();

    var note = '';
    var ok = false;
    if (_isWhatsApp(c) && ReplyBridge.connected) {
      final r = await ReplyBridge.callAction('accept');
      ok = r.ok;
      if (!ok) note = r.error;
    }
    if (ok) {
      note = 'answered';
    } else {
      final opened = await CallService.activateApp(c.app);
      if (opened) {
        note = 'opened';
      } else if (note.isEmpty) {
        note = 'unsupported';
      }
    }
    _timeout?.cancel();
    onLog?.call(c.caller, c.app, ok ? 'accepted' : 'dismissed');
    _settle(CallPhase.answered, note, const Duration(milliseconds: 2600));
  }

  Future<void> reject() async {
    final c = _call;
    if (c == null || _busy || _phase != CallPhase.ringing) return;
    _busy = true;
    notifyListeners();

    var ok = false;
    var note = '';
    if (_isWhatsApp(c) && ReplyBridge.connected) {
      final r = await ReplyBridge.callAction('reject');
      ok = r.ok;
      if (!ok) note = r.error;
    }
    _timeout?.cancel();
    onLog?.call(c.caller, c.app, ok ? 'rejected' : 'dismissed');
    _settle(CallPhase.rejected, ok ? 'rejected' : (note.isEmpty ? 'dismissed' : note),
        const Duration(milliseconds: 2200));
  }

  void _settle(CallPhase phase, String note, Duration hold) {
    _busy = false;
    _phase = phase;
    _note = note;
    notifyListeners();
    _clear?.cancel();
    _clear = Timer(hold, _finish);
  }

  void _finish() {
    _timeout?.cancel();
    _clear?.cancel();
    _call = null;
    _phase = CallPhase.ringing;
    _busy = false;
    _note = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _clear?.cancel();
    super.dispose();
  }
}
