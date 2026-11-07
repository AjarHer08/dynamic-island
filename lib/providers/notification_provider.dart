import 'dart:async';
import 'package:flutter/material.dart';

enum NotifKind { message, alarm, rest, water }

extension NotifKindStyle on NotifKind {
  IconData get icon => switch (this) {
        NotifKind.message => Icons.chat_bubble,
        NotifKind.alarm => Icons.alarm,
        NotifKind.rest => Icons.self_improvement,
        NotifKind.water => Icons.water_drop,
      };

  Color get color => switch (this) {
        NotifKind.message => const Color(0xFF25D366),
        NotifKind.alarm => const Color(0xFFFF9F0A),
        NotifKind.rest => const Color(0xFFBF5AF2),
        NotifKind.water => const Color(0xFF64D2FF),
      };
}

class AppNotification {
  final String id, sender, body, app;
  final NotifKind kind;
  final DateTime time;
  bool read;

  /// Teks balasan terakhir yang dikirim dari island (null = belum dibalas).
  String? replied;
  AppNotification({
    required this.id,
    required this.sender,
    required this.body,
    required this.time,
    this.app = '',
    this.kind = NotifKind.message,
    this.read = false,
  });
}

class NotificationProvider extends ChangeNotifier {
  final List<AppNotification> _queue = [];
  AppNotification? _active;
  Timer? _autoDismiss;
  String? _replyRequest;

  List<AppNotification> get queue => List.unmodifiable(_queue);
  AppNotification? get active => _active;

  /// [silent] = masuk daftar tanpa muncul di pill (dipakai saat DND).
  void push({
    required String sender,
    required String body,
    String app = '',
    NotifKind kind = NotifKind.message,
    bool silent = false,
    Duration showFor = const Duration(seconds: 5),
  }) {
    final n = AppNotification(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      sender: sender,
      body: body,
      app: app,
      kind: kind,
      time: DateTime.now(),
    );
    _queue.insert(0, n);
    if (_queue.length > 50) _queue.removeLast();
    if (silent) {
      notifyListeners();
    } else {
      _show(n, showFor);
    }
  }

  void _show(AppNotification n, Duration showFor) {
    _autoDismiss?.cancel();
    _active = n;
    notifyListeners();
    _autoDismiss = Timer(showFor, () {
      _active = null;
      notifyListeners();
    });
  }

  /// Pill diketuk saat ada pesan masuk: panel Notifikasi langsung membuka
  /// kolom balas untuk pesan itu.
  void requestReply(String id) {
    _replyRequest = id;
  }

  String? takeReplyRequest() {
    final id = _replyRequest;
    _replyRequest = null;
    return id;
  }

  void markReplied(String id, String text) {
    for (final n in _queue) {
      if (n.id == id) n.replied = text;
    }
    notifyListeners();
  }

  void dismiss() {
    _autoDismiss?.cancel();
    _active = null;
    notifyListeners();
  }

  void clear() {
    _queue.clear();
    dismiss();
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }
}
