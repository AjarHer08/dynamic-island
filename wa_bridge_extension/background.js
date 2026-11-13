// Menyambung ke island (ws://127.0.0.1:48721): meneruskan perintah kirim pesan
// dan terima/tolak panggilan ke tab WhatsApp Web, serta melaporkan panggilan
// masuk dari tab itu ke island.
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
    let res;
    try {
      if (m.type === 'wa-send') {
        res = await sendToWa(m);
      } else if (m.type === 'wa-call-action') {
        res = await callActionToWa(m.action);
      } else {
        return;
      }
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

// Coba semua tab WA Web: panggilan bisa berdering di tab mana pun.
async function callActionToWa(action) {
  const tabs = await browser.tabs.query({ url: '*://web.whatsapp.com/*' });
  if (!tabs.length) {
    return { ok: false, error: 'Tab WhatsApp Web tidak terbuka di Firefox.' };
  }
  let last = { ok: false, error: 'Panggilan tidak ditemukan di WhatsApp Web.' };
  for (const tab of tabs) {
    try {
      const r = await browser.tabs.sendMessage(tab.id, { type: 'call-action', action });
      if (r && r.ok) return r;
      if (r && r.error) last = r;
    } catch (e) {
      last = { ok: false, error: 'Muat ulang tab WhatsApp Web lalu coba lagi.' };
    }
  }
  return last;
}

// Laporan panggilan masuk dari content script -> island.
browser.runtime.onMessage.addListener((msg) => {
  if (msg && msg.type === 'wa-call' && ws && ws.readyState === 1) {
    try { ws.send(JSON.stringify(msg)); } catch (_) {}
  }
});

connect();
