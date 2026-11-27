// Configurações: manual, atalhos (gravador de teclas), captura, gravação, histórico, sobre e apoio via Pix.
import { icon } from './icons.js';
import { t, locale, getLang, translatePage, onLanguageChange } from './i18n.js';
import { manualTopics } from './manual.js';

const T = window.__TAURI__;
const invoke = T.core.invoke;
const $ = s => document.querySelector(s);

const ACTIONS = [
  ['clipboard', 'Abrir o histórico de cópias', 'copy'],
  ['captureArea', 'Capturar área ou janela', 'select'],
  ['captureScreen', 'Capturar a tela inteira', 'fullscreen'],
  ['board', 'Modo apresentação (quadro)', 'pen'],
  ['record', 'Gravar a tela (de novo para parar)', 'record'],
  ['dictate', 'Ditado por voz (segure e fale, ou toque)', 'mic'],
  ['voiceCommand', 'Comando de voz sobre o texto selecionado', 'style'],
];
const TABS = [
  ['inicio', 'Início', 'heart'], ['manual', 'Como usar', 'help'], ['atalhos', 'Atalhos', 'more'], ['captura', 'Captura', 'select'],
  ['gravacao', 'Gravação', 'record'], ['ia', 'IA e ditado', 'mic'], ['historico', 'Histórico', 'copy'], ['apoie', 'Sobre e apoio', 'heart'],
];

let data = null, s = null, recording = null;

function pretty(accel) {
  if (!accel) return t('Desativado');
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
    b.innerHTML = `${icon(ic, 17)}${t(label)}`;
    b.addEventListener('click', () => show(k));
    nav.append(b);
  }
  const hk = a => data.settings.hotkeys[a] ? `<kbd>${pretty(data.settings.hotkeys[a])}</kbd>` : `<i>${t('desativado')}</i>`;
  $('#main').innerHTML = `
  <section data-tab="inicio">
    <h1>${t('Bem-vindo ao CopyPaste')}</h1>
    <p class="sub">${t(data.system === 'Windows' ? 'Ele fica perto do relógio (na bandeja do sistema) e não atrapalha nada. Use pelos atalhos:' : 'Ele fica perto do relógio (no painel) e não atrapalha nada. Use pelos atalhos:')}</p>
    <div class="grid">
      <div class="feat"><b>${icon('copy')}${t('Histórico de cópias')}</b><p>${t('{0} abre tudo o que você copiou: textos, links, imagens, cores e código, com busca. Enter cola no app em que você estava.', hk('clipboard'))}</p></div>
      <div class="feat"><b>${icon('select')}${t('Captura com anotações')}</b><p>${t('{0} congela a tela na hora: selecione uma área ou janela, anote com setas, texto, desfoque e números, e copie com Enter.', hk('captureArea'))}</p></div>
      <div class="feat"><b>${icon('pen')}${t('Modo apresentação')}</b><p>${t('{0} desenha por cima da tela ou num quadro branco, com formas no estilo Excalidraw, notas adesivas e laser.', hk('board'))}</p></div>
      <div class="feat"><b>${icon('record')}${t('Gravação de tela')}</b><p>${t('{0} grava uma área ou a tela inteira em MP4, com microfone e áudio do sistema. O mesmo atalho para.', hk('record'))}</p></div>
      <div class="feat"><b>${icon('mic')}${t('Ditado por voz com IA')}</b><p>${t('Segure {0} e fale: o texto aparece onde está o cursor, limpo e pontuado pela IA que você conectar (Claude, GPT, Gemini, DeepSeek ou Grok).', hk('dictate'))}</p></div>
    </div>
    <div class="note" id="notes"></div>
    <div class="card">
      <div class="row"><div class="l">${t('Idioma do app')}<small>${t('Menus, avisos e janelas do CopyPaste')}</small></div><select data-k="language">
        <option value="auto">${t('Automático (idioma do sistema)')}</option><option value="pt">Português</option><option value="en">English</option><option value="es">Español</option></select></div>
    </div>
  </section>

  <section data-tab="manual">
    <h1>${t('Como usar')}</h1>
    <div class="manual"><div class="topics" id="topics"></div><div class="topic" id="topic"></div></div>
  </section>

  <section data-tab="atalhos">
    <h1>${t('Atalhos globais')}</h1>
    <p class="sub">${t('Clique num atalho e pressione a nova combinação. <kbd>Esc</kbd> cancela, <kbd>Backspace</kbd> desativa.')}</p>
    <div class="card">${ACTIONS.map(([a, label, ic]) => `
      <div class="row"><span class="kind">${icon(ic, 18)}</span>
        <div class="l">${t(label)}<span class="err" data-err="${a}"></span></div>
        <button class="btn hk" data-hk="${a}">${pretty(s.hotkeys[a])}</button>
        <button class="btn" data-reset="${a}" title="${t('Voltar ao padrão ({0})', pretty(data.defaults[a]))}">${t('Padrão')}</button>
      </div>`).join('')}
    </div>
    <div class="card"><h3>${t('Dentro da captura e do quadro')}</h3>
      <table class="keys">
        <tr><td><kbd>Enter</kbd></td><td>${t('Ação principal (copiar, salvar ou ambos)')}</td></tr>
        <tr><td><kbd>Ctrl</kbd>+<kbd>C</kbd> · <kbd>Ctrl</kbd>+<kbd>S</kbd> · <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>S</kbd></td><td>${t('Copiar · salvar na pasta · salvar como')}</td></tr>
        <tr><td><kbd>Ctrl</kbd>+<kbd>P</kbd> · <kbd>Ctrl</kbd>+<kbd>T</kbd></td><td>${t('Fixar na tela · copiar o texto (OCR)')}</td></tr>
        <tr><td><kbd>V P H L A R O D T N S B E K</kbd></td><td>${t('Selecionar, caneta, marca-texto, linha, seta, retângulo, elipse, losango, texto, número, nota, desfoque, borracha, laser')}</td></tr>
        <tr><td><kbd>1</kbd> … <kbd>9</kbd></td><td>${t('Trocar a cor')}</td></tr>
        <tr><td>${t('<kbd>Shift</kbd> arrastando')}</td><td>${t('Retas a 45°, quadrados e círculos perfeitos')}</td></tr>
        <tr><td>${t('<kbd>Ctrl</kbd> arrastando')}</td><td>${t('Mover a área selecionada')}</td></tr>
        <tr><td><kbd>Ctrl</kbd>+<kbd>Z</kbd> · <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>Z</kbd></td><td>${t('Desfazer · refazer')}</td></tr>
        <tr><td>${t('<kbd>C</kbd> (antes de selecionar)')}</td><td>${t('Copiar a cor do pixel')}</td></tr>
        <tr><td>${t('<kbd>G</kbd> · <kbd>Ctrl</kbd>+<kbd>V</kbd> (no quadro)')}</td><td>${t('Trocar o fundo · colar imagem ou texto')}</td></tr>
      </table>
    </div>
  </section>

  <section data-tab="captura">
    <h1>${t('Captura de tela')}</h1>
    <p class="sub">${t('A tela congela no instante do atalho: nada some enquanto você seleciona.')}</p>
    <div class="card">
      <div class="row"><div class="l">${t('Pasta das capturas')}</div><span class="path" id="capdir"></span><button class="btn" data-folder="captureDir">${t('Escolher…')}</button></div>
      <div class="row"><div class="l">${t('Formato ao salvar')}</div><select data-k="captureFormat"><option value="png">${t('PNG (sem perdas)')}</option><option value="jpg">${t('JPEG (menor)')}</option></select></div>
      <div class="row"><div class="l">${t('Enter faz')}</div><select data-k="captureEnter"><option value="copy">${t('Copiar')}</option><option value="save">${t('Salvar na pasta')}</option><option value="copyAndSave">${t('Copiar e salvar')}</option></select></div>
      <div class="row"><div class="l">${t('Lupa com coordenadas e cor')}<small>${t('Ajuda a selecionar no pixel exato')}</small></div>${sw('magnifier')}</div>
      <div class="row"><div class="l">${t('Destacar janelas ao passar o mouse')}<small>${t('Clique para capturar a janela inteira')}</small></div>${sw('snapWindows')}</div>
    </div>
  </section>

  <section data-tab="gravacao">
    <h1>${t('Gravação de tela')}</h1>
    <p class="sub">${t('Vídeo MP4 (H.264 + AAC), que abre em qualquer lugar.')}</p>
    <div class="note" id="ffmpeg"></div>
    <div class="card">
      <div class="row"><div class="l">${t('Pasta das gravações')}</div><span class="path" id="recdir"></span><button class="btn" data-folder="recordDir">${t('Escolher…')}</button></div>
      <div class="row"><div class="l">${t('Quadros por segundo')}</div><select data-k="recordFps" data-num="1"><option value="24">24</option><option value="30">30</option><option value="60">60</option></select></div>
      <div class="row"><div class="l">${t('Gravar o microfone')}</div>${sw('recordMic')}</div>
      <div class="row"><div class="l">${t('Gravar o áudio do sistema')}</div>${sw('recordSystemAudio')}</div>
    </div>
  </section>

  <section data-tab="ia">
    <h1>${t('IA e ditado por voz')}</h1>
    <p class="sub">${t('Segure {0} e fale; solte para o texto aparecer onde está o cursor, em qualquer app. Um toque rápido deixa ouvindo até o próximo toque. Com um texto selecionado, {1} aplica o que você pedir ("traduza para inglês", "deixe mais formal").', hk('dictate'), hk('voiceCommand'))}</p>
    <div class="card">
      <div class="row"><div class="l">${t('Transcrição da voz')}<small>${t('A IA local roda no computador, sem internet e sem chave')}</small></div><select data-k="dictEngine"><option value="local">${t('IA local Gemma 4 (grátis, offline)')}</option><option value="openai">${t('OpenAI (sua chave)')}</option><option value="gemini">${t('Gemini (sua chave)')}</option></select></div>
      <div class="row"><div class="l">${t('Idioma falado')}</div><select data-k="dictLanguage">
        <option value="pt-BR">${t('Português (Brasil)')}</option><option value="pt-PT">${t('Português (Portugal)')}</option><option value="en-US">${t('Inglês (EUA)')}</option>
        <option value="en-GB">${t('Inglês (Reino Unido)')}</option><option value="es-ES">${t('Espanhol')}</option><option value="fr-FR">${t('Francês')}</option><option value="it-IT">${t('Italiano')}</option><option value="de-DE">${t('Alemão')}</option>
        <option value="auto">${t('Detectar automaticamente')}</option></select></div>
      <div class="row"><div class="l">${t('IA que ajusta o texto')}<small>${t('Tira vícios de fala, pontua e formata')}</small></div><select id="polish"></select></div>
      <div class="row"><div class="l">${t('Estilo')}</div><select data-k="dictStyle">
        <option value="natural">${t('Natural: limpo, com o seu jeito de falar')}</option><option value="formal">${t('Formal: e-mails e documentos')}</option>
        <option value="casual">${t('Descontraído: chats e mensagens')}</option><option value="literal">${t('Literal: só a transcrição, sem IA')}</option></select></div>
      <div class="row"><div class="l">${t('Vocabulário')}<small>${t('Nomes, siglas e termos, separados por vírgula')}</small></div><input type="text" data-k="dictTerms" placeholder="${t('Ex.: CopyPaste, Kubernetes, Dra. Ana Souza')}" style="width:260px"></div>
    </div>
    <div class="card"><h3>${t('IA local (padrão, grátis e offline)')}</h3>
      <div class="row"><div class="l"><b>Gemma 4 E2B</b><small id="localinfo">${t('O modelo do Google roda no seu computador pelo llama.cpp: transcreve e ajusta o texto sem internet e sem chave. É usado quando nenhuma outra IA está ativa.')}</small><span class="err" id="localerr"></span></div><span id="localact"></span></div>
      <div id="localbar" style="display:none;padding:0 0 12px"><div style="height:6px;border-radius:9px;background:var(--line);overflow:hidden"><div id="localfill" style="height:100%;width:0;background:var(--accent)"></div></div><small id="locallabel" style="color:var(--muted)"></small></div>
    </div>
    <div class="card" id="aicards"><h3>${t('Conexões de IA')}</h3></div>
    <p style="color:var(--muted);font-size:12px">${t('Use a sua própria chave de API: o CopyPaste não tem servidor e não cobra nada. A chave fica só neste computador, e o áudio e o texto vão direto para a IA escolhida, cobrados na sua conta dela.')}</p>
  </section>

  <section data-tab="historico">
    <h1>${t('Histórico de cópias')}</h1>
    <p class="sub">${t('Fica só no seu computador. Nada é enviado para a internet.')}</p>
    <div class="card">
      <div class="row"><div class="l">${t('Enter e duplo clique colam no app anterior')}<small>${t('Desligado: só copiam (você cola com Ctrl+V)')}</small></div>${sw('pasteOnSelect')}</div>
      <div class="row"><div class="l">${t('Itens guardados (os fixados não contam)')}</div><input type="number" min="20" max="5000" step="10" data-k="historyLimit" data-num="1" style="width:100px"></div>
      <div class="row"><div class="l">${t('Pausar o histórico')}<small>${t('Útil ao copiar senhas')}</small></div>${sw('paused')}</div>
      <div class="row"><div class="l">${t('Iniciar com o sistema')}</div>${sw('autostart')}</div>
      <div class="row"><div class="l">${t('Apagar o histórico')}</div><button class="btn danger" id="clear">${t('Apagar (mantém os fixados)')}</button></div>
    </div>
  </section>

  <section data-tab="apoie">
    <h1>${t('Sobre e apoio')}</h1>
    <p class="sub">${t('CopyPaste {0} para {1} · código aberto (GPL-3.0)', data.version, data.system)}</p>
    <div class="card" style="padding:16px">
      <b class="heart">${icon('heart', 18)}</b>
      <p style="margin:6px 0 12px">${t('O CopyPaste é gratuito. Se ele poupa seu tempo, considere uma doação via <b>Pix</b> — qualquer valor ajuda a manter o projeto vivo e com novidades.')}</p>
      <div class="pix"><code id="pix">${data.pixKey}</code><button class="btn primary" id="copypix">${icon('copy', 16)}${t('Copiar chave Pix')}</button></div>
      <p style="color:var(--muted);font-size:12px;margin:10px 0 0">${t('No app do seu banco: Pix → Pagar → Chave aleatória → cole a chave.')}</p>
    </div>
    <div class="card" style="padding:14px 16px">
      <p style="margin:0">${t('Código, novidades e downloads:')} <a href="#" id="repo">github.com/jonathansfp/copypaste</a></p>
      <p style="margin:8px 0 0"><a href="#" data-url="https://jonathansfp.github.io/copypaste/suporte.html">${t('Suporte')}</a> · <a href="#" data-url="https://jonathansfp.github.io/copypaste/privacidade.html">${t('Privacidade e termos de uso')}</a></p>
    </div>
  </section>`;

  renderAI();

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
  $('#clear').addEventListener('click', () => { if (confirm(t('Apagar todo o histórico (exceto os fixados)?'))) invoke('history_clear', { keepPinned: true }); });
  $('#copypix').addEventListener('click', () => invoke('copy_text', { text: data.pixKey, toast: t('Chave Pix copiada — obrigado! ♥') }));
  $('#repo').addEventListener('click', e => { e.preventDefault(); T.opener ? T.opener.openUrl('https://github.com/jonathansfp/copypaste') : invoke('plugin:opener|open_url', { url: 'https://github.com/jonathansfp/copypaste' }); });
  $('#ffmpeg').innerHTML = data.ffmpeg ? `${icon('check', 16)} ${t('ffmpeg encontrado: a gravação está pronta.')}` : t('Para gravar, instale o ffmpeg (grátis): {0} e reabra esta tela.', data.system === 'Windows' ? '<kbd>winget install Gyan.FFmpeg</kbd>' : '<kbd>sudo apt install ffmpeg</kbd>');
  const notes = $('#notes');
  notes.innerHTML = data.notes.length ? data.notes.map(n => `• ${n.replace(/`([^`]+)`/g, '<kbd>$1</kbd>')}`).join('<br>') : `${icon('check', 16)} ${t('Tudo pronto. Dica: clique com o botão direito no ícone perto do relógio para ver o menu.')}`;
  renderErrors();
  renderManual();
}

// ── manual (Como usar) ──
let manualTopic = 'start';
function renderManual() {
  const topics = manualTopics(getLang(), data.system);
  const list = $('#topics');
  list.innerHTML = '';
  for (const tp of topics) {
    const b = document.createElement('button');
    b.className = tp.id === manualTopic ? 'active' : '';
    b.innerHTML = `${icon(tp.icon, 16)}<span>${tp.title}</span>`;
    b.addEventListener('click', () => { manualTopic = tp.id; renderManual(); $('#main').scrollTop = 0; });
    list.append(b);
  }
  const tp = topics.find(x => x.id === manualTopic) || topics[0];
  const label = Object.fromEntries(ACTIONS.map(([a, l]) => [a, t(l)]));
  // The shortcuts as set now (also right after a change in the Shortcuts tab).
  const hotkeys = tp.actions.map(a => `<div class="hkrow"><span>${label[a]}</span>${s.hotkeys[a] ? `<kbd>${pretty(s.hotkeys[a])}</kbd>` : `<i>${t('sem atalho: defina em Configurações › Atalhos')}</i>`}</div>`).join('');
  const notes = tp.id === 'start' && data.notes.length ? `<div class="note">${data.notes.map(n => `• ${esc(n).replace(/`([^`]+)`/g, '<kbd>$1</kbd>')}`).join('<br>')}</div>` : '';
  $('#topic').innerHTML = `
    <h2>${icon(tp.icon, 24)}${tp.title}</h2>
    <p class="intro">${tp.intro}</p>
    ${hotkeys ? `<div class="card hks">${hotkeys}</div>` : ''}
    <h3>${t('Como usar')}</h3>
    <ol class="steps">${tp.steps.map(x => `<li>${x}</li>`).join('')}</ol>
    ${notes}
    ${tp.tips.length ? `<div class="tips"><h3>${t('Dicas')}</h3>${tp.tips.map(x => `<p>${x}</p>`).join('')}</div>` : ''}`;
}

const PROVIDERS = [
  ['claude', 'Claude (Anthropic)', 'https://platform.claude.com/settings/keys', 'sk-ant-…'],
  ['openai', 'ChatGPT (OpenAI)', 'https://platform.openai.com/api-keys', 'sk-…'],
  ['gemini', 'Gemini (Google)', 'https://aistudio.google.com/apikey', 'AIza…'],
  ['deepseek', 'DeepSeek', 'https://platform.deepseek.com/api_keys', 'sk-…'],
  ['grok', 'Grok (xAI)', 'https://console.x.ai', 'xai-…'],
];
const esc = t => String(t).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const openUrl = url => T.opener ? T.opener.openUrl(url) : invoke('plugin:opener|open_url', { url });
document.addEventListener('click', e => {
  const a = e.target.closest('a[href^="mailto:"], a[data-url]');
  if (!a) return;
  e.preventDefault();
  if (a.dataset.url) { const u = new URL(a.dataset.url); u.searchParams.set('lang', getLang()); openUrl(u.toString()); } else openUrl(a.getAttribute('href'));
});

const gb = b => (b / 1e9).toLocaleString(locale(), { maximumFractionDigits: 1 }) + ' GB';

function renderLocal() {
  const st = data.local || {};
  const act = $('#localact'), bar = $('#localbar');
  $('#localerr').textContent = '';
  bar.style.display = st.downloading ? 'block' : 'none';
  if (st.installed) {
    act.innerHTML = `<small style="color:#16a34a;margin-right:10px">${t('Pronta · {0}', gb(st.disk))}</small><button class="btn danger" id="localrm">${t('Remover')}</button>`;
    $('#localrm').onclick = async () => {
      if (!confirm(t('Remover a IA local e liberar o espaço em disco?'))) return;
      const ns = await invoke('local_remove');
      s.dictPolish = ns.dictPolish;
      data.local = await invoke('local_status');
      renderAI();
    };
  } else if (st.downloading) {
    act.innerHTML = `<button class="btn" id="localcancel">${t('Cancelar')}</button>`;
    $('#localcancel').onclick = () => invoke('local_cancel');
  } else {
    act.innerHTML = `<button class="btn primary" id="localget">${st.hasModel ? t('Instalar (≈ 25 MB)') : t('Baixar (≈ {0})', gb(st.total || 4.1e9))}</button>`;
    $('#localget').onclick = async () => {
      data.local = { ...st, downloading: true };
      renderLocal();
      await invoke('local_install');
    };
  }
}

T.event.listen('local-progress', async e => {
  const p = e.payload;
  if (!$('#localbar')) return;
  if (p.done) {
    data.local = await invoke('local_status');
    if (p.error) { renderLocal(); $('#localerr').textContent = p.error; return; }
    const fresh = await invoke('get_settings');
    for (const k of ['dictPolish', 'dictEngine']) s[k] = fresh.settings[k];
    const eng = document.querySelector('[data-k="dictEngine"]');
    if (eng) eng.value = s.dictEngine;
    renderAI();
    return;
  }
  $('#localbar').style.display = 'block';
  $('#localfill').style.width = (p.progress * 100).toFixed(1) + '%';
  $('#locallabel').textContent = `${p.label} ${Math.round(p.progress * 100)}%`;
});

function renderAI() {
  renderLocal();
  const connected = new Set(data.aiConnected || []);
  const localOk = !!(data.local && data.local.installed);
  const polish = $('#polish');
  polish.innerHTML = `<option value="">${t('Nenhuma (texto como foi transcrito)')}</option>` +
    `<option value="local">${t(localOk ? 'IA local Gemma 4' : 'IA local Gemma 4 (baixar abaixo)')}</option>` +
    PROVIDERS.filter(([p]) => connected.has(p)).map(([p, n]) => `<option value="${p}">${n}</option>`).join('');
  polish.value = s.dictPolish === 'local' || connected.has(s.dictPolish) ? s.dictPolish : '';
  polish.onchange = () => { s.dictPolish = polish.value; save(); };
  const box = $('#aicards');
  box.querySelectorAll('.row').forEach(r => r.remove());
  for (const [p, n, url, ph] of PROVIDERS) {
    const row = document.createElement('div');
    row.className = 'row';
    const voice = p === 'openai' || p === 'gemini' ? t('Texto e voz') : t('Texto');
    if (connected.has(p)) {
      const models = (s.aiModelLists || {})[p] || [];
      const stt = (s.aiSttLists || {})[p] || [];
      row.innerHTML = `<div class="l" style="min-width:150px"><b>${n}</b><small style="color:#16a34a">${t('Conectado · {0}', voice.toLowerCase())}</small></div>
        <select data-model="${p}" title="${t('Modelo de texto')}">${models.map(m => `<option>${esc(m)}</option>`).join('')}</select>
        ${stt.length ? `<select data-stt="${p}" title="${t('Modelo de transcrição')}">${stt.map(m => `<option>${esc(m)}</option>`).join('')}</select>` : ''}
        <button class="btn danger" data-remove="${p}">${t('Remover')}</button>`;
      const sel = row.querySelector('[data-model]');
      sel.value = (s.aiModels || {})[p] || models[0] || '';
      sel.onchange = () => { s.aiModels = { ...s.aiModels, [p]: sel.value }; save(); };
      const ss = row.querySelector('[data-stt]');
      if (ss) { ss.value = (s.aiSttModels || {})[p] || stt[0] || ''; ss.onchange = () => { s.aiSttModels = { ...s.aiSttModels, [p]: ss.value }; save(); }; }
      row.querySelector('[data-remove]').onclick = async () => {
        const ns = await invoke('ai_disconnect', { provider: p });
        data.aiConnected = (data.aiConnected || []).filter(x => x !== p);
        s.dictPolish = ns.dictPolish;
        renderAI();
      };
    } else {
      row.innerHTML = `<div class="l" style="min-width:150px"><b>${n}</b><small>${voice} · <a href="#" class="getkey">${t('obter chave')}</a></small><span class="err"></span></div>
        <input type="password" placeholder="${ph}" style="width:170px;min-width:0;padding:6px 10px;border-radius:8px;border:1px solid var(--line);background:var(--panel)">
        <button class="btn primary">${t('Conectar')}</button>`;
      const input = row.querySelector('input'), btn = row.querySelector('button'), err = row.querySelector('.err');
      row.querySelector('.getkey').onclick = e => { e.preventDefault(); openUrl(url); };
      const go = async () => {
        if (!input.value.trim()) return;
        btn.disabled = true; btn.textContent = t('Verificando…'); err.textContent = '';
        try {
          const ns = await invoke('ai_connect', { provider: p, key: input.value });
          data.aiConnected = [...new Set([...(data.aiConnected || []), p])];
          for (const k of ['aiModels', 'aiSttModels', 'aiModelLists', 'aiSttLists', 'dictPolish', 'dictEngine']) s[k] = ns[k];
          document.querySelector('[data-k="dictEngine"]').value = s.dictEngine;
          renderAI();
        } catch (e) {
          err.textContent = String(e);
          btn.disabled = false; btn.textContent = t('Conectar');
        }
      };
      btn.onclick = go;
      input.onkeydown = e => { if (e.key === 'Enter') go(); };
    }
    box.append(row);
  }
}

function renderErrors() {
  document.querySelectorAll('[data-err]').forEach(el => { el.textContent = (data.errors || {})[el.dataset.err] || ''; });
}

let current = 'inicio';
function show(tab) {
  if (!TABS.some(x => x[0] === tab)) tab = 'inicio';
  current = tab;
  if (tab === 'manual' && data) renderManual();
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
  b.classList.add('rec'); b.textContent = t('Pressione o atalho…');
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
  if (!mods.length && !standalone) { recording.b.textContent = t('Use Ctrl, Alt, Shift ou Win junto'); return; }
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
// Another language chosen: the page is drawn again in it, on the same tab.
onLanguageChange(() => { translatePage(); const tab = current; init().then(() => show(tab)); });
translatePage();
init();
