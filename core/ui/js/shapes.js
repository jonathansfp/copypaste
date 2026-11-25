// Motor de desenho vetorial (porte do app de Mac): formas, traço à mão, setas, rótulos e desfoque.
// Coordenadas em pixels CSS; na exportação o contexto é escalado para a resolução nativa da tela.

export const PALETTE = ['#ff3b30', '#ff9500', '#ffcc00', '#34c759', '#00c7be', '#007aff',
  '#5856d6', '#af52de', '#ff2d55', '#1c1c1e', '#8e8e93', '#ffffff'];

export const FONTS = {
  system: '"Segoe UI Variable Text","Segoe UI",Ubuntu,Cantarell,"Noto Sans",system-ui,sans-serif',
  rounded: '"Nunito","Varela Round","Segoe UI",Ubuntu,"Noto Sans",system-ui,sans-serif',
  hand: '"Segoe Print","Comic Neue","Comic Sans MS","Chalkboard SE","Kalam",cursive',
  serif: 'Georgia,"Noto Serif","DejaVu Serif","Times New Roman",serif',
  mono: '"Cascadia Code",Consolas,"JetBrains Mono","DejaVu Sans Mono",monospace',
};
export const FONT_LABELS = { system: 'Sistema', rounded: 'Arredondada', hand: 'Manuscrita', serif: 'Serifada', mono: 'Código' };

export const KINDS = {
  pen: 'Caneta', highlighter: 'Marca-texto', line: 'Linha', arrow: 'Seta', doubleArrow: 'Seta dupla',
  rect: 'Retângulo', ellipse: 'Elipse', diamond: 'Losango', text: 'Texto', step: 'Passo numerado',
  sticky: 'Nota adesiva', blur: 'Desfocar / ocultar', image: 'Imagem', cylinder: 'Banco de dados',
  person: 'Pessoa', cloud: 'Nuvem', bubble: 'Balão de fala', star: 'Estrela', check: 'Certo',
  cross: 'Errado', browser: 'Janela / navegador', phone: 'Celular',
};
export const LIBRARY = ['sticky', 'cylinder', 'person', 'cloud', 'bubble', 'browser', 'phone', 'star', 'check', 'cross', 'doubleArrow'];

export const isLinear = k => k === 'line' || k === 'arrow' || k === 'doubleArrow';
export const isFreehand = k => k === 'pen' || k === 'highlighter';
export const isPoint = k => k === 'step' || k === 'text';
export const isBox = k => !isLinear(k) && !isFreehand(k) && !isPoint(k);
export const acceptsLabel = k => ['rect', 'ellipse', 'diamond', 'sticky', 'cylinder', 'cloud', 'bubble', 'browser', 'phone'].includes(k);

export function defaultStyle() {
  return { color: '#ff3b30', width: 4, fill: 'none', dashed: false, sketchy: false, font: 'system', fontSize: 26 };
}

let idSeq = 0;
export function newShape(kind, pts, style) {
  return { id: `s${Date.now().toString(36)}${(idSeq++).toString(36)}`, kind, pts, style: { ...style }, text: '', number: 0, img: null, seed: (Math.random() * 2 ** 31) | 0 || 7 };
}

// ── cores ──
function rgb(hex) {
  let h = hex.replace('#', '');
  if (h.length === 3) h = h.split('').map(c => c + c).join('');
  const n = parseInt(h.slice(0, 6), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
export const rgba = (hex, a) => { const [r, g, b] = rgb(hex); return `rgba(${r},${g},${b},${a})`; };
export function mix(hex, other, f) {
  const a = rgb(hex), b = rgb(other);
  return `rgb(${a.map((v, i) => Math.round(v + (b[i] - v) * f)).join(',')})`;
}
export function contrast(hex) {
  const [r, g, b] = rgb(hex);
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.6 ? '#1a1a1a' : '#ffffff';
}

// ── geometria ──
export function rectOf(s) {
  const a = s.pts[0] || [0, 0], b = s.pts[s.pts.length - 1] || a;
  return { x: Math.min(a[0], b[0]), y: Math.min(a[1], b[1]), w: Math.abs(a[0] - b[0]), h: Math.abs(a[1] - b[1]) };
}
const inset = (r, dx, dy = dx) => ({ x: r.x + dx, y: r.y + dy, w: r.w - 2 * dx, h: r.h - 2 * dy });
export const stepRadius = s => 11 + s.style.width * 2.2;

const mctx = document.createElement('canvas').getContext('2d');
export const fontOf = (st, size = st.fontSize, weight = 600) => `${weight} ${size}px ${FONTS[st.font] || FONTS.system}`;

export function textSize(s) {
  mctx.font = fontOf(s.style);
  const lines = (s.text || ' ').split('\n');
  const w = Math.max(...lines.map(l => mctx.measureText(l || ' ').width), s.style.fontSize * 0.5);
  return { w: Math.ceil(w), h: Math.ceil(lines.length * s.style.fontSize * 1.25) };
}

export function bounds(s) {
  const st = s.style;
  switch (s.kind) {
    case 'text': {
      const o = s.pts[0], t = textSize(s), pad = st.fill === 'none' ? 0 : 8;
      return { x: o[0] - pad, y: o[1] - pad / 2, w: t.w + pad * 2, h: t.h + pad };
    }
    case 'step': {
      const c = s.pts[0], r = stepRadius(s);
      return { x: c[0] - r, y: c[1] - r, w: r * 2, h: r * 2 };
    }
    case 'pen': case 'highlighter': {
      let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
      for (const [x, y] of s.pts) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
      const w = s.kind === 'highlighter' ? st.width * 3 : st.width;
      return inset({ x: x0, y: y0, w: x1 - x0, h: y1 - y0 }, -w);
    }
    case 'line': case 'arrow': case 'doubleArrow':
      return inset(rectOf(s), -(st.width * 4 + 6));
    default:
      return inset(rectOf(s), -st.width - 2);
  }
}

// Caminhos como lista de comandos: ['M',x,y] ['L',x,y] ['Q',cx,cy,x,y] ['C',c1x,c1y,c2x,c2y,x,y] ['Z']
const K = 0.5522847;
function ellipseCmds(cx, cy, rx, ry) {
  return [['M', cx + rx, cy], ['C', cx + rx, cy + ry * K, cx + rx * K, cy + ry, cx, cy + ry],
    ['C', cx - rx * K, cy + ry, cx - rx, cy + ry * K, cx - rx, cy], ['C', cx - rx, cy - ry * K, cx - rx * K, cy - ry, cx, cy - ry],
    ['C', cx + rx * K, cy - ry, cx + rx, cy - ry * K, cx + rx, cy], ['Z']];
}
function roundRectCmds(r, cr) {
  cr = Math.max(0, Math.min(cr, r.w / 2, r.h / 2));
  const { x, y, w, h } = r, k = cr * (1 - K);
  if (cr < 0.5) return [['M', x, y], ['L', x + w, y], ['L', x + w, y + h], ['L', x, y + h], ['Z']];
  return [['M', x + cr, y], ['L', x + w - cr, y], ['C', x + w - k, y, x + w, y + k, x + w, y + cr], ['L', x + w, y + h - cr],
    ['C', x + w, y + h - k, x + w - k, y + h, x + w - cr, y + h], ['L', x + cr, y + h], ['C', x + k, y + h, x, y + h - k, x, y + h - cr],
    ['L', x, y + cr], ['C', x, y + k, x + k, y, x + cr, y], ['Z']];
}
function smoothCmds(pts) {
  if (!pts.length) return [];
  const c = [['M', ...pts[0]]];
  if (pts.length < 3) { pts.slice(1).forEach(p => c.push(['L', ...p])); if (pts.length === 1) c.push(['L', pts[0][0] + 0.01, pts[0][1]]); return c; }
  for (let i = 1; i < pts.length - 1; i++) {
    const m = [(pts[i][0] + pts[i + 1][0]) / 2, (pts[i][1] + pts[i + 1][1]) / 2];
    c.push(['Q', pts[i][0], pts[i][1], m[0], m[1]]);
  }
  c.push(['L', ...pts[pts.length - 1]]);
  return c;
}

export function outline(s) {
  const r = rectOf(s), { x, y, w, h } = r, mx = x + w / 2, my = y + h / 2, X = x + w, Y = y + h;
  switch (s.kind) {
    case 'pen': case 'highlighter': return smoothCmds(s.pts);
    case 'line': case 'arrow': case 'doubleArrow': {
      const a = s.pts[0], b = s.pts[s.pts.length - 1];
      return [['M', ...a], ['L', ...b]];
    }
    case 'rect': case 'blur': case 'image': case 'text': case 'step':
      return roundRectCmds(r, s.style.sketchy ? 0 : Math.min(8, Math.min(w, h) / 5));
    case 'sticky': return roundRectCmds(r, 3);
    case 'ellipse': return ellipseCmds(mx, my, w / 2, h / 2);
    case 'diamond': return [['M', mx, y], ['L', X, my], ['L', mx, Y], ['L', x, my], ['Z']];
    case 'cylinder': {
      const ry = Math.min(h * 0.15, w * 0.18);
      return [...ellipseCmds(mx, y + ry, w / 2, ry), ['M', x, y + ry], ['L', x, Y - ry],
        ['C', x, Y - ry + ry * K, mx - w / 2 * K, Y, mx, Y], ['C', mx + w / 2 * K, Y, X, Y - ry + ry * K, X, Y - ry], ['L', X, y + ry]];
    }
    case 'person': {
      const hd = Math.min(w, h) * 0.22, hip = y + h * 0.66;
      return [...ellipseCmds(mx, y + hd, hd, hd), ['M', mx, y + hd * 2], ['L', mx, hip],
        ['M', x + w * 0.12, y + h * 0.42], ['L', mx, y + h * 0.36], ['L', X - w * 0.12, y + h * 0.42],
        ['M', x + w * 0.2, Y], ['L', mx, hip], ['L', X - w * 0.2, Y]];
    }
    case 'cloud':
      return [['M', x + w * 0.2, Y - h * 0.08],
        ['C', x - w * 0.05, Y - h * 0.1, x - w * 0.02, y + h * 0.5, x + w * 0.12, y + h * 0.45],
        ['C', x + w * 0.1, y + h * 0.18, x + w * 0.3, y + h * 0.08, x + w * 0.42, y + h * 0.14],
        ['C', x + w * 0.52, y - h * 0.08, x + w * 0.8, y + h * 0.02, x + w * 0.8, y + h * 0.3],
        ['C', X + w * 0.04, y + h * 0.32, X + w * 0.08, Y - h * 0.12, x + w * 0.86, Y - h * 0.08], ['Z']];
    case 'bubble': {
      const bh = h * 0.78, by = y + bh, cr = Math.min(14, Math.min(w, bh) / 4);
      return [['M', x + cr, y], ['L', X - cr, y], ['Q', X, y, X, y + cr], ['L', X, by - cr], ['Q', X, by, X - cr, by],
        ['L', x + w * 0.34, by], ['L', x + w * 0.16, Y], ['L', x + w * 0.2, by], ['L', x + cr, by], ['Q', x, by, x, by - cr],
        ['L', x, y + cr], ['Q', x, y, x + cr, y], ['Z']];
    }
    case 'star': {
      const c = [];
      for (let i = 0; i < 10; i++) {
        const rad = i % 2 === 0 ? 1 : 0.42, a = -Math.PI / 2 + i * Math.PI / 5;
        c.push([i ? 'L' : 'M', mx + Math.cos(a) * w / 2 * rad, my + Math.sin(a) * h / 2 * rad]);
      }
      c.push(['Z']);
      return c;
    }
    case 'check': return [['M', x, y + h * 0.55], ['L', x + w * 0.38, Y], ['L', X, y]];
    case 'cross': return [['M', x, y], ['L', X, Y], ['M', X, y], ['L', x, Y]];
    case 'browser': {
      const c = [...roundRectCmds(r, 8), ['M', x, y + 22], ['L', X, y + 22]];
      for (let i = 0; i < 3; i++) c.push(...ellipseCmds(x + 12.5 + i * 12, y + 10.5, 3.5, 3.5));
      return c;
    }
    case 'phone': {
      const cr = Math.min(w, h) * 0.14, nw = w * 0.3;
      return [...roundRectCmds(r, cr), ...roundRectCmds({ x: mx - nw / 2, y: y + h * 0.03, w: nw, h: Math.max(4, h * 0.025) }, 3)];
    }
    default: return roundRectCmds(r, 0);
  }
}

function fillOutline(s) {
  const r = rectOf(s);
  if (s.kind === 'browser') return roundRectCmds(r, 8);
  if (s.kind === 'phone') return roundRectCmds(r, Math.min(r.w, r.h) * 0.14);
  if (s.kind === 'cylinder') {
    const ry = Math.min(r.h * 0.15, r.w * 0.18);
    return [...roundRectCmds({ x: r.x, y: r.y + ry, w: r.w, h: r.h - ry * 2 }, 0), ...ellipseCmds(r.x + r.w / 2, r.y + ry, r.w / 2, ry), ...ellipseCmds(r.x + r.w / 2, r.y + r.h - ry, r.w / 2, ry)];
  }
  return null;
}

export function toPath(cmds) {
  const p = new Path2D();
  for (const c of cmds) {
    switch (c[0]) {
      case 'M': p.moveTo(c[1], c[2]); break;
      case 'L': p.lineTo(c[1], c[2]); break;
      case 'Q': p.quadraticCurveTo(c[1], c[2], c[3], c[4]); break;
      case 'C': p.bezierCurveTo(c[1], c[2], c[3], c[4], c[5], c[6]); break;
      case 'Z': p.closePath(); break;
    }
  }
  return p;
}

// Achata o caminho em polilinhas (para o traço à mão).
function flatten(cmds, step) {
  const out = []; let cur = [], start = [0, 0], last = [0, 0];
  const finish = closed => { if (cur.length > 1) out.push({ pts: cur, closed }); cur = []; };
  const seg = b => {
    const n = Math.max(1, Math.floor(Math.hypot(b[0] - last[0], b[1] - last[1]) / step));
    for (let i = 1; i <= n; i++) { const t = i / n; cur.push([last[0] + (b[0] - last[0]) * t, last[1] + (b[1] - last[1]) * t]); }
    last = b;
  };
  for (const c of cmds) {
    if (c[0] === 'M') { finish(false); start = [c[1], c[2]]; last = start; cur = [start]; }
    else if (c[0] === 'L') seg([c[1], c[2]]);
    else if (c[0] === 'Q') {
      const a = last, q = [c[1], c[2]], b = [c[3], c[4]];
      const n = Math.max(4, Math.floor((Math.hypot(q[0] - a[0], q[1] - a[1]) + Math.hypot(b[0] - q[0], b[1] - q[1])) / step));
      for (let i = 1; i <= n; i++) { const t = i / n, m = 1 - t; cur.push([m * m * a[0] + 2 * m * t * q[0] + t * t * b[0], m * m * a[1] + 2 * m * t * q[1] + t * t * b[1]]); }
      last = b;
    } else if (c[0] === 'C') {
      const a = last, c1 = [c[1], c[2]], c2 = [c[3], c[4]], b = [c[5], c[6]];
      const len = Math.hypot(c1[0] - a[0], c1[1] - a[1]) + Math.hypot(c2[0] - c1[0], c2[1] - c1[1]) + Math.hypot(b[0] - c2[0], b[1] - c2[1]);
      const n = Math.max(4, Math.floor(len / step));
      for (let i = 1; i <= n; i++) {
        const t = i / n, m = 1 - t;
        cur.push([m * m * m * a[0] + 3 * m * m * t * c1[0] + 3 * m * t * t * c2[0] + t * t * t * b[0],
          m * m * m * a[1] + 3 * m * m * t * c1[1] + 3 * m * t * t * c2[1] + t * t * t * b[1]]);
      }
      last = b;
    } else if (c[0] === 'Z') {
      if (Math.hypot(start[0] - last[0], start[1] - last[1]) > 0.5) seg(start);
      finish(true); last = start;
    }
  }
  finish(false);
  return out;
}

function rng(seed) {
  let s = seed >>> 0 || 0x9e3779b9;
  return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
}

function catmull(ctx, pts, closed) {
  const n = pts.length;
  ctx.beginPath();
  ctx.moveTo(pts[0][0], pts[0][1]);
  for (let i = 0; i < n - 1; i++) {
    const p0 = i > 0 ? pts[i - 1] : (closed ? pts[n - 1] : pts[i]), p1 = pts[i], p2 = pts[i + 1];
    const p3 = i + 2 < n ? pts[i + 2] : (closed ? pts[(i + 2) % n] : p2);
    ctx.bezierCurveTo(p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6, p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6, p2[0], p2[1]);
  }
  ctx.stroke();
}

// Traço "à mão": tremido estável (mesma semente) e duas passadas, como um marcador real.
function strokeRough(ctx, cmds, seed, width, passes = 2) {
  const rand = rng(seed), amp = 0.9 + width * 0.35;
  for (const sub of flatten(cmds, 14)) {
    for (let pass = 0; pass < passes; pass++) {
      const pts = sub.pts.map(([x, y]) => [x + (rand() * 2 - 1) * amp, y + (rand() * 2 - 1) * amp]);
      if (sub.closed && pass === 1 && pts.length > 2) pts.push(pts[1]);
      ctx.lineWidth = pass === 0 ? width : Math.max(1, width * 0.7);
      catmull(ctx, pts, sub.closed && pass === 0);
    }
  }
}

// ── desenho ──
export function draw(ctx, shapes, env) { for (const s of shapes) drawShape(ctx, s, env); }

export function drawShape(ctx, s, env) {
  const st = s.style;
  ctx.save();
  ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  ctx.lineWidth = st.width; ctx.strokeStyle = st.color; ctx.fillStyle = st.color;
  if (st.dashed) ctx.setLineDash([st.width * 2.5, st.width * 2.2]);
  switch (s.kind) {
    case 'blur': {
      const r = rectOf(s), px = env && env.pixelate ? env.pixelate(r) : null;
      if (px) { ctx.imageSmoothingEnabled = false; ctx.drawImage(px, r.x, r.y, r.w, r.h); }
      else { ctx.fillStyle = 'rgba(128,128,128,0.92)'; ctx.fillRect(r.x, r.y, r.w, r.h); }
      break;
    }
    case 'image': {
      const r = rectOf(s), img = env && env.images && env.images.get(s.img);
      if (img) ctx.drawImage(img, r.x, r.y, r.w, r.h);
      break;
    }
    case 'text': drawText(ctx, s, env); break;
    case 'step': drawStep(ctx, s, env); break;
    case 'highlighter':
      ctx.globalCompositeOperation = 'multiply';
      ctx.strokeStyle = rgba(st.color, 0.42); ctx.lineWidth = st.width * 3; ctx.lineCap = 'butt';
      ctx.setLineDash([]);
      ctx.stroke(toPath(outline(s)));
      break;
    case 'pen':
      if (st.sketchy) strokeRough(ctx, outline(s), s.seed, st.width, 1);
      else ctx.stroke(toPath(outline(s)));
      break;
    case 'line': case 'arrow': case 'doubleArrow': drawLinear(ctx, s); break;
    default: drawBox(ctx, s, env);
  }
  ctx.restore();
}

function drawStep(ctx, s, env) {
  const [cx, cy] = s.pts[0], r = stepRadius(s), scale = (env && env.scale) || 1;
  ctx.setLineDash([]);
  ctx.shadowColor = 'rgba(0,0,0,0.35)'; ctx.shadowBlur = 3 * scale; ctx.shadowOffsetY = 1 * scale;
  ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.fillStyle = s.style.color; ctx.fill();
  ctx.shadowColor = 'transparent';
  ctx.lineWidth = 2; ctx.strokeStyle = '#fff';
  ctx.beginPath(); ctx.arc(cx, cy, r - 1, 0, Math.PI * 2); ctx.stroke();
  ctx.fillStyle = contrast(s.style.color);
  ctx.font = `700 ${r * 1.05}px ${FONTS.system}`;
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillText(String(s.number), cx, cy + r * 0.04);
}

function drawText(ctx, s, env) {
  const [ox, oy] = s.pts[0], st = s.style, t = textSize(s), scale = (env && env.scale) || 1;
  ctx.setLineDash([]);
  let color = st.color;
  if (st.fill !== 'none') {
    ctx.fillStyle = st.fill === 'solid' ? st.color : 'rgba(255,255,255,0.88)';
    ctx.fill(toPath(roundRectCmds({ x: ox - 8, y: oy - 4, w: t.w + 16, h: t.h + 8 }, 6)));
    if (st.fill === 'solid') color = contrast(st.color);
  } else {
    // Contorno sutil para o texto continuar legível sobre qualquer fundo.
    ctx.shadowColor = rgba(contrast(st.color) === '#ffffff' ? '#ffffff' : '#000000', 0.55);
    ctx.shadowBlur = 3 * scale;
  }
  ctx.fillStyle = color;
  ctx.font = fontOf(st);
  ctx.textBaseline = 'top';
  const lh = st.fontSize * 1.25;
  (s.text || '').split('\n').forEach((line, i) => ctx.fillText(line, ox, oy + i * lh + st.fontSize * 0.1));
}

function drawLinear(ctx, s) {
  const st = s.style, a = s.pts[0], b = s.pts[s.pts.length - 1];
  const head = Math.max(12, st.width * 3.6), len = Math.hypot(b[0] - a[0], b[1] - a[1]), ang = Math.atan2(b[1] - a[1], b[0] - a[0]);
  const sharp = !st.sketchy && s.kind !== 'line';
  let start = a, end = b;
  if (sharp && len > head) {
    end = [b[0] - Math.cos(ang) * head * 0.6, b[1] - Math.sin(ang) * head * 0.6];
    if (s.kind === 'doubleArrow') start = [a[0] + Math.cos(ang) * head * 0.6, a[1] + Math.sin(ang) * head * 0.6];
  }
  const shaft = [['M', ...start], ['L', ...end]];
  if (st.sketchy) strokeRough(ctx, shaft, s.seed, st.width); else ctx.stroke(toPath(shaft));
  if (s.kind === 'line') return;
  ctx.setLineDash([]);
  const headCmds = (tip, an) => {
    const sp = Math.PI / 7;
    const c = [['M', tip[0] - Math.cos(an - sp) * head, tip[1] - Math.sin(an - sp) * head], ['L', ...tip],
      ['L', tip[0] - Math.cos(an + sp) * head, tip[1] - Math.sin(an + sp) * head]];
    if (sharp) c.push(['Z']);
    return c;
  };
  const heads = [headCmds(b, ang)];
  if (s.kind === 'doubleArrow') heads.push(headCmds(a, ang + Math.PI));
  for (const h of heads) {
    if (sharp) { const p = toPath(h); ctx.fill(p); ctx.stroke(p); }
    else strokeRough(ctx, h, s.seed + 7, st.width);
  }
}

export function labelRect(s) {
  const r = rectOf(s);
  switch (s.kind) {
    case 'diamond': return inset(r, r.w * 0.12, r.h * 0.2);
    case 'ellipse': case 'cloud': return inset(r, r.w * 0.15, r.h * 0.15);
    case 'cylinder': return { x: r.x + 8, y: r.y + Math.min(r.h * 0.25, r.w * 0.2), w: r.w - 16, h: r.h * 0.7 };
    case 'bubble': return { x: r.x + 10, y: r.y + 6, w: r.w - 20, h: r.h * 0.78 - 12 };
    case 'browser': return { x: r.x + 10, y: r.y + 30, w: r.w - 20, h: r.h - 40 };
    case 'phone': return inset(r, r.w * 0.12, r.h * 0.12);
    default: return inset(r, 10, 8);
  }
}

export function wrap(ctx, text, maxW) {
  const out = [];
  for (const para of text.split('\n')) {
    const words = para.split(/(\s+)/);
    let line = '';
    for (const w of words) {
      const test = line + w;
      if (ctx.measureText(test).width > maxW && line.trim()) { out.push(line.trimEnd()); line = w.trimStart(); }
      else line = test;
      // Palavra maior que a largura: quebra por letras.
      while (ctx.measureText(line).width > maxW && line.length > 1) {
        let i = line.length - 1;
        while (i > 1 && ctx.measureText(line.slice(0, i)).width > maxW) i--;
        out.push(line.slice(0, i)); line = line.slice(i);
      }
    }
    out.push(line);
  }
  return out;
}

function drawBox(ctx, s, env) {
  const st = s.style, r = rectOf(s);
  if (r.w < 0.5 && r.h < 0.5) return;
  const cmds = outline(s), path = toPath(cmds);
  let fill = null;
  if (st.fill === 'none') fill = s.kind === 'sticky' ? mix(st.color, '#ffffff', 0.72) : null;
  else if (st.fill === 'soft') fill = rgba(st.color, 0.18);
  else fill = s.kind === 'sticky' ? mix(st.color, '#ffffff', 0.45) : st.color;
  const scale = (env && env.scale) || 1;
  if (s.kind === 'sticky') {
    ctx.save();
    ctx.shadowColor = 'rgba(0,0,0,0.25)'; ctx.shadowBlur = 8 * scale; ctx.shadowOffsetY = 3 * scale;
    ctx.fillStyle = fill; ctx.fill(path);
    ctx.restore();
  } else if (fill && !['check', 'cross', 'person'].includes(s.kind)) {
    ctx.fillStyle = fill;
    const fo = fillOutline(s);
    ctx.fill(fo ? toPath(fo) : path);
  }
  if (s.kind !== 'sticky') {
    if (st.sketchy) strokeRough(ctx, cmds, s.seed, st.width); else ctx.stroke(path);
  }
  if (acceptsLabel(s.kind) && s.text) {
    const inner = labelRect(s);
    ctx.setLineDash([]);
    ctx.font = fontOf(st);
    ctx.fillStyle = s.kind === 'sticky' ? '#1f1f1f' : (st.fill === 'solid' ? contrast(st.color) : st.color);
    ctx.textAlign = 'center'; ctx.textBaseline = 'top';
    const lines = wrap(ctx, s.text, Math.max(10, inner.w)), lh = st.fontSize * 1.25;
    const top = inner.y + inner.h / 2 - (lines.length * lh) / 2;
    lines.forEach((l, i) => ctx.fillText(l, inner.x + inner.w / 2, top + i * lh + st.fontSize * 0.1));
  }
}

// ── seleção ──
const hctx = document.createElement('canvas').getContext('2d');
const inRect = (r, x, y, t = 0) => x >= r.x - t && x <= r.x + r.w + t && y >= r.y - t && y <= r.y + r.h + t;

export function hitTest(s, x, y, tol = 6) {
  switch (s.kind) {
    case 'text': case 'step': case 'sticky': case 'blur': case 'image': case 'browser': case 'phone':
      return inRect(bounds(s), x, y, tol);
    case 'pen': case 'highlighter': case 'line': case 'arrow': case 'doubleArrow': case 'check': case 'cross': case 'person': {
      hctx.lineWidth = (s.kind === 'highlighter' ? s.style.width * 3 : s.style.width) + tol * 2;
      hctx.lineCap = 'round'; hctx.lineJoin = 'round';
      return hctx.isPointInStroke(toPath(outline(s)), x, y);
    }
    default: {
      const p = toPath(outline(s));
      if ((s.style.fill !== 'none' || s.text) && hctx.isPointInPath(p, x, y)) return true;
      hctx.lineWidth = s.style.width + tol * 2;
      return hctx.isPointInStroke(p, x, y);
    }
  }
}

export function move(s, dx, dy) { s.pts = s.pts.map(([x, y]) => [x + dx, y + dy]); }

export const intersects = (a, b) => a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
