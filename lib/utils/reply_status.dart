import 'package:flutter/widgets.dart';

import '../services/reply_service.dart';
import 'tr.dart';

/// Teks status untuk hasil membalas pesan (dipakai panel & banner notifikasi).
String replyStatusText(BuildContext context, ReplyResult res) {
  return switch (res.outcome) {
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
}
