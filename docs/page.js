// Language and theme of the text pages, shared with the home page (same saved choices).
(() => {
  const store = { get(k) { try { return localStorage.getItem(k); } catch { return null; } }, set(k, v) { try { localStorage.setItem(k, v); } catch { } } };
  const norm = l => { l = (l || '').slice(0, 2).toLowerCase(); return ['pt', 'en', 'es'].includes(l) ? l : null; };
  const nav = {
    pt: { home: 'Início', support: 'Suporte', privacy: 'Privacidade e termos', theme: 'Alternar tema claro/escuro' },
    en: { home: 'Home', support: 'Support', privacy: 'Privacy & terms', theme: 'Toggle light/dark theme' },
    es: { home: 'Inicio', support: 'Soporte', privacy: 'Privacidad y términos', theme: 'Cambiar tema claro/oscuro' },
  };

  function apply(lang) {
    for (const a of document.querySelectorAll('article[data-lang]')) a.hidden = a.dataset.lang !== lang;
    const art = document.querySelector(`article[data-lang="${lang}"]`);
    document.documentElement.lang = { pt: 'pt-BR', en: 'en', es: 'es' }[lang];
    if (art && art.dataset.title) document.title = art.dataset.title;
    for (const el of document.querySelectorAll('[data-nav]')) el.textContent = nav[lang][el.dataset.nav];
    for (const a of document.querySelectorAll('a[data-keep-lang]')) {
      const u = new URL(a.getAttribute('href'), location.href);
      u.searchParams.set('lang', lang);
      a.href = u.pathname.split('/').pop() + u.search + u.hash;
    }
    const t = document.getElementById('theme');
    if (t) { t.title = nav[lang].theme; t.setAttribute('aria-label', nav[lang].theme); }
    for (const b of document.querySelectorAll('#lang button')) b.setAttribute('aria-pressed', String(b.dataset.lang === lang));
  }

  const param = norm(new URLSearchParams(location.search).get('lang'));
  const lang = param || norm(store.get('cp.lang')) || (navigator.languages || [navigator.language]).map(norm).find(Boolean) || 'en';
  apply(lang);
  for (const b of document.querySelectorAll('#lang button')) b.addEventListener('click', () => { store.set('cp.lang', b.dataset.lang); apply(b.dataset.lang); });

  const saved = store.get('cp.theme');
  if (saved) document.documentElement.dataset.theme = saved;
  document.getElementById('theme')?.addEventListener('click', () => {
    const dark = document.documentElement.dataset.theme ? document.documentElement.dataset.theme === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
    const next = dark ? 'light' : 'dark';
    document.documentElement.dataset.theme = next;
    store.set('cp.theme', next);
  });
})();
