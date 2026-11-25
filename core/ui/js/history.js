// Painel do histórico de cópias: busca, filtros, teclado e colar no app anterior.
import { icon } from './icons.js';

const T = window.__TAURI__;
const invoke = T.core.invoke;
const PROTO = /Windows/i.test(navigator.userAgent) ? 'http://cpframe.localhost' : 'cpframe://localhost';
const $ = s => document.querySelector(s);

const FILTERS = [['all', 'Tudo'], ['pinned', 'Fixados'], ['text', 'Texto'], ['link', 'Links'], ['image', 'Imagens'], ['color', 'Cores'], ['code', 'Código']];
const KIND_ICON = { text: 'textLines', link: 'link', image: 'image', color: 'palette', code: 'code' };

let items = [], view = [], sel = 0, filter = 'all', pasteOnSelect = true;

$('#searchbox').innerHTML = `${icon('search', 16)}<input id="q" placeholder="Buscar no histórico…" autocomplete="off" spellcheck="false">`;
$('#settings').innerHTML = icon('settings', 17);
$('#settings').addEventListener('click', () => invoke('open_settings', {}));
const q = $('#q');

const nav = $('#filters');
for (const [k, label] of FILTERS) {
  const b = document.createElement('button');
  b.textContent = label; b.dataset.k = k;
  b.addEventListener('click', () => setFilter(k));
  nav.append(b);
}
function setFilter(k) {
  filter = k;
  nav.querySelectorAll('button').forEach(b => b.classList.toggle('active', b.dataset.k === k));
  sel = 0; refresh();
}

function ago(ms) {
  const s = (Date.now() - ms) / 1000;
  if (s < 60) return 'agora';
  if (s < 3600) return `há ${Math.floor(s / 60)} min`;
  if (s < 86400) return `há ${Math.floor(s / 3600)} h`;
  const d = Math.floor(s / 86400);
  return d === 1 ? 'ontem' : d < 30 ? `há ${d} dias` : new Date(ms).toLocaleDateString('pt-BR');
}

function norm(s) { return (s || '').normalize('NFD').replace(/\p{M}/gu, '').toLowerCase(); }

function refresh() {
  const words = norm(q.value).split(/\s+/).filter(Boolean);
  view = items.filter(i => {
    if (filter === 'pinned' ? !i.pinned : filter !== 'all' && i.kind !== filter) return false;
    if (!words.length) return true;
    const hay = norm(i.text || (i.kind === 'image' ? 'imagem' : ''));
    return words.every(w => hay.includes(w));
  });
  // Fixados primeiro quando não há busca.
  if (!words.length && filter === 'all') view.sort((a, b) => (b.pinned - a.pinned) || (b.date - a.date));
  sel = Math.max(0, Math.min(sel, view.length - 1));
  draw();
}

function esc(s) { return s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }

function draw() {
  const list = $('#list');
  if (!view.length) {
    list.innerHTML = `<div class="empty">${items.length ? 'Nada encontrado.' : 'Copie algo (Ctrl+C) e ele aparece aqui.'}</div>`;
  } else {
    list.innerHTML = view.slice(0, 300).map((i, n) => {
      let lead;
      if (i.kind === 'image') lead = `<img class="thumb" loading="lazy" src="${PROTO}/img/${encodeURIComponent(i.image)}">`;
      else if (i.kind === 'color') lead = `<span class="swatch" style="background:${esc(i.text.trim())}"></span>`;
      else lead = `<span class="kind">${icon(KIND_ICON[i.kind] || 'textLines', 16)}</span>`;
      const title = i.kind === 'image' ? `Imagem` : esc((i.text || '').replace(/\s+/g, ' ').trim().slice(0, 240));
      const meta = [ago(i.date)];
      if (i.kind === 'image') meta.push(`${i.width} × ${i.height}`);
      else if (i.chars > 80) meta.push(`${i.chars.toLocaleString('pt-BR')} caracteres`);
      if (i.uses > 1) meta.push(`usado ${i.uses}×`);
      return `<div class="item ${n === sel ? 'sel' : ''}" data-n="${n}">
        <span class="num">${n < 9 ? n + 1 : ''}</span>${lead}
        <div class="body"><div class="title ${i.kind === 'code' ? 'code' : ''}">${title}</div><div class="meta">${meta.join(' · ')}</div></div>
        ${i.pinned ? `<span class="pinmark" title="Fixado">${icon('pin', 15)}</span>` : ''}
      </div>`;
    }).join('');
  }
  $('#count').textContent = `${view.length} de ${items.length}`;
  const el = list.querySelector('.item.sel');
  if (el) el.scrollIntoView({ block: 'nearest' });
}

$('#list').addEventListener('click', e => { const it = e.target.closest('.item'); if (it) { sel = +it.dataset.n; draw(); } });
$('#list').addEventListener('dblclick', e => { const it = e.target.closest('.item'); if (it) { sel = +it.dataset.n; use(pasteOnSelect); } });

async function load() {
  items = await invoke('history_list');
  refresh();
}

async function use(paste) {
  const it = view[sel];
  if (!it) return;
  await invoke('history_use', { id: it.id, paste });
}

function preview() {
  const it = view[sel];
  if (!it) return;
  const box = $('#pvbox');
  box.innerHTML = it.kind === 'image' ? `<img src="${PROTO}/img/${encodeURIComponent(it.image)}">` : esc(it.text || '');
  $('#preview').hidden = false;
}
$('#preview').addEventListener('click', () => { $('#preview').hidden = true; });

addEventListener('keydown', async e => {
  const ctrl = e.ctrlKey || e.metaKey;
  if (!$('#preview').hidden) { if (e.key === 'Escape' || e.key === ' ') { e.preventDefault(); $('#preview').hidden = true; } return; }
  switch (e.key) {
    case 'Escape': e.preventDefault(); if (q.value) { q.value = ''; refresh(); } else invoke('hide_history'); return;
    case 'ArrowDown': e.preventDefault(); sel = Math.min(view.length - 1, sel + 1); draw(); return;
    case 'ArrowUp': e.preventDefault(); sel = Math.max(0, sel - 1); draw(); return;
    case 'PageDown': e.preventDefault(); sel = Math.min(view.length - 1, sel + 8); draw(); return;
    case 'PageUp': e.preventDefault(); sel = Math.max(0, sel - 8); draw(); return;
    case 'Enter': e.preventDefault(); use(ctrl ? false : pasteOnSelect); return;
    case 'Tab': {
      e.preventDefault();
      const i = FILTERS.findIndex(f => f[0] === filter);
      setFilter(FILTERS[(i + (e.shiftKey ? FILTERS.length - 1 : 1)) % FILTERS.length][0]);
      return;
    }
    case 'Delete': if (view[sel]) { e.preventDefault(); invoke('history_delete', { id: view[sel].id }); } return;
    case ' ': if (!q.value) { e.preventDefault(); preview(); } return;
  }
  if (ctrl && e.key.toLowerCase() === 'p' && view[sel]) { e.preventDefault(); invoke('history_pin', { id: view[sel].id }); return; }
  if (ctrl && e.key.toLowerCase() === 'c' && view[sel] && !window.getSelection().toString()) { e.preventDefault(); use(false); return; }
  if (ctrl && /^[1-9]$/.test(e.key)) { e.preventDefault(); sel = +e.key - 1; if (view[sel]) use(pasteOnSelect); return; }
  if (ctrl && e.key === ',') { e.preventDefault(); invoke('open_settings', {}); return; }
  if (document.activeElement !== q && e.key.length === 1 && !ctrl && !e.altKey) q.focus();
});
q.addEventListener('input', () => { sel = 0; refresh(); });

T.event.listen('history-changed', load);
T.event.listen('history-open', async () => {
  q.value = ''; sel = 0; $('#preview').hidden = true;
  try { pasteOnSelect = (await invoke('get_settings')).settings.pasteOnSelect; } catch { }
  setFilter('all');
  await load();
  setTimeout(() => q.focus(), 30);
});

setFilter('all');
load();
