import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/notification_provider.dart';
import '../providers/settings_provider.dart';
import '../services/reply_service.dart';
import '../theme/island_theme.dart';
import '../utils/reply_status.dart';
import '../utils/tr.dart';

/// Notifikasi pesan di island dengan kolom balas langsung (seperti notifikasi
/// WhatsApp Desktop): ketik, tekan Enter / tombol kirim, selesai.
/// Selama kolom balas dipakai, notifikasi tidak menutup sendiri.
class MessageBanner extends StatefulWidget {
  const MessageBanner(
      {super.key, required this.n, required this.t, required this.onOpen});

  final AppNotification n;
  final IslandTheme t;

  /// Ketuk bagian atas banner: buka island penuh di tab Notifikasi.
  final VoidCallback onOpen;

  @override
  State<MessageBanner> createState() => _MessageBannerState();
}

class _MessageBannerState extends State<MessageBanner> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false, _sent = false;
  String? _status;
  late final NotificationProvider _notif;

  @override
  void initState() {
    super.initState();
    _notif = context.read<NotificationProvider>();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _notif.hold();
    } else if (!_sending) {
      _notif.release(Duration(seconds: _ctrl.text.trim().isEmpty ? 3 : 12));
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final n = widget.n;
    final autoSend = context.read<SettingsProvider>().replyAutoSend;
    setState(() {
      _sending = true;
      _status = null;
    });
    _notif.hold();

    await Clipboard.setData(ClipboardData(text: text));
    final res = await ReplyService.pasteReply(
      app: n.app,
      sender: n.sender,
      body: n.body,
      autoSend: autoSend,
      text: text,
    );
    _notif.markReplied(n.id, text);
    if (!mounted) return;

    if (res.outcome == ReplyOutcome.sent) {
      setState(() {
        _sending = false;
        _sent = true;
      });
      _ctrl.clear();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (_notif.active?.id == n.id) _notif.dismiss();
      return;
    }
    setState(() {
      _sending = false;
      _status = replyStatusText(context, res);
    });
    _notif.release(const Duration(seconds: 14));
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.n;
    final t = widget.t;
    final onAccent =
        t.accentColor.computeLuminance() > 0.6 ? Colors.black87 : Colors.white;
    final initial = n.sender.isEmpty
        ? '?'
        : String.fromCharCode(n.sender.runes.first).toUpperCase();
    OutlineInputBorder border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c, width: 1));

    final line2 = _sent
        ? tr(context, 'Terkirim', 'Sent')
        : (_status ?? n.body);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(
          height: 42,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpen,
            child: Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: n.kind.color,
                child: Text(initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        n.app.isEmpty ? n.sender : '${n.sender}  ·  ${n.app}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                    Text(line2,
                        maxLines: _status != null ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: _status != null
                                ? Colors.orangeAccent
                                : (_sent ? t.accentColor : Colors.white70),
                            fontSize: _status != null ? 10 : 12,
                            height: 1.2)),
                  ],
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _notif.dismiss,
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.close, size: 16, color: Colors.white38),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                enabled: !_sending,
                // Island tidak otomatis menerima fokus keyboard: minta manual.
                onTap: () => unawaited(windowManager.focus()),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                cursorColor: t.accentColor,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: tr(context, 'Balas ${n.sender}...',
                      'Reply to ${n.sender}...'),
                  hintStyle:
                      const TextStyle(color: Colors.white38, fontSize: 13),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.25),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  border: border(Colors.white.withValues(alpha: 0.12)),
                  enabledBorder: border(Colors.white.withValues(alpha: 0.12)),
                  disabledBorder: border(Colors.white.withValues(alpha: 0.08)),
                  focusedBorder: border(t.accentColor.withValues(alpha: 0.7)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 44,
                height: 38,
                decoration: BoxDecoration(
                  color: t.accentColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: t.accentColor.withValues(alpha: 0.35),
                        blurRadius: 8)
                  ],
                ),
                child: _sending
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: onAccent))
                    : Icon(_sent ? Icons.check : Icons.send,
                        size: 18, color: onAccent),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
