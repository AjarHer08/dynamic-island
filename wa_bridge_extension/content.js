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

function chatInList(name) {
  const pane = document.querySelector('#pane-side');
  if (!pane) return null;
  const spans = [...pane.querySelectorAll('span[title]')];
  const n = norm(name);
  return (
    spans.find((s) => norm(s.getAttribute('title')) === n) ||
    spans.find((s) => norm(s.getAttribute('title')).includes(n)) ||
    null
  );
}

function openChatTitle() {
  const el = document.querySelector('#main header span[title]');
  return el ? norm(el.getAttribute('title')) : '';
}

function chatIsOpen(name) {
  const t = openChatTitle();
  const n = norm(name);
  return !!t && (t === n || t.includes(n) || n.includes(t));
}

const searchBox = () =>
  document.querySelector('#side [contenteditable="true"][data-tab="3"]') ||
  document.querySelector('#side [contenteditable="true"]');
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

async function openChat(name) {
  if (chatIsOpen(name)) return true;

  let item = chatInList(name);
  if (!item) {
    const box = await waitFor(searchBox, 3000);
    if (!box) return false;
    setText(box, name);
    item = await waitFor(() => chatInList(name), 6000);
    if (!item) {
      setText(box, '');
      return false;
    }
  }
  click(item);
  const ok = await waitFor(() => chatIsOpen(name), 5000);
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
    return { ok: false, error: `Chat "${chat}" tidak ditemukan di WhatsApp Web.` };
  }
  if (!(await sendText(text))) {
    return { ok: false, error: 'Pesan tidak terkirim (kolom tulis tidak ditemukan).' };
  }
  return { ok: true };
}

browser.runtime.onMessage.addListener((msg) => {
  if (msg && msg.type === 'send') return handleSend(msg);
});
