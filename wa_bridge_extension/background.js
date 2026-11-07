// Menyambung ke island (ws://127.0.0.1:48721) dan meneruskan perintah kirim
// ke tab WhatsApp Web.
const URL_WS = 'ws://127.0.0.1:48721';
let ws = null;

function connect() {
  try {
    ws = new WebSocket(URL_WS);
  } catch (e) {
    setTimeout(connect, 3000);
    return;
  }
  ws.onmessage = async (ev) => {
    let m;
    try { m = JSON.parse(ev.data); } catch (_) { return; }
    if (m.type !== 'wa-send') return;
    let res;
    try {
      res = await sendToWa(m);
    } catch (e) {
      res = { ok: false, error: String(e) };
    }
    try { ws.send(JSON.stringify({ id: m.id, ...res })); } catch (_) {}
  };
  ws.onclose = () => setTimeout(connect, 3000);
  ws.onerror = () => { try { ws.close(); } catch (_) {} };
}

async function sendToWa(m) {
  const tabs = await browser.tabs.query({ url: '*://web.whatsapp.com/*' });
  if (!tabs.length) {
    return { ok: false, error: 'Tab WhatsApp Web tidak terbuka di Firefox.' };
  }
  try {
    return await browser.tabs.sendMessage(tabs[0].id, {
      type: 'send', chat: m.chat, text: m.text,
    });
  } catch (e) {
    return { ok: false, error: 'Muat ulang tab WhatsApp Web lalu coba lagi.' };
  }
}

connect();
