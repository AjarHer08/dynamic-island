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
  String? _status;

  @override
  void initState() {
    super.initState();
    // Pill diketuk saat ada pesan baru -> langsung buka kolom balas pesan itu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final id = context.read<NotificationProvider>().takeReplyRequest();
      if (id != null) _openReply(id);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _openReply(String id) {
    setState(() {
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
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              enabled: !_sending,
              style: t.titleStyle.copyWith(fontSize: 12),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(n),
              decoration: InputDecoration(
                hintText: tr(context, 'Balas ${n.sender}...',
                    'Reply to ${n.sender}...'),
                hintStyle: t.subtitleStyle,
                isDense: true,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _send(n),
            child: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.send, size: 18, color: t.accentColor),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final q in _quick(context))
            GestureDetector(
              onTap: () {
                _ctrl.text = q;
                _ctrl.selection = TextSelection.collapsed(offset: q.length);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(q,
                    style: const TextStyle(color: Colors.white70, fontSize: 10)),
              ),
            ),
        ]),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.notifications_active, size: 14, color: t.accentColor),
            const SizedBox(width: 6),
            Text(l10n.notifications,
                style: t.subtitleStyle.copyWith(letterSpacing: 1)),
            const Spacer(),
            if (notif.queue.isNotEmpty) ...[
              Text('${notif.queue.length}',
                  style: t.subtitleStyle.copyWith(color: t.accentColor)),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: notif.clear,
                child: Text(l10n.clearAll,
                    style: t.subtitleStyle.copyWith(fontSize: 10)),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          Expanded(
            child: notif.queue.isEmpty
                ? Center(child: Text(l10n.noNotifications, style: t.subtitleStyle))
                : ListView.separated(
                    itemCount: notif.queue.length > 12 ? 12 : notif.queue.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final n = notif.queue[i];
                      final isMsg = n.kind == NotifKind.message;
                      final initial =
                          n.sender.isEmpty ? '?' : n.sender[0].toUpperCase();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: cardDecoration(t, radius: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: n.kind.color,
                                child: isMsg
                                    ? Text(initial,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold))
                                    : Icon(n.kind.icon,
                                        size: 14, color: Colors.white),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        n.app.isEmpty
                                            ? n.sender
                                            : '${n.sender}  ·  ${n.app}',
                                        style:
                                            t.titleStyle.copyWith(fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    Text(n.body,
                                        style: t.subtitleStyle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                  '${twoDigits(n.time.hour)}:${twoDigits(n.time.minute)}',
                                  style: t.subtitleStyle.copyWith(fontSize: 9)),
                              if (isMsg) ...[
                                const SizedBox(width: 8),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _openReply(n.id),
                                  child: Icon(Icons.reply,
                                      size: 18,
                                      color: _replyId == n.id
                                          ? t.accentColor
                                          : Colors.white54),
                                ),
                              ],
                            ]),
                            if (n.replied != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6, left: 36),
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
