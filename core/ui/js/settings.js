// Configurações: atalhos (gravador de teclas), captura, gravação, histórico, sobre e apoio via Pix.
import { icon } from './icons.js';

const T = window.__TAURI__;
const invoke = T.core.invoke;
const $ = s => document.querySelector(s);

const ACTIONS = [
  ['clipboard', 'Abrir o histórico de cópias', 'copy'],
  ['captureArea', 'Capturar área ou janela', 'select'],
  ['captureScreen', 'Capturar a tela inteira', 'fullscreen'],
  ['board', 'Modo apresentação (quadro)', 'pen'],
  ['record', 'Gravar a tela (de novo para parar)', 'record'],
];
const TABS = [
  ['inicio', 'Início', 'heart'], ['atalhos', 'Atalhos', 'more'], ['captura', 'Captura', 'select'],
  ['gravacao', 'Gravação', 'record'], ['historico', 'Histórico', 'copy'], ['apoie', 'Sobre e apoio', 'heart'],
];

let data = null, s = null, recording = null;

function pretty(accel) {
  if (!accel) return 'Desativado';
  return accel.split('+').map(k => ({ Super: 'Win', PrintScreen: 'PrtSc', CommandOrControl: 'Ctrl', Control: 'Ctrl' }[k] || k.replace(/^Key/, '').replace(/^Digit/, ''))).join(' + ');
}

async function save() {
  data.errors = await invoke('save_settings', { settings: s });
  renderErrors();
}

function sw(key, onChange) {
  return `<label class="switch"><input type="checkbox" data-k="${key}" ${s[key] ? 'checked' : ''}><span></span></label>`;
}

function build() {
  const nav = $('#nav');
  nav.querySelectorAll('button').forEach(b => b.remove());
  for (const [k, label, ic] of TABS) {
    const b = document.createElement('button');
    b.dataset.tab = k;
    b.innerHTML = `${icon(ic, 17)}${label}`;
    b.addEventListener('click', () => show(k));
    nav.append(b);
  }
  const hk = a => data.settings.hotkeys[a] ? `<kbd>${pretty(data.settings.hotkeys[a])}</kbd>` : '<i>desativado</i>';
  $('#main').innerHTML = `
  <section data-tab="inicio">
    <h1>Bem-vindo ao CopyPaste</h1>
    <p class="sub">Ele fica perto do relógio (${data.system === 'Windows' ? 'na bandeja do sistema' : 'no painel'}) e não atrapalha nada. Use pelos atalhos:</p>
    <div class="grid">
      <div class="feat"><b>${icon('copy')}Histórico de cópias</b><p>${hk('clipboard')} abre tudo o que você copiou: textos, links, imagens, cores e código, com busca. Enter cola no app em que você estava.</p></div>
      <div class="feat"><b>${icon('select')}Captura com anotações</b><p>${hk('captureArea')} congela a tela na hora: selecione uma área ou janela, anote com setas, texto, desfoque e números, e copie com Enter.</p></div>
      <div class="feat"><b>${icon('pen')}Modo apresentação</b><p>${hk('board')} desenha por cima da tela ou num quadro branco, com formas no estilo Excalidraw, notas adesivas e laser.</p></div>
      <div class="feat"><b>${icon('record')}Gravação de tela</b><p>${hk('record')} grava uma área ou a tela inteira em MP4, com microfone e áudio do sistema. O mesmo atalho para.</p></div>
    </div>
    <div class="note" id="notes"></div>
  </section>

  <section data-tab="atalhos">
    <h1>Atalhos globais</h1>
    <p class="sub">Clique num atalho e pressione a nova combinação. <kbd>Esc</kbd> cancela, <kbd>Backspace</kbd> desativa.</p>
    <div class="card">${ACTIONS.map(([a, label, ic]) => `
      <div class="row"><span class="kind">${icon(ic, 18)}</span>
        <div class="l">${label}<span class="err" data-err="${a}"></span></div>
        <button class="btn hk" data-hk="${a}">${pretty(s.hotkeys[a])}</button>
        <button class="btn" data-reset="${a}" title="Voltar ao padrão (${pretty(data.defaults[a])})">Padrão</button>
      </div>`).join('')}
    </div>
    <div class="card"><h3>Dentro da captura e do quadro</h3>
      <table class="keys">
        <tr><td><kbd>Enter</kbd></td><td>Ação principal (copiar, salvar ou ambos)</td></tr>
        <tr><td><kbd>Ctrl</kbd>+<kbd>C</kbd> · <kbd>Ctrl</kbd>+<kbd>S</kbd> · <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>S</kbd></td><td>Copiar · salvar na pasta · salvar como</td></tr>
        <tr><td><kbd>Ctrl</kbd>+<kbd>P</kbd> · <kbd>Ctrl</kbd>+<kbd>T</kbd></td><td>Fixar na tela · copiar o texto (OCR)</td></tr>
        <tr><td><kbd>V P H L A R O D T N S B E K</kbd></td><td>Selecionar, caneta, marca-texto, linha, seta, retângulo, elipse, losango, texto, número, nota, desfoque, borracha, laser</td></tr>
        <tr><td><kbd>1</kbd> … <kbd>9</kbd></td><td>Trocar a cor</td></tr>
        <tr><td><kbd>Shift</kbd> arrastando</td><td>Retas a 45°, quadrados e círculos perfeitos</td></tr>
        <tr><td><kbd>Ctrl</kbd> arrastando</td><td>Mover a área selecionada</td></tr>
        <tr><td><kbd>Ctrl</kbd>+<kbd>Z</kbd> · <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>Z</kbd></td><td>Desfazer · refazer</td></tr>
        <tr><td><kbd>C</kbd> (antes de selecionar)</td><td>Copiar a cor do pixel</td></tr>
        <tr><td><kbd>G</kbd> · <kbd>Ctrl</kbd>+<kbd>V</kbd> (no quadro)</td><td>Trocar o fundo · colar imagem ou texto</td></tr>
      </table>
    </div>
  </section>

  <section data-tab="captura">
    <h1>Captura de tela</h1>
    <p class="sub">A tela congela no instante do atalho: nada some enquanto você seleciona.</p>
    <div class="card">
      <div class="row"><div class="l">Pasta das capturas</div><span class="path" id="capdir"></span><button class="btn" data-folder="captureDir">Escolher…</button></div>
      <div class="row"><div class="l">Formato ao salvar</div><select data-k="captureFormat"><option value="png">PNG (sem perdas)</option><option value="jpg">JPEG (menor)</option></select></div>
      <div class="row"><div class="l">Enter faz</div><select data-k="captureEnter"><option value="copy">Copiar</option><option value="save">Salvar na pasta</option><option value="copyAndSave">Copiar e salvar</option></select></div>
      <div class="row"><div class="l">Lupa com coordenadas e cor<small>Ajuda a selecionar no pixel exato</small></div>${sw('magnifier')}</div>
      <div class="row"><div class="l">Destacar janelas ao passar o mouse<small>Clique para capturar a janela inteira</small></div>${sw('snapWindows')}</div>
    </div>
  </section>

  <section data-tab="gravacao">
    <h1>Gravação de tela</h1>
    <p class="sub">Vídeo MP4 (H.264 + AAC), que abre em qualquer lugar.</p>
    <div class="note" id="ffmpeg"></div>
    <div class="card">
      <div class="row"><div class="l">Pasta das gravações</div><span class="path" id="recdir"></span><button class="btn" data-folder="recordDir">Escolher…</button></div>
      <div class="row"><div class="l">Quadros por segundo</div><select data-k="recordFps" data-num="1"><option value="24">24</option><option value="30">30</option><option value="60">60</option></select></div>
      <div class="row"><div class="l">Gravar o microfone</div>${sw('recordMic')}</div>
      <div class="row"><div class="l">Gravar o áudio do sistema</div>${sw('recordSystemAudio')}</div>
    </div>
  </section>

  <section data-tab="historico">
    <h1>Histórico de cópias</h1>
    <p class="sub">Fica só no seu computador. Nada é enviado para a internet.</p>
    <div class="card">
      <div class="row"><div class="l">Enter e duplo clique colam no app anterior<small>Desligado: só copiam (você cola com Ctrl+V)</small></div>${sw('pasteOnSelect')}</div>
      <div class="row"><div class="l">Itens guardados (os fixados não contam)</div><input type="number" min="20" max="5000" step="10" data-k="historyLimit" data-num="1" style="width:100px"></div>
      <div class="row"><div class="l">Pausar o histórico<small>Útil ao copiar senhas</small></div>${sw('paused')}</div>
      <div class="row"><div class="l">Iniciar com o sistema</div>${sw('autostart')}</div>
      <div class="row"><div class="l">Apagar o histórico</div><button class="btn danger" id="clear">Apagar (mantém os fixados)</button></div>
    </div>
  </section>

  <section data-tab="apoie">
    <h1>Sobre e apoio</h1>
    <p class="sub">CopyPaste ${data.version} para ${data.system} · código aberto (GPL-3.0)</p>
    <div class="card" style="padding:16px">
      <b class="heart">${icon('heart', 18)}</b>
      <p style="margin:6px 0 12px">O CopyPaste é gratuito. Se ele poupa seu tempo, considere uma doação via <b>Pix</b> — qualquer valor ajuda a manter o projeto vivo e com novidades.</p>
      <div class="pix"><code id="pix">${data.pixKey}</code><button class="btn primary" id="copypix">${icon('copy', 16)}Copiar chave Pix</button></div>
      <p style="color:var(--muted);font-size:12px;margin:10px 0 0">No app do seu banco: Pix → Pagar → Chave aleatória → cole a chave.</p>
    </div>
    <div class="card" style="padding:14px 16px">
      <p style="margin:0">Código, novidades e downloads: <a href="#" id="repo">github.com/jonathansfp/copypaste</a></p>
    </div>
  </section>`;

  // valores
  $('#capdir').textContent = s.captureDir;
  $('#recdir').textContent = s.recordDir;
  document.querySelectorAll('[data-k]').forEach(el => {
    const k = el.dataset.k;
    if (el.type === 'checkbox') el.checked = !!s[k];
    else el.value = String(s[k]);
    el.addEventListener('change', () => {
      s[k] = el.type === 'checkbox' ? el.checked : el.dataset.num ? +el.value : el.value;
      save();
    });
  });
  document.querySelectorAll('[data-folder]').forEach(b => b.addEventListener('click', async () => {
    const k = b.dataset.folder;
    const p = await invoke('choose_folder', { current: s[k] });
    if (p) { s[k] = p; $(k === 'captureDir' ? '#capdir' : '#recdir').textContent = p; save(); }
  }));
  document.querySelectorAll('[data-hk]').forEach(b => b.addEventListener('click', () => startRecord(b)));
  document.querySelectorAll('[data-reset]').forEach(b => b.addEventListener('click', () => setHotkey(b.dataset.reset, data.defaults[b.dataset.reset])));
  $('#clear').addEventListener('click', () => { if (confirm('Apagar todo o histórico (exceto os fixados)?')) invoke('history_clear', { keepPinned: true }); });
  $('#copypix').addEventListener('click', () => invoke('copy_text', { text: data.pixKey, toast: 'Chave Pix copiada — obrigado! ♥' }));
  $('#repo').addEventListener('click', e => { e.preventDefault(); T.opener ? T.opener.openUrl('https://github.com/jonathansfp/copypaste') : invoke('plugin:opener|open_url', { url: 'https://github.com/jonathansfp/copypaste' }); });
  $('#ffmpeg').innerHTML = data.ffmpeg ? `${icon('check', 16)} ffmpeg encontrado: a gravação está pronta.` : `Para gravar, instale o ffmpeg (grátis): ${data.system === 'Windows' ? '<kbd>winget install Gyan.FFmpeg</kbd>' : '<kbd>sudo apt install ffmpeg</kbd>'} e reabra esta tela.`;
  const notes = $('#notes');
  notes.innerHTML = data.notes.length ? data.notes.map(n => `• ${n.replace(/`([^`]+)`/g, '<kbd>$1</kbd>')}`).join('<br>') : `${icon('check', 16)} Tudo pronto. Dica: clique com o botão direito no ícone perto do relógio para ver o menu.`;
  renderErrors();
}

function renderErrors() {
  document.querySelectorAll('[data-err]').forEach(el => { el.textContent = (data.errors || {})[el.dataset.err] || ''; });
}

function show(tab) {
  if (!TABS.some(t => t[0] === tab)) tab = 'inicio';
  document.querySelectorAll('aside button').forEach(b => b.classList.toggle('active', b.dataset.tab === tab));
  document.querySelectorAll('section').forEach(x => x.classList.toggle('active', x.dataset.tab === tab));
}

// ── gravador de atalhos ──
const CODE_NAMES = { Space: 'Space', Enter: 'Enter', Tab: 'Tab', Backquote: 'Backquote', Minus: 'Minus', Equal: 'Equal', BracketLeft: 'BracketLeft', BracketRight: 'BracketRight', Backslash: 'Backslash', Semicolon: 'Semicolon', Quote: 'Quote', Comma: 'Comma', Period: 'Period', Slash: 'Slash', Insert: 'Insert', Delete: 'Delete', Home: 'Home', End: 'End', PageUp: 'PageUp', PageDown: 'PageDown', ArrowUp: 'ArrowUp', ArrowDown: 'ArrowDown', ArrowLeft: 'ArrowLeft', ArrowRight: 'ArrowRight', PrintScreen: 'PrintScreen', Pause: 'Pause', ScrollLock: 'ScrollLock' };
function keyName(code) {
  if (/^Key[A-Z]$/.test(code)) return code.slice(3);
  if (/^Digit[0-9]$/.test(code)) return code.slice(5);
  if (/^F([1-9]|1[0-9]|2[0-4])$/.test(code)) return code;
  if (/^Numpad[0-9]$/.test(code)) return code;
  return CODE_NAMES[code] || null;
}

async function startRecord(b) {
  if (recording) stopRecord(false);
  recording = { b, action: b.dataset.hk };
  b.classList.add('rec'); b.textContent = 'Pressione o atalho…';
  await invoke('suspend_hotkeys');
}
async function stopRecord(apply, accel) {
  const r = recording;
  if (!r) return;
  recording = null;
  r.b.classList.remove('rec');
  if (apply) await setHotkey(r.action, accel);
  else { r.b.textContent = pretty(s.hotkeys[r.action]); data.errors = await invoke('resume_hotkeys'); renderErrors(); }
}
async function setHotkey(action, accel) {
  // O mesmo atalho em duas ações: a outra fica desativada.
  for (const [a] of ACTIONS) if (a !== action && accel && s.hotkeys[a] === accel) s.hotkeys[a] = '';
  s.hotkeys[action] = accel;
  await save();
  document.querySelectorAll('[data-hk]').forEach(x => { x.textContent = pretty(s.hotkeys[x.dataset.hk]); });
}
function onKey(e) {
  if (!recording) return;
  e.preventDefault(); e.stopPropagation();
  if (e.type === 'keydown' && e.key === 'Escape') { stopRecord(false); return; }
  if (e.type === 'keydown' && e.key === 'Backspace' && !e.ctrlKey && !e.altKey && !e.shiftKey) { stopRecord(true, ''); return; }
  const name = keyName(e.code);
  // PrintScreen só gera "keyup" no Windows.
  if (!name || (e.type === 'keyup' && e.code !== 'PrintScreen')) return;
  const mods = [];
  if (e.ctrlKey) mods.push('Ctrl');
  if (e.altKey) mods.push('Alt');
  if (e.shiftKey) mods.push('Shift');
  if (e.metaKey) mods.push('Super');
  const standalone = /^F\d+$/.test(name) || name === 'PrintScreen' || name === 'Pause' || name === 'ScrollLock' || name === 'Insert';
  if (!mods.length && !standalone) { recording.b.textContent = 'Use Ctrl, Alt, Shift ou Win junto'; return; }
  stopRecord(true, [...mods, name].join('+'));
}
addEventListener('keydown', onKey, true);
addEventListener('keyup', onKey, true);
addEventListener('blur', () => { if (recording) stopRecord(false); });

async function init() {
  data = await invoke('get_settings');
  s = structuredClone(data.settings);
  build();
  show(location.hash.slice(1) || 'inicio');
}
T.event.listen('settings-tab', e => { if (e.payload) show(e.payload); init().then(() => e.payload && show(e.payload)); });
init();
