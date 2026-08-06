(() => {
  'use strict';

  const API = location.origin;
  const TOKEN_KEY = 'wesi_portal_token';
  const USER_KEY = 'wesi_portal_user';
  const TIMEOUT = 8000;
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const state = {
    token: sessionStorage.getItem(TOKEN_KEY) || '',
    user: json(sessionStorage.getItem(USER_KEY)),
    manifest: null,
  };
  const els = {
    app: $('#app'),
    loginView: $('#loginView'),
    dashboardView: $('#dashboardView'),
    loginForm: $('#loginForm'),
    identity: $('#identity'),
    password: $('#password'),
    passwordToggle: $('#passwordToggle'),
    loginButton: $('#loginButton'),
    loginMessage: $('#loginMessage'),
    logoutButton: $('#logoutButton'),
    employeeName: $('#employeeName'),
    heroVersion: $('#heroVersion'),
    heroBuild: $('#heroBuild'),
    releaseVersion: $('#releaseVersion'),
    releaseBuild: $('#releaseBuild'),
    publishedAt: $('#publishedAt'),
    changelog: $('#changelog p'),
    windowsSize: $('#windowsSize'),
    androidSize: $('#androidSize'),
    footerStatus: $('#footerStatus'),
    toastStack: $('#toastStack'),
  };

  function json(value) {
    try { return value ? JSON.parse(value) : null; } catch (_) { return null; }
  }

  function clearSession() {
    state.token = '';
    state.user = null;
    state.manifest = null;
    sessionStorage.removeItem(TOKEN_KEY);
    sessionStorage.removeItem(USER_KEY);
  }

  function headers(extra = {}) {
    return state.token ? { ...extra, Authorization: state.token } : extra;
  }

  async function fetchTimeout(url, options = {}, timeout = TIMEOUT) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);
    try {
      return await fetch(url, { ...options, signal: controller.signal });
    } finally {
      clearTimeout(timer);
    }
  }

  // Служебные фразы PocketBase, за которыми не стоит никакого объяснения.
  // Свои сообщения сервер шлёт по-русски и по делу — их надо показывать
  // как есть, а не заменять общими словами.
  const GENERIC_FAILURES = [
    'something went wrong',
    'failed to authenticate',
    'the request requires valid record authorization token',
  ];

  function describeFailure(status, message) {
    const raw = (message || '').trim();
    const generic = !raw ||
      GENERIC_FAILURES.some(phrase => raw.toLowerCase().includes(phrase));
    if (!generic) return raw;
    if (status === 401 || status === 403) return 'Сессия истекла — войдите заново';
    if (status === 404) return 'Сборка ещё не опубликована на сервере';
    if (status >= 500) return 'Сервер не смог ответить — попробуйте позже';
    return 'Не удалось получить данные с сервера';
  }

  async function request(path, options = {}, timeout = TIMEOUT) {
    const response = await fetchTimeout(`${API}${path}`, {
      cache: 'no-store',
      ...options,
      headers: headers(options.headers || {}),
    }, timeout);
    let body = null;
    try { body = await response.json(); } catch (_) {}
    if (!response.ok) {
      // Человеку — по-русски и про суть. Сервер отвечает служебной фразой
      // вроде «Something went wrong while processing your request», и
      // показывать её в подвале означает предъявлять сотруднику текст,
      // который ничего ему не говорит и выглядит поломкой сайта.
      const error = new Error(describeFailure(response.status, body?.message));
      error.status = response.status;
      error.raw = body?.message || '';
      throw error;
    }
    return body;
  }

  function showView(next, resetScroll = true) {
    $('.view.active')?.classList.remove('active');
    next?.classList.add('active');
    // Метка на корне: по ней выключается всё, что относится к публичной
    // странице. Огонёк, например, живёт вне `.view` и сам по себе тянул
    // страницу вниз на две с половиной тысячи пикселей — под экраном
    // загрузок оказывалась пустота, которую можно листать.
    document.documentElement.classList.toggle(
      'view-dashboard',
      next?.id === 'dashboardView',
    );
    if (resetScroll) scrollTo(0, 0);
  }

  function showLogin(resetScroll = false) {
    els.logoutButton?.classList.add('hidden');
    showView(els.loginView, resetScroll);
  }

  function setLoading(button, on, text = '') {
    if (!button) return;
    button.dataset.label ||= $('span', button)?.textContent || '';
    button.disabled = on;
    const label = $('span', button);
    if (label) label.textContent = on ? text : button.dataset.label;
  }

  function nameOf(record) {
    return (record?.name || record?.username || record?.email || 'сотрудник').replace(/@wesi\.local$/i, '');
  }

  async function authCandidate(identity, password) {
    const response = await fetchTimeout(`${API}/api/collections/users/auth-with-password`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ identity, password }),
      cache: 'no-store',
    });
    const body = await response.json().catch(() => null);
    return { response, body };
  }

  async function signIn(identity, password) {
    const raw = identity.trim();
    const candidates = [raw];
    if (raw && !raw.includes('@')) candidates.push(`${raw.toLowerCase()}@wesi.local`);
    for (const candidate of [...new Set(candidates)]) {
      const { response, body } = await authCandidate(candidate, password);
      if (response.ok && body?.token) {
        state.token = body.token;
        state.user = body.record || {};
        sessionStorage.setItem(TOKEN_KEY, state.token);
        sessionStorage.setItem(USER_KEY, JSON.stringify(state.user));
        return;
      }
    }
    const error = new Error('Неверный логин или пароль');
    error.status = 401;
    throw error;
  }

  async function verifySession() {
    if (!state.token) return false;
    try {
      const body = await request('/api/collections/users/auth-refresh', { method: 'POST' }, 2400);
      state.token = body.token || state.token;
      state.user = body.record || state.user;
      sessionStorage.setItem(TOKEN_KEY, state.token);
      sessionStorage.setItem(USER_KEY, JSON.stringify(state.user));
      return true;
    } catch (_) {
      clearSession();
      return false;
    }
  }

  function platform(manifest, name) {
    return manifest?.[name] && typeof manifest[name] === 'object' ? manifest[name] : null;
  }

  function size(value) {
    const bytes = Number(value);
    if (!bytes) return '—';
    const megabytes = bytes / 1048576;
    return megabytes >= 1024 ? `${(megabytes / 1024).toFixed(1)} ГБ` : `${megabytes.toFixed(megabytes >= 10 ? 0 : 1)} МБ`;
  }

  function date(value) {
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) return 'Дата не указана';
    return new Intl.DateTimeFormat('ru-RU', {
      day: '2-digit', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit',
    }).format(parsed);
  }

  function renderManifest(manifest) {
    const version = manifest.version || manifest.windows?.version || manifest.android?.version || '—';
    const build = manifest.build ?? manifest.windows?.build ?? manifest.android?.build ?? '—';
    const windows = platform(manifest, 'windows');
    const android = platform(manifest, 'android');
    els.heroVersion.textContent = `v${version}`;
    els.heroBuild.textContent = `build ${build}`;
    els.releaseVersion.textContent = `v${version}`;
    els.releaseBuild.textContent = build;
    els.publishedAt.textContent = date(manifest.publishedAt);
    els.changelog.textContent = windows?.notes || android?.notes || manifest.notes || 'Актуальная корпоративная сборка WesiOS.';
    els.windowsSize.textContent = size(windows?.sizeBytes);
    els.androidSize.textContent = size(android?.sizeBytes);
    $$('[data-download]').forEach(button => { button.disabled = !platform(manifest, button.dataset.download); });
    els.footerStatus.textContent = `Релиз v${version} доступен`;
  }

  async function enterDashboard() {
    els.employeeName.textContent = nameOf(state.user);
    els.logoutButton?.classList.remove('hidden');
    showView(els.dashboardView);
    try {
      state.manifest = await request('/api/wesi/portal/manifest');
      renderManifest(state.manifest);
    } catch (error) {
      els.footerStatus.textContent = error.message;
      toast('Список сборок пока недоступен', 'error');
    }
  }

  async function download(platformName, button) {
    const item = platform(state.manifest, platformName);
    if (!item) return;
    setLoading(button, true, 'Подготавливаем…');
    try {
      const response = await fetchTimeout(`${API}/api/wesi/portal/download/${platformName}`, { headers: headers() }, 30000);
      if (!response.ok) throw new Error();
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = item.asset || (platformName === 'windows' ? 'wesios-windows.zip' : 'wesios.apk');
      anchor.click();
      setTimeout(() => URL.revokeObjectURL(url), 30000);
    } catch (_) {
      toast('Не удалось скачать сборку', 'error');
    } finally {
      setLoading(button, false);
    }
  }

  function toast(text, type = '') {
    const node = document.createElement('div');
    node.className = `toast ${type}`;
    node.textContent = text;
    els.toastStack?.appendChild(node);
    setTimeout(() => node.remove(), 4400);
  }

  function initMotion() {
    const root = document.documentElement;
    const revealNodes = $$('[data-scroll-reveal]');
    const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

    root.classList.add('motion-ready');

    const reveal = node => {
      if (!node || node.classList.contains('visible')) return;
      node.classList.add('visible');
      setTimeout(() => node.classList.add('settled'), 820);
    };

    if (reduced || !('IntersectionObserver' in window)) {
      revealNodes.forEach(reveal);
    } else {
      // Почти два экрана запаса. На быстром свайпе слой уже создан и его
      // transition успевает начаться до попадания элемента в viewport.
      const observer = new IntersectionObserver(entries => {
        entries.forEach(entry => {
          if (!entry.isIntersecting) return;
          reveal(entry.target);
          observer.unobserve(entry.target);
        });
      }, { threshold: .001, rootMargin: '90% 0px 90% 0px' });
      revealNodes.forEach(node => observer.observe(node));
    }

    const syncVisibility = () => root.classList.toggle('motion-paused', document.hidden);
    document.addEventListener('visibilitychange', syncVisibility, { passive: true });
    syncVisibility();

    if (reduced) return;

    $$('[data-tilt-card]').forEach(card => {
      let frame = 0;
      let nextX = 0;
      let nextY = 0;

      const renderTilt = () => {
        frame = 0;
        card.style.transform = `perspective(900px) rotateX(${nextY.toFixed(2)}deg) rotateY(${nextX.toFixed(2)}deg) translate3d(0,-2px,0)`;
      };

      card.addEventListener('pointermove', event => {
        if (innerWidth < 900 || event.pointerType === 'touch') return;
        const rect = card.getBoundingClientRect();
        nextX = ((event.clientX - rect.left) / rect.width - .5) * 4;
        nextY = -((event.clientY - rect.top) / rect.height - .5) * 3;
        if (!frame) frame = requestAnimationFrame(renderTilt);
      }, { passive: true });

      card.addEventListener('pointerleave', () => {
        if (frame) cancelAnimationFrame(frame);
        frame = 0;
        card.style.transform = '';
      }, { passive: true });
    });
  }

  function preventPinchZoom() {
    document.addEventListener('gesturestart', event => event.preventDefault(), { passive: false });
    document.addEventListener('touchmove', event => {
      if (event.touches.length > 1) event.preventDefault();
    }, { passive: false });
  }

  function bind() {
    preventPinchZoom();
    els.passwordToggle?.addEventListener('click', () => {
      els.password.type = els.password.type === 'password' ? 'text' : 'password';
    });
    els.loginForm?.addEventListener('submit', async event => {
      event.preventDefault();
      els.loginMessage.textContent = '';
      if (!els.identity.value.trim() || !els.password.value) {
        els.loginMessage.textContent = 'Введите логин и пароль';
        return;
      }
      setLoading(els.loginButton, true, 'Проверяем доступ…');
      try {
        await signIn(els.identity.value, els.password.value);
        els.password.value = '';
        await enterDashboard();
      } catch (error) {
        els.loginMessage.textContent = error.name === 'AbortError' ? 'Сервер не ответил. Повторите попытку.' : 'Неверный логин или пароль';
      } finally {
        setLoading(els.loginButton, false);
      }
    });
    els.logoutButton?.addEventListener('click', () => {
      clearSession();
      showLogin(true);
    });
    $$('[data-download]').forEach(button => {
      button.addEventListener('click', () => download(button.dataset.download, button));
    });
  }

  async function boot() {
    bind();
    showLogin(false);
    requestAnimationFrame(initMotion);
    const valid = await verifySession();
    if (valid) await enterDashboard();
  }

  boot().catch(() => showLogin(false));
})();
