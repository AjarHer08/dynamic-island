import 'dart:async';
import 'dart:convert';
import 'dart:io';

class BridgeResult {
  const BridgeResult({required this.connected, this.ok = false, this.error = ''});

  /// Ekstensi browser tersambung ke island.
  final bool connected;
  final bool ok;
  final String error;
}

/// Jembatan lokal ke ekstensi "Dynamic Island WA Bridge" di Firefox.
///
/// Island membuka server WebSocket di 127.0.0.1 (hanya menerima koneksi dari
/// ekstensi browser). Balasan WhatsApp Web dikirim ke ekstensi, yang
/// membuka chat dan mengirim pesan langsung di tab WA Web, tanpa memindahkan
/// fokus atau membuka jendela browser.
class ReplyBridge {
  static const port = 48721;
  static HttpServer? _server;
  static final _clients = <WebSocket>[];
  static final _pending = <int, Completer<Map<String, dynamic>>>{};
  static int _seq = 0;

  static bool get connected => _clients.isNotEmpty;

  static Future<void> start() async {
    if (_server != null) return;
    try {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      _server = s;
      s.listen((req) async {
        try {
          final origin = req.headers.value('origin') ?? '';
          if (!origin.startsWith('moz-extension://') ||
              !WebSocketTransformer.isUpgradeRequest(req)) {
            req.response.statusCode = HttpStatus.forbidden;
            await req.response.close();
            return;
          }
          final ws = await WebSocketTransformer.upgrade(req);
          _clients.add(ws);
          ws.listen(
            (data) {
              try {
                final m = jsonDecode(data as String);
                if (m is Map<String, dynamic>) {
                  _pending.remove(m['id'])?.complete(m);
                }
              } catch (_) {}
            },
            onDone: () => _clients.remove(ws),
            onError: (_) => _clients.remove(ws),
            cancelOnError: true,
          );
        } catch (_) {}
      });
    } catch (_) {
      // Port dipakai instance lain: abaikan, balasan jatuh ke cara lama.
    }
  }

  /// Kirim [text] ke chat bernama [chat] di WhatsApp Web.
  static Future<BridgeResult> sendWhatsApp(String chat, String text) async {
    if (_clients.isEmpty) return const BridgeResult(connected: false);
    final id = ++_seq;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    final msg = jsonEncode({'id': id, 'type': 'wa-send', 'chat': chat, 'text': text});
    for (final ws in List.of(_clients)) {
      ws.add(msg);
    }
    try {
      final r = await c.future.timeout(const Duration(seconds: 20));
      return BridgeResult(
        connected: true,
        ok: r['ok'] == true,
        error: (r['error'] ?? '').toString(),
      );
    } on TimeoutException {
      _pending.remove(id);
      return const BridgeResult(
          connected: true, error: 'Ekstensi tidak merespons (timeout).');
    }
  }
}
