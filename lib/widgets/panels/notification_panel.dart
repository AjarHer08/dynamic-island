import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/notification_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/reply_service.dart';
import '../../theme/island_theme.dart';
import '../liquid_glass.dart';
import '../../utils/tr.dart';
import '../live_clock.dart';

class NotificationPanel extends StatefulWidget {
  const NotificationPanel({super.key});

  @override
  State<NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<NotificationPanel> {
  final _ctrl = TextEditingController();
  String? _replyId; // pesan yang sedang dibalas
  bool _sending = false;
  bool _focusReply = false; // fokus otomatis hanya saat dibuka oleh pengguna
  String? _status;

  @override
  void initState() {
    super.initState();
    // Pill diketuk saat ada pesan baru -> langsung buka kolom balas pesan itu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notif = context.read<NotificationProvider>();
      final id = notif.takeReplyRequest();
      if (id != null) {
        _openReply(id);
      } else {
        // Seperti gambar referensi: kolom balas pesan terbaru langsung terbuka.
        final msgs = notif.queue.where((e) => e.kind == NotifKind.message);
        if (msgs.isNotEmpty) setState(() => _replyId = msgs.first.id);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _openReply(String id) {
    setState(() {
      _focusReply = true;
      _replyId = _replyId == id ? null : id;
      _ctrl.clear();
      _status = null;
    });
  }

  Future<void> _send(AppNotification n) async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final notif = context.read<NotificationProvider>();
    final autoSend = context.read<SettingsProvider>().replyAutoSend;
    setState(() {
      _sending = true;
      _status = null;
    });

    await Clipboard.setData(ClipboardData(text: text));
    final res = await ReplyService.pasteReply(
      app: n.app,
      sender: n.sender,
      body: n.body,
      autoSend: autoSend,
      text: text,
    );
    // Provider tetap hidup walau island sempat menutup (jendela aplikasi
    // tujuan mengambil fokus), jadi riwayat balasan tidak hilang.
    notif.markReplied(n.id, text);
    if (!mounted) return;

    final msg = switch (res.outcome) {
      ReplyOutcome.sent => tr(context, 'Terkirim.', 'Sent.'),
      ReplyOutcome.pasted => tr(
          context,
          'Sudah ditempel di aplikasi. Tekan Enter di sana untuk mengirim.',
          'Pasted into the app. Press Enter there to send.'),
      ReplyOutcome.copied => res.error.isNotEmpty
          ? '${res.error} ${tr(context, 'Teks disalin; tempel manual (Ctrl+V).', 'Text copied; paste manually (Ctrl+V).')}'
          : res.xdotoolMissing
          ? tr(
              context,
              'Teks disalin. Pasang xdotool agar otomatis: sudo apt install xdotool',
              'Text copied. Install xdotool for auto-paste: sudo apt install xdotool')
          : res.tabMissing
          ? tr(
              context,
              'Teks disalin. Tab WhatsApp Web tidak ditemukan di browser; buka web.whatsapp.com lalu tempel (Ctrl+V).',
              'Text copied. WhatsApp Web tab not found in the browser; open web.whatsapp.com and paste (Ctrl+V).')
          : tr(
              context,
              'Teks disalin. Aplikasinya tidak ditemukan; buka chat-nya lalu tempel (Ctrl+V).',
              'Text copied. App window not found; open the chat and paste (Ctrl+V).'),
    };
    setState(() {
      _sending = false;
      _status = msg;
      if (res.outcome == ReplyOutcome.sent) _replyId = null;
    });
  }

  List<String> _quick(BuildContext context) => [
        tr(context, 'Oke', 'OK'),
        tr(context, 'Siap', 'On it'),
        tr(context, 'Nanti ya', 'Talk later'),
        tr(context, 'Lagi sibuk', 'Busy right now'),
      ];

  Widget _replyBox(AppNotification n, IslandTheme t) {
    final quick = _quick(context);
    final onAccent =
        t.accentColor.computeLuminance() > 0.6 ? Colors.black87 : Colors.white;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c, width: 1));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              autofocus: _focusReply,
              enabled: !_sending,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              cursorColor: t.accentColor,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(n),
              decoration: InputDecoration(
                hintText: tr(context, 'Ketik balasan...', 'Type a reply...'),
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                isDense: true,
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.25),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                border: border(Colors.white.withValues(alpha: 0.12)),
                enabledBorder: border(Colors.white.withValues(alpha: 0.12)),
                focusedBorder: border(t.accentColor.withValues(alpha: 0.7)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _send(n),
            child: Container(
              width: 46,
              height: 40,
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
                      padding: const EdgeInsets.all(11),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: onAccent))
                  : Icon(Icons.send, size: 19, color: onAccent),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          for (var i = 0; i < quick.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  _ctrl.text = quick[i];
                  _ctrl.selection =
                      TextSelection.collapsed(offset: quick[i].length);
                },
                child: Container(
                  height: 34,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16), width: 1),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(quick[i],
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12.5)),
                  ),
                ),
              ),
            ),
          ],
        ]),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status!,
                style: t.subtitleStyle
                    .copyWith(fontSize: 10, color: Colors.orangeAccent)),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notif = context.watch<NotificationProvider>();
    final settings = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;
    final t = settings.theme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notif.queue.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: 4),
              child: Row(children: [
                const Spacer(),
                Text('${notif.queue.length}',
                    style: t.subtitleStyle.copyWith(color: t.accentColor)),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: notif.clear,
                  child: Text(l10n.clearAll,
                      style: t.subtitleStyle.copyWith(fontSize: 10)),
                ),
              ]),
            ),
          Expanded(
            child: notif.queue.isEmpty
                ? Center(child: Text(l10n.noNotifications, style: t.subtitleStyle))
                : ListView.separated(
                    itemCount: notif.queue.length > 12 ? 12 : notif.queue.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final n = notif.queue[i];
                      final isMsg = n.kind == NotifKind.message;
                      final initial =
                          n.sender.isEmpty ? '?' : n.sender[0].toUpperCase();
                      return Container(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        decoration: cardDecoration(t, radius: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: n.kind.color,
                                    child: isMsg
                                        ? Text(initial,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w500))
                                        : Icon(n.kind.icon,
                                            size: 20, color: Colors.white),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(n.sender,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                        const SizedBox(height: 2),
                                        Text(n.body,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                height: 1.3),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis),
                                        if (n.app.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(n.app,
                                              style: t.subtitleStyle
                                                  .copyWith(fontSize: 12),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                            '${twoDigits(n.time.hour)}:${twoDigits(n.time.minute)}',
                                            style: t.subtitleStyle
                                                .copyWith(fontSize: 11)),
                                        if (isMsg) ...[
                                          const SizedBox(height: 8),
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () => _openReply(n.id),
                                            child: Container(
                                              width: 38,
                                              height: 38,
                                              decoration: BoxDecoration(
                                                color: _replyId == n.id
                                                    ? t.accentColor
                                                        .withValues(alpha: 0.22)
                                                    : Colors.white
                                                        .withValues(alpha: 0.07),
                                                borderRadius:
                                                    BorderRadius.circular(11),
                                                border: Border.all(
                                                    color: _replyId == n.id
                                                        ? t.accentColor
                                                            .withValues(alpha: 0.6)
                                                        : Colors.white
                                                            .withValues(alpha: 0.18)),
                                              ),
                                              child: const Icon(Icons.reply,
                                                  size: 20, color: Colors.white),
                                            ),
                                          ),
                                        ],
                                      ]),
                                ]),
                            if (n.replied != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6, left: 56),
                                child: Row(children: [
                                  Icon(Icons.subdirectory_arrow_right,
                                      size: 12, color: t.accentColor),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(n.replied!,
                                        style: t.subtitleStyle.copyWith(
                                            fontSize: 10,
                                            color: t.accentColor),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ]),
                              ),
                            if (isMsg && _replyId == n.id) _replyBox(n, t),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
