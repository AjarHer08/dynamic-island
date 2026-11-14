// Berjalan di dalam tab WhatsApp Web: buka chat lalu kirim pesan lewat DOM.
// Tidak butuh fokus jendela/tab, jadi bisa jalan saat tab di latar belakang.
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const norm = (s) => (s || '').trim().toLowerCase();

async function waitFor(fn, timeout = 6000, step = 150) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    const v = fn();
    if (v) return v;
    await sleep(step);
  }
  return null;
}

function click(el) {
  const t = el.closest('[role="listitem"], [role="row"], [role="gridcell"]') || el;
  for (const type of ['mousedown', 'mouseup', 'click']) {
    t.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, view: window }));
  }
}

// Cocokkan nama chat hanya dari huruf/angka: emoji, spasi ganda, dan karakter
// tak terlihat sering berbeda antara judul notifikasi dan daftar chat.
const letters = (s) =>
  (s || '').normalize('NFKC').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '');
function sameChat(a, b) {
  const x = letters(a), y = letters(b);
  if (!x || !y) return norm(a) === norm(b); // nama berisi emoji saja
  return x === y;
}
function looseChat(a, b) {
  const x = letters(a), y = letters(b);
  return !!x && !!y && (x.includes(y) || y.includes(x));
}
// Teks untuk kolom cari: tanpa emoji supaya hasil pencarian cocok.
function searchText(name) {
  const t = (name || '')
    .normalize('NFKC')
    .replace(/[^\p{L}\p{N}\s]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return t || (name || '').trim();
}

function chatItems() {
  const pane = document.querySelector('#pane-side') || document.querySelector('#side');
  if (!pane) return [];
  const out = [];
  for (const row of pane.querySelectorAll('[role="listitem"], [role="row"], [role="gridcell"]')) {
    const t = row.querySelector('span[title]');
    const title =
      (t && t.getAttribute('title')) ||
      ((row.querySelector('span[dir="auto"]') || {}).textContent || '');
    if (title) out.push({ el: row, title });
  }
  if (!out.length) {
    for (const s of pane.querySelectorAll('span[title]')) {
      out.push({ el: s, title: s.getAttribute('title') });
    }
  }
  return out;
}

function chatInList(name) {
  const items = chatItems();
  const hit = items.find((i) => sameChat(i.title, name)) ||
    items.find((i) => looseChat(i.title, name));
  return hit ? hit.el : null;
}

function openChatTitle() {
  const el =
    document.querySelector('#main header span[title]') ||
    document.querySelector('#main header span[dir="auto"]');
  return el ? el.getAttribute('title') || el.textContent || '' : '';
}

function chatIsOpen(name) {
  const t = openChatTitle();
  return !!t && (sameChat(t, name) || looseChat(t, name));
}

const searchBox = () =>
  document.querySelector('#side [contenteditable="true"][data-tab="3"]') ||
  document.querySelector('#side div[role="textbox"][contenteditable="true"]') ||
  document.querySelector('#side [contenteditable="true"]') ||
  document.querySelector(
    '[contenteditable="true"][aria-label*="Cari" i], [contenteditable="true"][aria-label*="Search" i]');
const composer = () =>
  document.querySelector('#main footer [contenteditable="true"]') ||
  document.querySelector('footer [contenteditable="true"][data-tab="10"]');

function setText(el, text) {
  el.focus();
  const sel = window.getSelection();
  const range = document.createRange();
  range.selectNodeContents(el);
  sel.removeAllRanges();
  sel.addRange(range);
  document.execCommand('delete');
  if (text) document.execCommand('insertText', false, text);
}

let lastDiag = '';

// Cadangan bila kolom cari belum ada di DOM: pakai pintasan Ctrl+Alt+/ WhatsApp Web.
async function openSearchByShortcut() {
  const ev = {
    key: '/', code: 'Slash', keyCode: 191, which: 191,
    ctrlKey: true, altKey: true, bubbles: true, cancelable: true,
  };
  document.dispatchEvent(new KeyboardEvent('keydown', ev));
  return await waitFor(searchBox, 1500);
}

async function openChat(name) {
  lastDiag = '';
  if (chatIsOpen(name)) return true;

  let item = chatInList(name);
  if (!item) {
    const box = searchBox() || (await openSearchByShortcut());
    if (!box) {
      lastDiag = 'kolom cari WhatsApp Web tidak ditemukan';
      return false;
    }
    const q = searchText(name);
    setText(box, q);
    item = await waitFor(() => chatInList(name), 6000);
    if (!item) {
      const seen = chatItems().slice(0, 4).map((i) => i.title).join(' | ');
      lastDiag = `dicari "${q}", yang terlihat: ${seen || 'tidak ada'}`;
      setText(box, '');
      return false;
    }
  }
  click(item);
  const ok = await waitFor(() => chatIsOpen(name), 5000);
  if (!ok) lastDiag = `chat diklik tetapi yang terbuka: "${openChatTitle()}"`;
  const box = searchBox();
  if (box && box.textContent) setText(box, '');
  return !!ok;
}

async function sendText(text) {
  const box = await waitFor(composer, 5000);
  if (!box) return false;
  setText(box, text);
  await sleep(250);
  const btn =
    document.querySelector('#main footer button[aria-label="Kirim"]') ||
    document.querySelector('#main footer button[aria-label="Send"]') ||
    (document.querySelector('#main footer span[data-icon="send"]') || {}).closest?.('button');
  if (btn) {
    btn.click();
  } else {
    const ev = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
    box.dispatchEvent(new KeyboardEvent('keydown', ev));
    box.dispatchEvent(new KeyboardEvent('keyup', ev));
  }
  // Berhasil bila kolom tulis kosong lagi.
  return !!(await waitFor(() => (composer() ? !composer().textContent.trim() : false), 4000));
}

async function handleSend({ chat, text }) {
  if (!document.querySelector('#pane-side')) {
    return { ok: false, error: 'WhatsApp Web belum siap (belum login / masih memuat).' };
  }
  if (!(await openChat(chat))) {
    return {
      ok: false,
      error: `Chat "${chat}" tidak ditemukan di WhatsApp Web${lastDiag ? ` (${lastDiag})` : ''}.`,
    };
  }
  if (!(await sendText(text))) {
    return { ok: false, error: 'Pesan tidak terkirim (kolom tulis tidak ditemukan).' };
  }
  return { ok: true };
}

// ---------------------------------------------------------------------
// Panggilan masuk: cari tombol Terima + Tolak di popup panggilan WhatsApp Web.
// Pencarian berdasarkan label tombol (ID/EN), bukan class CSS yang berubah-ubah.
// ---------------------------------------------------------------------
const ACCEPT_RE = /^(accept|answer|terima|jawab)(\s+(call|panggilan))?$/i;
const DECLINE_RE = /^(decline|reject|tolak)(\s+(call|panggilan))?$/i;
const CALL_WORDS = /call|panggilan|calling|memanggil|menelepon/i;
const labelOf = (el) =>
  (el.getAttribute('aria-label') || el.getAttribute('title') || el.textContent || '').trim();

function findCall() {
  let accept = null, decline = null;
  for (const el of document.querySelectorAll('button, [role="button"]')) {
    const l = labelOf(el);
    if (!l || l.length > 24) continue;
    if (!accept && ACCEPT_RE.test(l)) accept = el;
    else if (!decline && DECLINE_RE.test(l)) decline = el;
  }
  if (!accept || !decline) return null;

  // Kedua tombol harus satu popup, dan popup itu menyebut "call/panggilan"
  // (supaya dialog "Terima/Tolak" lain tidak dikira panggilan).
  let box = accept;
  while (box && !box.contains(decline)) box = box.parentElement;
  if (!box || box === document.body) return null;
  let ctx = box;
  for (let i = 0; i < 3 && ctx.parentElement && ctx.parentElement !== document.body; i++) {
    ctx = ctx.parentElement;
  }
  const text = (ctx.innerText || '').trim();
  if (!CALL_WORDS.test(text)) return null;

  const lines = text
    .split('\n')
    .map((s) => s.trim())
    .filter((l) => l && !ACCEPT_RE.test(l) && !DECLINE_RE.test(l));
  const name =
    lines.find((l) => !CALL_WORDS.test(l) && !/^whatsapp$/i.test(l) && l.length < 60) ||
    'WhatsApp';
  return { accept, decline, name, video: /video/i.test(text) };
}

function reportCall(m) {
  try {
    const p = browser.runtime.sendMessage(m);
    if (p && p.catch) p.catch(() => {});
  } catch (_) {}
}

let ringing = false;
setInterval(() => {
  let f = null;
  try { f = findCall(); } catch (_) {}
  if (f && !ringing) {
    ringing = true;
    reportCall({ type: 'wa-call', state: 'incoming', name: f.name, video: f.video });
  } else if (!f && ringing) {
    ringing = false;
    reportCall({ type: 'wa-call', state: 'ended' });
  }
}, 800);

function handleCallAction(action) {
  const f = findCall();
  if (!f) {
    return { ok: false, error: 'Panggilan tidak ditemukan di WhatsApp Web (sudah berakhir?).' };
  }
  (action === 'accept' ? f.accept : f.decline).click();
  return { ok: true };
}

browser.runtime.onMessage.addListener((msg) => {
  if (!msg) return;
  if (msg.type === 'send') return handleSend(msg);
  if (msg.type === 'call-action') return Promise.resolve(handleCallAction(msg.action));
});
