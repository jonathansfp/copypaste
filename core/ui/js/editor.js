// Editor em tela cheia: captura (área, janela ou tela), gravação (escolha da área) e quadro de apresentação.
import * as S from './shapes.js';
import { icon } from './icons.js';

const T = window.__TAURI__;
const invoke = T.core.invoke;
const listen = T.event.listen;
const PROTO = /Windows/i.test(navigator.userAgent) ? 'http://cpframe.localhost' : 'cpframe://localhost';
const $ = s => document.querySelector(s);
const cv = $('#c'), ctx = cv.getContext('2d');
const ta = $('#ed');

const TOOL_KEYS = { select: 'V', pen: 'P', highlighter: 'H', line: 'L', arrow: 'A', rect: 'R', ellipse: 'O', diamond: 'D', text: 'T', step: 'N', sticky: 'S', blur: 'B', eraser: 'E', laser: 'K' };
const TOOL_LABELS = { select: 'Selecionar e mover', eraser: 'Borracha', laser: 'Laser (apresentação)', ...S.KINDS };
const BACKGROUNDS = [['screen', 'Tela congelada'], ['white', 'Quadro branco'], ['grid', 'Papel quadriculado'], ['dark', 'Quadro escuro'], ['chalk', 'Lousa verde']];

const newDoc = () => ({ shapes: [], undo: [], redo: [] });
const boardDoc = newDoc();
const images = new Map();
const pixCache = new Map();

const st = {
  mode: null, phase: 'choose', frame: null, scale: 1,
  sel: null, windows: [], hover: null,
  tool: 'arrow', style: S.defaultStyle(),
  doc: newDoc(), selected: new Set(), drag: null,
  mouse: { x: -100, y: -100, in: false }, laser: [], editing: null,
  settings: { magnifier: true, enterAction: 'copy', mic: false, systemAudio: false },
  bg: localStorage.getItem('cp.board.bg') || 'screen',
};
let W = innerWidth, H = innerHeight, dpr = devicePixelRatio || 1;
const isBoard = () => st.mode === 'board';
const isRecord = () => st.mode === 'record';
const docShapes = () => st.doc.shapes;

// ───────────────────────── abertura ─────────────────────────

function loadPrefs() {
  const k = isBoard() ? 'board' : 'capture';
  try { st.style = { ...S.defaultStyle(), ...JSON.parse(localStorage.getItem(`cp.style.${k}`) || '{}') }; } catch { st.style = S.defaultStyle(); }
  st.tool = localStorage.getItem(`cp.tool.${k}`) || (isBoard() ? 'pen' : 'arrow');
  if (st.tool === 'laser' && !isBoard()) st.tool = 'arrow';
}
function savePrefs() {
  const k = isBoard() ? 'board' : 'capture';
  localStorage.setItem(`cp.style.${k}`, JSON.stringify(st.style));
  localStorage.setItem(`cp.tool.${k}`, st.tool);
}

listen('editor-open', async ev => {
  const p = ev.payload;
  hideTextEditor(false);
  st.mode = p.mode;
  st.settings = { magnifier: p.magnifier, enterAction: p.enterAction, mic: p.mic, systemAudio: p.systemAudio };
  st.doc = isBoard() ? boardDoc : newDoc();
  st.selected.clear(); st.drag = null; st.laser = []; st.hover = null;
  pixCache.clear();
  loadPrefs();
  try {
    const res = await fetch(`${PROTO}/frame/${p.frame}`, { cache: 'no-store' });
    const buf = await res.arrayBuffer();
    const data = new ImageData(new Uint8ClampedArray(buf), p.width, p.height);
    const bmp = await createImageBitmap(data);
    if (st.frame && st.frame.bmp) st.frame.bmp.close();
    st.frame = { w: p.width, h: p.height, bmp, data };
  } catch (e) {
    invoke('log', { msg: `falha ao carregar a tela: ${e}` });
    st.frame = null;
  }
  layout();
  st.windows = (p.windows || []).map(r => ({ x: r.x / st.scale, y: r.y / st.scale, w: r.w / st.scale, h: r.h / st.scale }));
  if (p.mode === 'screen' || isBoard()) {
    st.sel = { x: 0, y: 0, w: W, h: H };
    st.phase = 'edit';
  } else {
    st.sel = null;
    st.phase = 'choose';
  }
  buildBars();
  render();
  await invoke('editor_ready');
  setTimeout(() => { layout(); if (p.mode === 'screen' || isBoard()) st.sel = { x: 0, y: 0, w: W, h: H }; buildBars(); render(); }, 80);
});

listen('editor-close-request', () => close());

function layout() {
  W = innerWidth; H = innerHeight; dpr = devicePixelRatio || 1;
  cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr);
  cv.style.width = `${W}px`; cv.style.height = `${H}px`;
  st.scale = st.frame ? st.frame.w / W : dpr;
}
addEventListener('resize', () => { const old = W; layout(); if (st.sel && st.sel.w === old) st.sel = { x: 0, y: 0, w: W, h: H }; placeBars(); render(); });

// ───────────────────────── desenho ─────────────────────────

const env = {
  get scale() { return 1; },
  images,
  pixelate(r) {
    if (!st.frame || (isBoard() && st.bg !== 'screen')) return null;
    const key = `${r.x | 0},${r.y | 0},${r.w | 0},${r.h | 0}`;
    if (pixCache.has(key)) return pixCache.get(key);
    const b = Math.max(10, Math.min(r.w, r.h) / 9);
    const c = document.createElement('canvas');
    c.width = Math.max(1, Math.round(r.w / b)); c.height = Math.max(1, Math.round(r.h / b));
    const sc = st.scale;
    // Reduz pela metade em etapas: cada bloco vira a média real dos pixels (sem "furos").
    let src = st.frame.bmp, sx = r.x * sc, sy = r.y * sc, sw = Math.max(1, r.w * sc), sh = Math.max(1, r.h * sc);
    while (sw / 2 > c.width && sh / 2 > c.height) {
      const t = document.createElement('canvas');
      t.width = Math.max(1, Math.round(sw / 2)); t.height = Math.max(1, Math.round(sh / 2));
      const tx = t.getContext('2d');
      tx.imageSmoothingQuality = 'high';
      tx.drawImage(src, sx, sy, sw, sh, 0, 0, t.width, t.height);
      src = t; sx = 0; sy = 0; sw = t.width; sh = t.height;
    }
    const x = c.getContext('2d');
    x.imageSmoothingQuality = 'high';
    x.drawImage(src, sx, sy, sw, sh, 0, 0, c.width, c.height);
    if (pixCache.size > 60) pixCache.clear();
    pixCache.set(key, c);
    return c;
  },
};
const envAt = scale => ({ scale, images, pixelate: env.pixelate });

function drawBackground(c, w, h) {
  switch (isBoard() ? st.bg : 'screen') {
    case 'white': c.fillStyle = '#ffffff'; c.fillRect(0, 0, w, h); break;
    case 'dark': c.fillStyle = '#1d1f24'; c.fillRect(0, 0, w, h); break;
    case 'chalk': c.fillStyle = '#1f3b2f'; c.fillRect(0, 0, w, h); break;
    case 'grid': {
      c.fillStyle = '#fbfbfa'; c.fillRect(0, 0, w, h);
      c.strokeStyle = '#e8e8e4'; c.lineWidth = 1; c.beginPath();
      for (let x = 0.5; x < w; x += 24) { c.moveTo(x, 0); c.lineTo(x, h); }
      for (let y = 0.5; y < h; y += 24) { c.moveTo(0, y); c.lineTo(w, y); }
      c.stroke();
      break;
    }
    default:
      if (st.frame) c.drawImage(st.frame.bmp, 0, 0, w, h);
      else { c.fillStyle = '#000'; c.fillRect(0, 0, w, h); }
  }
}

let raf = 0;
function render() { if (!raf) raf = requestAnimationFrame(() => { raf = 0; paint(); }); }
function renderNow() { if (raf) { cancelAnimationFrame(raf); raf = 0; } paint(); }

function visibleShapes() {
  return docShapes().map(s => (st.editing && s === st.editing ? { ...s, text: '' } : s));
}

function paint() {
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, W, H);
  drawBackground(ctx, W, H);
  if (isBoard()) {
    S.draw(ctx, visibleShapes(), env);
    drawShapeSelection();
    drawMarquee();
    drawLaser();
    return;
  }
  const sel = st.sel;
  ctx.fillStyle = 'rgba(0,0,0,0.38)';
  if (st.phase === 'choose' || !sel || sel.w < 1 || sel.h < 1) {
    ctx.fillRect(0, 0, W, H);
    if (st.phase === 'choose' && st.hover) {
      const h = st.hover;
      if (st.frame) ctx.drawImage(st.frame.bmp, h.x * st.scale, h.y * st.scale, h.w * st.scale, h.h * st.scale, h.x, h.y, h.w, h.h);
      ctx.strokeStyle = '#2f8cff'; ctx.lineWidth = 3; ctx.strokeRect(h.x + 1.5, h.y + 1.5, h.w - 3, h.h - 3);
    }
  } else {
    ctx.fillRect(0, 0, W, sel.y);
    ctx.fillRect(0, sel.y + sel.h, W, H - sel.y - sel.h);
    ctx.fillRect(0, sel.y, sel.x, sel.h);
    ctx.fillRect(sel.x + sel.w, sel.y, W - sel.x - sel.w, sel.h);
    ctx.save();
    ctx.beginPath(); ctx.rect(sel.x, sel.y, sel.w, sel.h); ctx.clip();
    S.draw(ctx, visibleShapes(), env);
    ctx.restore();
    drawShapeSelection();
    drawMarquee();
    // Borda e alças da seleção
    ctx.strokeStyle = '#2f8cff'; ctx.lineWidth = 1.5; ctx.setLineDash([]);
    ctx.strokeRect(sel.x - 0.75, sel.y - 0.75, sel.w + 1.5, sel.h + 1.5);
    if (st.phase === 'edit' && st.mode !== 'screen') {
      for (const [hx, hy] of selHandles(sel)) {
        ctx.fillStyle = '#fff'; ctx.strokeStyle = '#2f8cff'; ctx.lineWidth = 1.5;
        ctx.beginPath(); ctx.arc(hx, hy, 4.5, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
      }
    }
    // Tamanho em pixels reais
    const label = `${Math.round(sel.w * st.scale)} × ${Math.round(sel.h * st.scale)}`;
    ctx.font = `600 12px ${S.FONTS.system}`;
    const tw = ctx.measureText(label).width + 14;
    const ly = sel.y > 26 ? sel.y - 24 : sel.y + 6, lx = Math.min(sel.x, W - tw - 4);
    ctx.fillStyle = 'rgba(20,20,22,0.82)';
    ctx.beginPath(); ctx.roundRect ? ctx.roundRect(lx, ly, tw, 19, 5) : ctx.rect(lx, ly, tw, 19); ctx.fill();
    ctx.fillStyle = '#fff'; ctx.textBaseline = 'middle'; ctx.fillText(label, lx + 7, ly + 10);
  }
  if (st.phase !== 'edit' && st.settings.magnifier && st.mouse.in) drawMagnifier();
}

function drawMarquee() {
  const d = st.drag;
  if (!d || d.type !== 'marquee') return;
  const r = rectFrom(d.start, d.cur);
  ctx.fillStyle = 'rgba(47,140,255,0.08)'; ctx.fillRect(r.x, r.y, r.w, r.h);
  ctx.strokeStyle = '#2f8cff'; ctx.lineWidth = 1; ctx.setLineDash([4, 3]); ctx.strokeRect(r.x + 0.5, r.y + 0.5, r.w, r.h); ctx.setLineDash([]);
}

function drawShapeSelection() {
  const sel = selectedShapes();
  if (!sel.length) return;
  ctx.save();
  ctx.strokeStyle = '#2f8cff'; ctx.lineWidth = 1.2; ctx.setLineDash([5, 4]);
  for (const s of sel) { const b = S.bounds(s); ctx.strokeRect(b.x, b.y, b.w, b.h); }
  ctx.setLineDash([]);
  if (sel.length === 1) {
    for (const [hx, hy] of shapeHandles(sel[0])) {
      ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.rect(hx - 4, hy - 4, 8, 8); ctx.fill(); ctx.stroke();
    }
  }
  ctx.restore();
}

function drawLaser() {
  const now = performance.now();
  st.laser = st.laser.filter(p => now - p.t < 700);
  if (st.laser.length > 1) {
    ctx.save(); ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    for (let i = 1; i < st.laser.length; i++) {
      const a = st.laser[i - 1], b = st.laser[i], life = 1 - (now - b.t) / 700;
      ctx.strokeStyle = `rgba(255,40,40,${0.85 * life})`; ctx.lineWidth = 2 + 6 * life;
      ctx.shadowColor = 'rgba(255,0,0,0.8)'; ctx.shadowBlur = 12;
      ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
    }
    ctx.restore();
  }
  if (st.tool === 'laser' && st.mouse.in) {
    ctx.save(); ctx.fillStyle = '#ff2a2a'; ctx.shadowColor = 'rgba(255,0,0,0.9)'; ctx.shadowBlur = 14;
    ctx.beginPath(); ctx.arc(st.mouse.x, st.mouse.y, 5, 0, Math.PI * 2); ctx.fill(); ctx.restore();
  }
  if (st.laser.length) render();
}

function pixelAt(x, y) {
  if (!st.frame) return null;
  const px = Math.min(st.frame.w - 1, Math.max(0, Math.floor(x * st.scale)));
  const py = Math.min(st.frame.h - 1, Math.max(0, Math.floor(y * st.scale)));
  const i = (py * st.frame.w + px) * 4, d = st.frame.data.data;
  return { px, py, hex: '#' + [d[i], d[i + 1], d[i + 2]].map(v => v.toString(16).padStart(2, '0')).join('').toUpperCase() };
}

function drawMagnifier() {
  if (!st.frame) return;
  const { x, y } = st.mouse, size = 128, n = 15;
  const p = pixelAt(x, y);
  let bx = x + 22, by = y + 22;
  if (bx + size > W - 6) bx = x - size - 22;
  if (by + size + 26 > H - 6) by = y - size - 48;
  ctx.save();
  ctx.imageSmoothingEnabled = false;
  ctx.beginPath(); ctx.roundRect ? ctx.roundRect(bx, by, size, size, 10) : ctx.rect(bx, by, size, size); ctx.clip();
  ctx.fillStyle = '#000'; ctx.fillRect(bx, by, size, size);
  ctx.drawImage(st.frame.bmp, p.px - (n >> 1), p.py - (n >> 1), n, n, bx, by, size, size);
  const cell = size / n;
  ctx.strokeStyle = 'rgba(255,255,255,0.9)'; ctx.lineWidth = 1.5;
  ctx.strokeRect(bx + cell * (n >> 1), by + cell * (n >> 1), cell, cell);
  ctx.restore();
  ctx.strokeStyle = 'rgba(255,255,255,0.85)'; ctx.lineWidth = 2;
  ctx.beginPath(); ctx.roundRect ? ctx.roundRect(bx, by, size, size, 10) : ctx.rect(bx, by, size, size); ctx.stroke();
  const label = `${p.px}, ${p.py}   ${p.hex}`;
  ctx.font = `600 11px ${S.FONTS.mono}`;
  const tw = ctx.measureText(label).width + 30;
  ctx.fillStyle = 'rgba(20,20,22,0.88)';
  ctx.beginPath(); ctx.roundRect ? ctx.roundRect(bx, by + size + 5, Math.max(tw, size), 21, 6) : ctx.rect(bx, by + size + 5, tw, 21); ctx.fill();
  ctx.fillStyle = p.hex; ctx.fillRect(bx + 7, by + size + 10, 11, 11);
  ctx.fillStyle = '#fff'; ctx.textBaseline = 'middle'; ctx.fillText(label, bx + 23, by + size + 16);
}

// ───────────────────────── geometria da interação ─────────────────────────

const rectFrom = (a, b) => ({ x: Math.min(a[0], b[0]), y: Math.min(a[1], b[1]), w: Math.abs(a[0] - b[0]), h: Math.abs(a[1] - b[1]) });
const inside = (r, x, y, t = 0) => r && x >= r.x - t && x <= r.x + r.w + t && y >= r.y - t && y <= r.y + r.h + t;
const clampSel = r => {
  const x = Math.max(0, Math.min(r.x, W - 1)), y = Math.max(0, Math.min(r.y, H - 1));
  return { x, y, w: Math.min(r.w, W - x), h: Math.min(r.h, H - y) };
};
function selHandles(r) {
  const { x, y, w, h } = r;
  return [[x, y], [x + w / 2, y], [x + w, y], [x + w, y + h / 2], [x + w, y + h], [x + w / 2, y + h], [x, y + h], [x, y + h / 2]];
}
function handleAt(list, x, y, tol = 8) { return list.findIndex(([hx, hy]) => Math.abs(hx - x) <= tol && Math.abs(hy - y) <= tol); }
function resizeRect(o, idx, dx, dy) {
  let x0 = o.x, y0 = o.y, x1 = o.x + o.w, y1 = o.y + o.h;
  if ([0, 6, 7].includes(idx)) x0 += dx;
  if ([2, 3, 4].includes(idx)) x1 += dx;
  if ([0, 1, 2].includes(idx)) y0 += dy;
  if ([4, 5, 6].includes(idx)) y1 += dy;
  return rectFrom([x0, y0], [x1, y1]);
}
function shapeHandles(s) {
  if (S.isLinear(s.kind)) return [s.pts[0], s.pts[s.pts.length - 1]];
  if (S.isBox(s.kind)) return selHandles(S.rectOf(s));
  return [];
}
const selectedShapes = () => docShapes().filter(s => st.selected.has(s.id));
function shapeAt(x, y) {
  const list = docShapes();
  for (let i = list.length - 1; i >= 0; i--) if (S.hitTest(list[i], x, y)) return list[i];
  return null;
}

// ───────────────────────── desfazer ─────────────────────────

function checkpoint() {
  const d = st.doc;
  d.undo.push(structuredClone(d.shapes));
  if (d.undo.length > 300) d.undo.shift();
  d.redo = [];
}
function undo() {
  const d = st.doc;
  if (!d.undo.length) return;
  d.redo.push(structuredClone(d.shapes));
  d.shapes = d.undo.pop();
  st.selected.clear(); render();
}
function redo() {
  const d = st.doc;
  if (!d.redo.length) return;
  d.undo.push(structuredClone(d.shapes));
  d.shapes = d.redo.pop();
  st.selected.clear(); render();
}

// ───────────────────────── mouse ─────────────────────────

const canDraw = () => isBoard() || (st.phase === 'edit' && !isRecord());

cv.addEventListener('pointerdown', e => {
  if (e.button === 2) return;
  // Evita que o clique tire o foco da caixa de texto recém-criada.
  e.preventDefault();
  cv.setPointerCapture(e.pointerId);
  closePopover();
  const p = [e.clientX, e.clientY];
  if (st.editing) { commitText(); return; }

  if (!isBoard()) {
    if (st.phase === 'choose') { st.drag = { type: 'newsel', start: p, cur: p }; st.phase = 'select'; st.sel = { x: p[0], y: p[1], w: 0, h: 0 }; hideBars(); render(); return; }
    if (st.phase === 'edit' && st.mode !== 'screen') {
      const hi = handleAt(selHandles(st.sel), p[0], p[1]);
      if (hi >= 0 && !(st.tool !== 'select' && shapeAt(p[0], p[1]))) { st.drag = { type: 'selresize', idx: hi, orig: { ...st.sel }, start: p }; return; }
      if (e.ctrlKey || e.metaKey || isRecord()) {
        if (inside(st.sel, p[0], p[1]) || e.ctrlKey || e.metaKey) { st.drag = { type: 'selmove', orig: { ...st.sel }, start: p }; return; }
      }
      if (!inside(st.sel, p[0], p[1]) && (isRecord() || !docShapes().length)) {
        st.drag = { type: 'newsel', start: p, cur: p }; st.phase = 'select'; st.sel = { x: p[0], y: p[1], w: 0, h: 0 }; hideBars(); render(); return;
      }
    }
    if (!canDraw()) return;
  }

  const tool = st.tool;
  if (tool === 'select') {
    const one = selectedShapes();
    if (one.length === 1) {
      const hi = handleAt(shapeHandles(one[0]), p[0], p[1]);
      if (hi >= 0) { st.drag = { type: 'shaperesize', idx: hi, shape: one[0], orig: structuredClone(one[0]), start: p, saved: false }; return; }
    }
    const hit = shapeAt(p[0], p[1]);
    if (hit) {
      if (e.shiftKey) { st.selected.has(hit.id) ? st.selected.delete(hit.id) : st.selected.add(hit.id); }
      else if (!st.selected.has(hit.id)) { st.selected.clear(); st.selected.add(hit.id); }
      st.drag = { type: 'move', last: p, saved: false };
      syncStyleFromSelection(); render(); return;
    }
    if (!e.shiftKey) st.selected.clear();
    if (!isBoard() && st.mode !== 'screen' && inside(st.sel, p[0], p[1]) && !docShapes().length) {
      st.drag = { type: 'selmove', orig: { ...st.sel }, start: p }; render(); return;
    }
    st.drag = { type: 'marquee', start: p, cur: p }; render(); return;
  }
  if (tool === 'eraser') { checkpoint(); st.drag = { type: 'erase', removed: 0 }; erase(p); return; }
  if (tool === 'laser') { st.drag = { type: 'laser' }; st.laser.push({ x: p[0], y: p[1], t: performance.now() }); render(); return; }
  if (tool === 'text') {
    const hit = shapeAt(p[0], p[1]);
    if (hit && (hit.kind === 'text' || S.acceptsLabel(hit.kind))) { editText(hit); return; }
    checkpoint();
    const s = S.newShape('text', [[p[0], p[1] - st.style.fontSize * 0.6]], st.style);
    docShapes().push(s);
    editText(s, true);
    return;
  }
  if (tool === 'step') {
    checkpoint();
    const s = S.newShape('step', [p], st.style);
    s.number = docShapes().filter(x => x.kind === 'step').reduce((m, x) => Math.max(m, x.number), 0) + 1;
    docShapes().push(s);
    render(); return;
  }
  checkpoint();
  st.selected.clear();
  const s = S.newShape(tool, S.isFreehand(tool) ? [p] : [p, p], st.style);
  if (tool === 'sticky') { s.style.fill = s.style.fill === 'soft' ? 'none' : s.style.fill; if (s.style.color === '#ff3b30') s.style.color = '#ffcc00'; s.style.fontSize = Math.min(s.style.fontSize, 22); }
  docShapes().push(s);
  st.drag = { type: 'create', shape: s, start: p };
  render();
});

cv.addEventListener('pointermove', e => {
  const p = [e.clientX, e.clientY];
  st.mouse = { x: p[0], y: p[1], in: true };
  const d = st.drag;
  if (!d) {
    if (!isBoard() && st.phase === 'choose') {
      const hov = st.windows.find(r => inside(r, p[0], p[1])) || null;
      st.hover = hov;
    }
    updateCursor(p);
    if (!isBoard() && st.phase !== 'edit' || st.tool === 'laser') render();
    return;
  }
  switch (d.type) {
    case 'newsel': d.cur = p; st.sel = clampSel(rectFrom(d.start, p)); break;
    case 'selmove': {
      const o = d.orig;
      st.sel = { x: Math.max(0, Math.min(W - o.w, o.x + p[0] - d.start[0])), y: Math.max(0, Math.min(H - o.h, o.y + p[1] - d.start[1])), w: o.w, h: o.h };
      placeBars(); break;
    }
    case 'selresize': st.sel = clampSel(resizeRect(d.orig, d.idx, p[0] - d.start[0], p[1] - d.start[1])); placeBars(); break;
    case 'create': {
      const s = d.shape;
      if (S.isFreehand(s.kind)) {
        const last = s.pts[s.pts.length - 1];
        if (Math.hypot(p[0] - last[0], p[1] - last[1]) >= 1.5) s.pts.push(p);
      } else {
        let q = p;
        if (e.shiftKey) {
          const dx = p[0] - d.start[0], dy = p[1] - d.start[1];
          if (S.isLinear(s.kind)) {
            const a = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * (Math.PI / 4), len = Math.hypot(dx, dy);
            q = [d.start[0] + Math.cos(a) * len, d.start[1] + Math.sin(a) * len];
          } else {
            const m = Math.max(Math.abs(dx), Math.abs(dy));
            q = [d.start[0] + Math.sign(dx || 1) * m, d.start[1] + Math.sign(dy || 1) * m];
          }
        }
        s.pts = [d.start, q];
      }
      break;
    }
    case 'move': {
      const dx = p[0] - d.last[0], dy = p[1] - d.last[1];
      if (!d.saved && (dx || dy)) { checkpoint(); d.saved = true; }
      for (const s of selectedShapes()) S.move(s, dx, dy);
      d.last = p; break;
    }
    case 'shaperesize': {
      if (!d.saved) { checkpoint(); d.saved = true; }
      const s = d.shape, o = d.orig, dx = p[0] - d.start[0], dy = p[1] - d.start[1];
      if (S.isLinear(s.kind)) {
        const pts = o.pts.map(q => [...q]);
        const i = d.idx === 0 ? 0 : pts.length - 1;
        pts[i] = [pts[i][0] + dx, pts[i][1] + dy];
        s.pts = pts;
      } else {
        const r = resizeRect(S.rectOf(o), d.idx, dx, dy);
        s.pts = [[r.x, r.y], [r.x + r.w, r.y + r.h]];
      }
      pixCache.clear();
      break;
    }
    case 'marquee': d.cur = p; break;
    case 'erase': erase(p); break;
    case 'laser': st.laser.push({ x: p[0], y: p[1], t: performance.now() }); break;
  }
  render();
});

cv.addEventListener('pointerleave', () => { st.mouse.in = false; render(); });

cv.addEventListener('pointerup', e => {
  const d = st.drag;
  st.drag = null;
  if (!d) return;
  const p = [e.clientX, e.clientY];
  if (d.type === 'newsel') {
    const r = rectFrom(d.start, p);
    if (r.w < 4 && r.h < 4) st.sel = st.hover ? { ...st.hover } : { x: 0, y: 0, w: W, h: H };
    st.sel = clampSel(st.sel);
    st.phase = 'edit';
    buildBars();
  } else if (d.type === 'create') {
    const s = d.shape, r = S.rectOf(s);
    const tiny = S.isFreehand(s.kind) ? false : (r.w < 3 && r.h < 3);
    if (tiny) {
      if (S.isBox(s.kind) && s.kind !== 'blur') {
        // Clique simples com forma de caixa: cria no tamanho padrão.
        const sz = s.kind === 'sticky' ? [200, 160] : s.kind === 'person' ? [70, 120] : [160, 100];
        s.pts = [[p[0] - sz[0] / 2, p[1] - sz[1] / 2], [p[0] + sz[0] / 2, p[1] + sz[1] / 2]];
      } else { docShapes().pop(); st.doc.undo.pop(); }
    }
    if (s.kind === 'sticky' && docShapes().includes(s)) editText(s);
    // No quadro, a forma recém-criada fica selecionada (Enter escreve dentro dela, como no Excalidraw).
    else if (isBoard() && docShapes().includes(s) && S.acceptsLabel(s.kind)) { st.selected.clear(); st.selected.add(s.id); }
  } else if (d.type === 'marquee') {
    const r = rectFrom(d.start, d.cur);
    if (r.w > 2 || r.h > 2) for (const s of docShapes()) if (S.intersects(S.bounds(s), r)) st.selected.add(s.id);
    syncStyleFromSelection();
  } else if (d.type === 'erase' && !d.removed) {
    st.doc.undo.pop();
  }
  render();
});

cv.addEventListener('dblclick', e => {
  if (!canDraw()) return;
  const hit = shapeAt(e.clientX, e.clientY);
  if (hit && (hit.kind === 'text' || S.acceptsLabel(hit.kind))) { editText(hit); return; }
  if (isBoard() && !hit && st.tool === 'select') {
    checkpoint();
    const s = S.newShape('text', [[e.clientX, e.clientY - st.style.fontSize * 0.6]], st.style);
    docShapes().push(s);
    editText(s, true);
  }
});
cv.addEventListener('contextmenu', e => e.preventDefault());

function erase(p) {
  const list = docShapes();
  for (let i = list.length - 1; i >= 0; i--) {
    if (S.hitTest(list[i], p[0], p[1], 8)) { list.splice(i, 1); st.drag && (st.drag.removed = (st.drag.removed || 0) + 1); }
  }
  render();
}

function updateCursor(p) {
  let c = 'crosshair';
  if (!isBoard() && st.phase === 'edit' && st.sel && st.mode !== 'screen') {
    const hi = handleAt(selHandles(st.sel), p[0], p[1]);
    if (hi >= 0) c = ['nwse-resize', 'ns-resize', 'nesw-resize', 'ew-resize', 'nwse-resize', 'ns-resize', 'nesw-resize', 'ew-resize'][hi];
    else if (isRecord() && inside(st.sel, p[0], p[1])) c = 'move';
  }
  if (canDraw()) {
    if (st.tool === 'select') c = shapeAt(p[0], p[1]) ? 'move' : 'default';
    else if (st.tool === 'text') c = 'text';
    else if (st.tool === 'laser') c = 'none';
    else if (st.tool === 'eraser') c = 'cell';
  }
  cv.style.cursor = c;
}

// ───────────────────────── texto ─────────────────────────

function editText(s, isNew = false) {
  st.editing = s;
  st.selected.clear();
  const stl = s.style;
  ta.value = s.text || '';
  ta.style.font = S.fontOf(stl);
  ta.style.lineHeight = `${stl.fontSize * 1.25}px`;
  if (s.kind === 'text') {
    ta.style.color = stl.fill === 'solid' ? S.contrast(stl.color) : stl.color;
    ta.style.background = stl.fill === 'solid' ? stl.color : stl.fill === 'soft' ? 'rgba(255,255,255,0.88)' : 'transparent';
    ta.style.textAlign = 'left';
    ta.style.left = `${s.pts[0][0] - 2}px`;
    ta.style.top = `${s.pts[0][1] + stl.fontSize * 0.1 - 2}px`;
    ta.style.width = `${Math.max(60, S.textSize(s).w + stl.fontSize)}px`;
    ta.style.height = `${S.textSize(s).h + 6}px`;
  } else {
    const r = S.labelRect(s);
    ta.style.color = s.kind === 'sticky' ? '#1f1f1f' : (stl.fill === 'solid' ? S.contrast(stl.color) : stl.color);
    ta.style.background = 'transparent';
    ta.style.textAlign = 'center';
    ta.style.left = `${r.x}px`; ta.style.top = `${r.y}px`;
    ta.style.width = `${Math.max(40, r.w)}px`; ta.style.height = `${Math.max(stl.fontSize * 1.4, r.h)}px`;
  }
  ta.dataset.isNew = isNew ? '1' : '';
  ta.hidden = false;
  ta.focus();
  ta.select();
  requestAnimationFrame(() => { if (st.editing === s) ta.focus(); });
  render();
}

ta.addEventListener('input', () => {
  const s = st.editing;
  if (!s || s.kind !== 'text') return;
  const probe = { ...s, text: ta.value };
  const t = S.textSize(probe);
  ta.style.width = `${Math.max(60, t.w + s.style.fontSize)}px`;
  ta.style.height = `${t.h + 6}px`;
});
ta.addEventListener('keydown', e => {
  e.stopPropagation();
  if (e.key === 'Escape' || (e.key === 'Enter' && (e.ctrlKey || e.metaKey))) { e.preventDefault(); commitText(); }
});
ta.addEventListener('blur', () => { setTimeout(() => { if (st.editing && document.activeElement !== ta) commitText(); }, 0); });

function commitText() {
  const s = st.editing;
  if (!s) return;
  const text = ta.value.replace(/\s+$/, '');
  if (text !== s.text && !ta.dataset.isNew) checkpoint();
  s.text = text;
  if (s.kind === 'text' && !text) {
    const i = docShapes().indexOf(s);
    if (i >= 0) docShapes().splice(i, 1);
    if (ta.dataset.isNew) st.doc.undo.pop();
  }
  hideTextEditor(true);
}
function hideTextEditor(redraw) {
  st.editing = null;
  ta.hidden = true;
  ta.blur();
  if (redraw) render();
}

// ───────────────────────── barras ─────────────────────────

const bars = { tools: $('#tools'), actions: $('#actions'), rec: $('#recbar'), board: $('#boardbar') };
const pop = $('#pop');
const hint = $('#hint');

function btn(name, title, onClick, extra = '') {
  const b = document.createElement('button');
  b.className = `b ${extra}`;
  b.innerHTML = icon(name);
  b.title = title;
  b.addEventListener('pointerdown', e => e.stopPropagation());
  b.addEventListener('click', e => { e.stopPropagation(); onClick(b, e); });
  return b;
}
const sep = () => { const s = document.createElement('i'); s.className = 'sep'; return s; };

function toolButton(t) {
  const b = btn(t, `${TOOL_LABELS[t]}${TOOL_KEYS[t] ? ` (${TOOL_KEYS[t]})` : ''}`, () => setTool(t), 'tool');
  b.dataset.tool = t;
  return b;
}
function colorButton() {
  const b = document.createElement('button');
  b.className = 'b color';
  b.title = 'Cor e estilo (1–9 trocam a cor)';
  b.innerHTML = `<span class="dot" style="background:${st.style.color}"></span>`;
  b.addEventListener('pointerdown', e => e.stopPropagation());
  b.addEventListener('click', e => { e.stopPropagation(); togglePopover('style', b); });
  return b;
}

function buildBars() {
  closePopover();
  for (const b of Object.values(bars)) { b.innerHTML = ''; b.hidden = true; }
  hint.hidden = true;
  if (isBoard()) {
    const bb = bars.board;
    const grip = document.createElement('div');
    grip.className = 'grip'; grip.innerHTML = icon('grip'); grip.title = 'Arraste para mover a barra · duplo clique volta ao padrão';
    setupGrip(grip);
    bb.append(grip);
    ['select', 'pen', 'highlighter', 'line', 'arrow', 'rect', 'ellipse', 'diamond', 'text', 'sticky', 'step'].forEach(t => bb.append(toolButton(t)));
    bb.append(btn('library', 'Biblioteca de componentes', b => togglePopover('library', b)));
    bb.append(toolButton('eraser'), toolButton('laser'), sep(), colorButton(), sep());
    bb.append(btn('undo', 'Desfazer (Ctrl+Z)', undo), btn('redo', 'Refazer (Ctrl+Shift+Z)', redo), sep());
    bb.append(btn('layers', 'Fundo do quadro (G)', b => togglePopover('bg', b)), sep());
    bb.append(btn('copy', 'Copiar o quadro como imagem (Ctrl+C) — depois é só colar no chat ou e-mail', () => finish('copy')));
    bb.append(btn('save', 'Salvar o quadro na pasta (Ctrl+S)', () => finish('save')));
    bb.append(btn('more', 'Mais: salvar como, colar, limpar', b => togglePopover('more', b)));
    bb.append(btn('close', 'Fechar o quadro (Esc) — o desenho fica guardado', close, 'danger'));
    bb.hidden = false;
    placeBoardBar();
    markTool();
    return;
  }
  if (st.phase === 'choose') {
    hint.textContent = isRecord()
      ? 'Selecione a área que será gravada · clique numa janela ou em qualquer lugar para a tela inteira · Esc para sair'
      : 'Arraste para selecionar · clique numa janela · C copia a cor · Esc para sair';
    hint.hidden = false;
    return;
  }
  if (st.phase !== 'edit') return;
  if (isRecord()) {
    const rb = bars.rec;
    const go = document.createElement('button');
    go.className = 'b go'; go.innerHTML = `${icon('record')}<span>Gravar</span>`; go.title = 'Começar a gravar (Enter)';
    go.addEventListener('pointerdown', e => e.stopPropagation());
    go.addEventListener('click', startRecording);
    rb.append(go, sep());
    const mic = btn('mic', 'Gravar o microfone', b => { st.settings.mic = !st.settings.mic; b.classList.toggle('on', st.settings.mic); }, st.settings.mic ? 'on' : '');
    const sys = btn('speaker', 'Gravar o áudio do sistema', b => { st.settings.systemAudio = !st.settings.systemAudio; b.classList.toggle('on', st.settings.systemAudio); }, st.settings.systemAudio ? 'on' : '');
    rb.append(mic, sys, sep(), btn('fullscreen', 'Tela inteira', () => { st.sel = { x: 0, y: 0, w: W, h: H }; placeBars(); render(); }), btn('close', 'Cancelar (Esc)', close, 'danger'));
    rb.hidden = false;
    placeBars();
    return;
  }
  const tb = bars.tools;
  ['select', 'pen', 'highlighter', 'line', 'arrow', 'rect', 'ellipse', 'text', 'step', 'blur'].forEach(t => tb.append(toolButton(t)));
  tb.append(btn('library', 'Mais formas', b => togglePopover('library', b)));
  tb.append(toolButton('eraser'), sep(), colorButton(), sep(), btn('undo', 'Desfazer (Ctrl+Z)', undo), btn('redo', 'Refazer (Ctrl+Shift+Z)', redo));
  const ab = bars.actions;
  ab.append(
    btn('copy', 'Copiar (Ctrl+C)', () => finish('copy')),
    btn('save', 'Salvar na pasta (Ctrl+S)', () => finish('save')),
    btn('saveAs', 'Salvar como… (Ctrl+Shift+S)', () => finish('saveAs')),
    btn('pin', 'Fixar na tela (Ctrl+P)', () => finish('pin')),
    btn('ocr', 'Copiar o texto da imagem (Ctrl+T)', () => finish('ocr')),
    btn('record', 'Gravar esta área', () => { st.mode = 'record'; buildBars(); render(); }),
    sep(),
    btn('close', 'Cancelar (Esc)', close, 'danger'),
  );
  tb.hidden = false; ab.hidden = false;
  tb.classList.add('vertical');
  placeBars();
  markTool();
}
function hideBars() { for (const b of Object.values(bars)) b.hidden = true; hint.hidden = true; closePopover(); }

function placeBars() {
  if (isBoard() || !st.sel) return;
  const s = st.sel, m = 8;
  const tb = bars.tools, ab = isRecord() ? bars.rec : bars.actions;
  if (!tb.hidden) {
    const r = tb.getBoundingClientRect();
    let x = s.x + s.w + m;
    if (x + r.width > W - 4) x = s.x - r.width - m;
    if (x < 4) x = Math.max(4, s.x + s.w - r.width - m);
    let y = Math.max(4, Math.min(s.y, H - r.height - 4));
    tb.style.left = `${x}px`; tb.style.top = `${y}px`;
  }
  if (!ab.hidden) {
    const r = ab.getBoundingClientRect();
    let y = s.y + s.h + m;
    if (y + r.height > H - 4) y = s.y - r.height - m;
    if (y < 4) y = Math.max(4, s.y + s.h - r.height - m);
    const x = Math.max(4, Math.min(s.x + s.w - r.width, W - r.width - 4));
    ab.style.left = `${x}px`; ab.style.top = `${y}px`;
  }
}

// Barra do quadro: arrastável; vira vertical quando solta nas laterais. Nunca fica atrás do notch/câmera.
function placeBoardBar() {
  const bb = bars.board;
  let saved = null;
  try { saved = JSON.parse(localStorage.getItem('cp.board.bar') || 'null'); } catch { }
  bb.classList.toggle('vertical', !!(saved && saved.vertical));
  const r = bb.getBoundingClientRect();
  let x = saved ? saved.x : (W - r.width) / 2, y = saved ? saved.y : 14;
  x = Math.max(4, Math.min(x, W - r.width - 4)); y = Math.max(8, Math.min(y, H - r.height - 4));
  bb.style.left = `${x}px`; bb.style.top = `${y}px`;
}
function setupGrip(grip) {
  let start = null;
  grip.addEventListener('pointerdown', e => {
    e.stopPropagation();
    grip.setPointerCapture(e.pointerId);
    const r = bars.board.getBoundingClientRect();
    start = { x: e.clientX, y: e.clientY, left: r.left, top: r.top };
  });
  grip.addEventListener('pointermove', e => {
    if (!start) return;
    const bb = bars.board, r = bb.getBoundingClientRect();
    const x = Math.max(4, Math.min(start.left + e.clientX - start.x, W - r.width - 4));
    const y = Math.max(8, Math.min(start.top + e.clientY - start.y, H - r.height - 4));
    bb.style.left = `${x}px`; bb.style.top = `${y}px`;
  });
  grip.addEventListener('pointerup', e => {
    if (!start) return;
    start = null;
    const bb = bars.board, zone = 70;
    let vertical = bb.classList.contains('vertical');
    if (e.clientX < zone || e.clientX > W - zone) vertical = true;
    else if (e.clientY < zone || e.clientY > H - zone) vertical = false;
    bb.classList.toggle('vertical', vertical);
    const r = bb.getBoundingClientRect();
    let x = r.left, y = r.top;
    if (vertical && e.clientX < zone) x = 10;
    if (vertical && e.clientX > W - zone) x = W - r.width - 10;
    x = Math.max(4, Math.min(x, W - r.width - 4)); y = Math.max(8, Math.min(y, H - r.height - 4));
    bb.style.left = `${x}px`; bb.style.top = `${y}px`;
    localStorage.setItem('cp.board.bar', JSON.stringify({ x, y, vertical }));
  });
  grip.addEventListener('dblclick', () => { localStorage.removeItem('cp.board.bar'); placeBoardBar(); });
}

function markTool() {
  document.querySelectorAll('.b.tool').forEach(b => b.classList.toggle('active', b.dataset.tool === st.tool));
  const lib = S.LIBRARY.includes(st.tool);
  document.querySelectorAll('.b').forEach(b => { if (b.title.startsWith('Biblioteca') || b.title.startsWith('Mais formas')) b.classList.toggle('active', lib); });
  document.querySelectorAll('.b.color .dot').forEach(d => { d.style.background = st.style.color; });
}

function setTool(t) {
  if (st.editing) commitText();
  st.tool = t;
  if (t !== 'select') st.selected.clear();
  savePrefs(); markTool(); closePopover(); render();
}

// ───────────────────────── painéis ─────────────────────────

let popKind = null;
function closePopover() { pop.hidden = true; popKind = null; }
function togglePopover(kind, anchor) {
  if (popKind === kind) { closePopover(); return; }
  popKind = kind;
  pop.innerHTML = '';
  if (kind === 'style') buildStylePanel();
  if (kind === 'library') {
    const grid = document.createElement('div'); grid.className = 'lib';
    for (const k of S.LIBRARY) {
      const b = document.createElement('button');
      b.className = `libitem ${st.tool === k ? 'active' : ''}`;
      b.innerHTML = `${icon(k, 22)}<span>${S.KINDS[k]}</span>`;
      b.addEventListener('click', () => setTool(k));
      grid.append(b);
    }
    if (!isBoard()) {
      for (const k of ['diamond']) {
        const b = document.createElement('button');
        b.className = `libitem ${st.tool === k ? 'active' : ''}`;
        b.innerHTML = `${icon(k, 22)}<span>${S.KINDS[k]}</span>`;
        b.addEventListener('click', () => setTool(k));
        grid.prepend(b);
      }
    }
    pop.append(grid);
  }
  if (kind === 'bg') {
    for (const [k, label] of BACKGROUNDS) {
      const b = document.createElement('button');
      b.className = `row ${st.bg === k ? 'active' : ''}`;
      b.innerHTML = `<span class="sw bg-${k}"></span>${label}`;
      b.addEventListener('click', () => { setBg(k); closePopover(); });
      pop.append(b);
    }
  }
  if (kind === 'more') {
    const row = (ic, label, fn) => { const b = document.createElement('button'); b.className = 'row'; b.innerHTML = `${icon(ic, 16)}${label}`; b.addEventListener('click', () => { closePopover(); fn(); }); pop.append(b); };
    row('saveAs', 'Salvar como… (Ctrl+Shift+S)', () => finish('saveAs'));
    row('image', 'Colar imagem ou texto (Ctrl+V)', pasteFromClipboard);
    row('trash', 'Limpar o quadro', () => { if (docShapes().length) { checkpoint(); st.doc.shapes = []; st.selected.clear(); render(); } });
  }
  pop.hidden = false;
  const a = anchor.getBoundingClientRect(), r = pop.getBoundingClientRect();
  const vertical = anchor.closest('.vertical');
  let x, y;
  if (vertical) { x = a.right + 8; if (x + r.width > W - 4) x = a.left - r.width - 8; y = Math.min(a.top, H - r.height - 6); }
  else { x = Math.min(Math.max(4, a.left + a.width / 2 - r.width / 2), W - r.width - 4); y = a.bottom + 8; if (y + r.height > H - 4) y = a.top - r.height - 8; }
  pop.style.left = `${Math.max(4, x)}px`; pop.style.top = `${Math.max(4, y)}px`;
}
pop.addEventListener('pointerdown', e => e.stopPropagation());

function buildStylePanel() {
  const s = st.style;
  const pal = document.createElement('div'); pal.className = 'pal';
  S.PALETTE.forEach((c, i) => {
    const b = document.createElement('button');
    b.className = `sw ${s.color.toLowerCase() === c ? 'active' : ''}`; b.style.background = c; b.title = i < 9 ? `Tecla ${i + 1}` : c;
    b.addEventListener('click', () => { applyStyle({ color: c }); pal.querySelectorAll('.sw').forEach(x => x.classList.toggle('active', x === b)); });
    pal.append(b);
  });
  const custom = document.createElement('input'); custom.type = 'color'; custom.value = s.color.length === 7 ? s.color : '#ff3b30'; custom.title = 'Outra cor';
  custom.addEventListener('input', () => applyStyle({ color: custom.value }));
  pal.append(custom);
  pop.append(pal);

  const range = (label, min, max, val, fn) => {
    const w = document.createElement('label'); w.className = 'rng';
    w.innerHTML = `<span>${label}</span><input type="range" min="${min}" max="${max}" value="${val}"><b>${val}</b>`;
    const inp = w.querySelector('input'), out = w.querySelector('b');
    inp.addEventListener('input', () => { out.textContent = inp.value; fn(+inp.value); });
    pop.append(w);
  };
  range('Espessura', 1, 24, s.width, v => applyStyle({ width: v }));

  const seg = (label, opts, cur, fn) => {
    const w = document.createElement('div'); w.className = 'seg';
    w.innerHTML = `<span>${label}</span>`;
    const g = document.createElement('div'); g.className = 'segs';
    for (const [k, t] of opts) {
      const b = document.createElement('button'); b.textContent = t; b.className = cur === k ? 'active' : '';
      b.addEventListener('click', () => { fn(k); g.querySelectorAll('button').forEach(x => x.classList.toggle('active', x === b)); });
      g.append(b);
    }
    w.append(g); pop.append(w);
  };
  seg('Preenchimento', [['none', 'Nenhum'], ['soft', 'Suave'], ['solid', 'Sólido']], s.fill, v => applyStyle({ fill: v }));
  seg('Traço', [['plain', 'Contínuo'], ['dashed', 'Tracejado']], s.dashed ? 'dashed' : 'plain', v => applyStyle({ dashed: v === 'dashed' }));
  seg('Estilo', [['clean', 'Preciso'], ['sketchy', 'À mão']], s.sketchy ? 'sketchy' : 'clean', v => applyStyle({ sketchy: v === 'sketchy' }));
  const fw = document.createElement('div'); fw.className = 'seg';
  fw.innerHTML = '<span>Fonte</span>';
  const sel = document.createElement('select');
  for (const [k, t] of Object.entries(S.FONT_LABELS)) { const o = document.createElement('option'); o.value = k; o.textContent = t; o.selected = s.font === k; sel.append(o); }
  sel.addEventListener('change', () => applyStyle({ font: sel.value }));
  fw.append(sel); pop.append(fw);
  range('Tamanho do texto', 12, 96, s.fontSize, v => applyStyle({ fontSize: v }));
}

function applyStyle(patch) {
  Object.assign(st.style, patch);
  const sel = selectedShapes();
  if (sel.length) {
    checkpoint();
    for (const s of sel) Object.assign(s.style, patch);
    pixCache.clear();
  }
  savePrefs(); markTool(); render();
}
function syncStyleFromSelection() {
  const sel = selectedShapes();
  if (sel.length === 1) { st.style = { ...st.style, ...sel[0].style }; markTool(); }
}

function setBg(k) {
  st.bg = k;
  localStorage.setItem('cp.board.bg', k);
  pixCache.clear(); render();
}

// ───────────────────────── ações ─────────────────────────

function exportCanvas() {
  const sc = st.scale;
  const r = isBoard() ? { x: 0, y: 0, w: W, h: H } : st.sel;
  const cw = Math.max(1, Math.round(r.w * sc)), ch = Math.max(1, Math.round(r.h * sc));
  const c = document.createElement('canvas');
  c.width = cw; c.height = ch;
  const x = c.getContext('2d');
  if (isBoard()) { x.setTransform(sc, 0, 0, sc, 0, 0); drawBackground(x, W, H); }
  else if (st.frame) x.drawImage(st.frame.bmp, Math.round(r.x * sc), Math.round(r.y * sc), cw, ch, 0, 0, cw, ch);
  x.setTransform(sc, 0, 0, sc, -r.x * sc, -r.y * sc);
  S.draw(x, docShapes(), envAt(sc));
  return c;
}
const toPng = c => new Promise(res => c.toBlob(b => b.arrayBuffer().then(res), 'image/png'));

let busy = false;
async function finish(action) {
  if (busy || (!isBoard() && (!st.sel || st.sel.w < 2 || st.sel.h < 2))) return;
  busy = true;
  try {
    if (st.editing) commitText();
    st.selected.clear();
    const canvas = exportCanvas();
    const headers = { 'x-action': action, 'x-keep': isBoard() ? '1' : '0' };
    if (action === 'pin') { headers['x-pin-x'] = String(screenX + st.sel.x); headers['x-pin-y'] = String(screenY + st.sel.y); }
    if (!isBoard()) await invoke('editor_close');
    const png = await toPng(canvas);
    await invoke('editor_finish', new Uint8Array(png), { headers });
    if (!isBoard()) resetCapture();
  } catch (e) {
    invoke('log', { msg: `finish ${action}: ${e}` });
  } finally {
    busy = false;
  }
}

async function startRecording() {
  if (!st.sel) return;
  const sc = st.scale, s = st.sel;
  const args = { x: Math.round(s.x * sc), y: Math.round(s.y * sc), w: Math.round(s.w * sc), h: Math.round(s.h * sc), mic: !!st.settings.mic, systemAudio: !!st.settings.systemAudio };
  resetCapture();
  try { await invoke('start_recording', args); } catch (e) { invoke('log', { msg: `gravação: ${e}` }); }
}

function resetCapture() {
  st.doc = newDoc(); st.selected.clear(); st.sel = null; st.phase = 'choose';
  if (st.frame && st.frame.bmp) st.frame.bmp.close();
  st.frame = null;
  hideBars();
}

function close() {
  if (st.editing) hideTextEditor(false);
  invoke('editor_close');
  if (!isBoard()) resetCapture();
  closePopover();
}

async function pasteFromClipboard() {
  const at = st.mouse.in ? [st.mouse.x, st.mouse.y] : [W / 2, H / 2];
  try {
    const buf = await invoke('clipboard_image');
    const bytes = buf instanceof ArrayBuffer ? buf : new Uint8Array(buf).buffer;
    if (bytes.byteLength > 0) {
      const bmp = await createImageBitmap(new Blob([bytes], { type: 'image/png' }));
      const id = `img${Date.now()}`;
      images.set(id, bmp);
      const k = Math.min(1, (W * 0.6) / (bmp.width / st.scale), (H * 0.6) / (bmp.height / st.scale));
      const w = (bmp.width / st.scale) * k, h = (bmp.height / st.scale) * k;
      checkpoint();
      const s = S.newShape('image', [[at[0] - w / 2, at[1] - h / 2], [at[0] + w / 2, at[1] + h / 2]], { ...st.style, fill: 'none' });
      s.img = id;
      docShapes().push(s);
      setTool('select'); st.selected.add(s.id); render();
      return;
    }
    const text = await invoke('clipboard_text');
    if (text && text.trim()) {
      checkpoint();
      const s = S.newShape('text', [[at[0], at[1]]], st.style);
      s.text = text.trim().slice(0, 5000);
      docShapes().push(s);
      render();
    }
  } catch (e) { invoke('log', { msg: `colar: ${e}` }); }
}

// ───────────────────────── teclado ─────────────────────────

addEventListener('keydown', e => {
  if (st.editing) return;
  const ctrl = e.ctrlKey || e.metaKey, k = e.key.toLowerCase();
  if (e.key === 'Escape') {
    e.preventDefault();
    if (popKind) closePopover();
    else if (st.drag) { st.drag = null; render(); }
    else if (st.selected.size) { st.selected.clear(); render(); }
    else close();
    return;
  }
  if (!isBoard() && st.phase === 'choose') {
    if (k === 'c' && !ctrl) { const p = pixelAt(st.mouse.x, st.mouse.y); if (p) { invoke('copy_text', { text: p.hex, toast: `Cor ${p.hex} copiada` }); close(); } }
    if (e.key === 'Enter') { st.sel = st.hover ? { ...st.hover } : { x: 0, y: 0, w: W, h: H }; st.phase = 'edit'; buildBars(); render(); }
    return;
  }
  if (isRecord()) { if (e.key === 'Enter') startRecording(); return; }
  if (st.phase !== 'edit' && !isBoard()) return;

  if (ctrl && k === 'z') { e.preventDefault(); e.shiftKey ? redo() : undo(); return; }
  if (ctrl && k === 'y') { e.preventDefault(); redo(); return; }
  if (ctrl && k === 'c') { e.preventDefault(); finish('copy'); return; }
  if (ctrl && k === 's') { e.preventDefault(); finish(e.shiftKey ? 'saveAs' : 'save'); return; }
  if (ctrl && k === 'p' && !isBoard()) { e.preventDefault(); finish('pin'); return; }
  if (ctrl && k === 't' && !isBoard()) { e.preventDefault(); finish('ocr'); return; }
  if (ctrl && k === 'v' && isBoard()) { e.preventDefault(); pasteFromClipboard(); return; }
  if (ctrl && k === 'a') { e.preventDefault(); setTool('select'); docShapes().forEach(s => st.selected.add(s.id)); render(); return; }
  if (ctrl && k === 'd') {
    e.preventDefault();
    const sel = selectedShapes();
    if (!sel.length) return;
    checkpoint(); st.selected.clear();
    for (const s of sel) { const c = structuredClone(s); c.id = S.newShape(s.kind, [], s.style).id; S.move(c, 16, 16); docShapes().push(c); st.selected.add(c.id); }
    render(); return;
  }
  if (e.key === 'Enter' && st.selected.size === 1) {
    const one = selectedShapes()[0];
    if (one && (one.kind === 'text' || S.acceptsLabel(one.kind))) { e.preventDefault(); editText(one); return; }
  }
  if (e.key === 'Enter' && !isBoard()) { e.preventDefault(); finish(st.settings.enterAction || 'copy'); return; }
  if ((e.key === 'Delete' || e.key === 'Backspace') && st.selected.size) {
    e.preventDefault(); checkpoint();
    st.doc.shapes = docShapes().filter(s => !st.selected.has(s.id)); st.selected.clear(); render(); return;
  }
  if (e.key.startsWith('Arrow') && st.selected.size) {
    e.preventDefault();
    const d = e.shiftKey ? 10 : 1;
    const [dx, dy] = { ArrowLeft: [-d, 0], ArrowRight: [d, 0], ArrowUp: [0, -d], ArrowDown: [0, d] }[e.key];
    checkpoint(); selectedShapes().forEach(s => S.move(s, dx, dy)); render(); return;
  }
  if (ctrl || e.altKey) return;
  if (/^[1-9]$/.test(e.key)) { applyStyle({ color: S.PALETTE[+e.key - 1] }); return; }
  if (isBoard() && k === 'g') { const i = BACKGROUNDS.findIndex(b => b[0] === st.bg); setBg(BACKGROUNDS[(i + 1) % BACKGROUNDS.length][0]); return; }
  const tool = Object.entries(TOOL_KEYS).find(([, key]) => key.toLowerCase() === k);
  if (tool) {
    const t = tool[0];
    if (!isBoard() && t === 'laser') return;
    setTool(t);
  }
});

layout();
