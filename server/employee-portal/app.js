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

  async function request(path, options = {}, timeout = TIMEOUT) {
    const response = await fetchTimeout(`${API}${path}`, {
      cache: 'no-store',
      ...options,
      headers: headers(options.headers || {}),
    }, timeout);
    let body = null;
    try { body = await response.json(); } catch (_) {}
    if (!response.ok) {
      const error = new Error(body?.message || `HTTP ${response.status}`);
      error.status = response.status;
      throw error;
    }
    return body;
  }

  function showView(next, resetScroll = true) {
    $('.view.active')?.classList.remove('active');
    next?.classList.add('active');
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
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;

    const revealNodes = $$('[data-scroll-reveal]');
    const parallaxNodes = $$('[data-parallax]');
    const floatCards = $$('[data-float]');
    const stage = $('#moduleStage');
    let stageActive = false;
    let scheduled = false;

    document.documentElement.classList.add('motion-ready');

    if ('IntersectionObserver' in window) {
      const revealObserver = new IntersectionObserver(entries => {
        entries.forEach(entry => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add('visible');
          revealObserver.unobserve(entry.target);
        });
      }, { threshold: .08, rootMargin: '90px 0px' });
      revealNodes.forEach(node => revealObserver.observe(node));

      if (stage) {
        const stageObserver = new IntersectionObserver(entries => {
          stageActive = entries[0]?.isIntersecting || false;
          if (stageActive) schedule();
        }, { rootMargin: '35% 0px' });
        stageObserver.observe(stage);
      }
    } else {
      revealNodes.forEach(node => node.classList.add('visible'));
      stageActive = true;
    }

    function render() {
      scheduled = false;
      const y = scrollY;
      parallaxNodes.forEach(node => {
        const factor = Number(node.dataset.parallax || 0);
        node.style.transform = `translate3d(0,${(y * factor).toFixed(1)}px,0)`;
      });

      if (stage && stageActive) {
        const rect = stage.getBoundingClientRect();
        const progress = Math.max(0, Math.min(1, (innerHeight - rect.top) / (innerHeight + rect.height)));
        floatCards.forEach((node, index) => {
          const phase = progress * 6.2 + index * 1.4;
          const dx = Math.sin(phase * .88) * (6 + index * 1.5);
          const dy = Math.cos(phase) * (9 + index * 1.8);
          const rotation = Math.sin(phase * .54) * (1.4 + index * .22);
          node.style.transform = `translate3d(${dx.toFixed(1)}px,${dy.toFixed(1)}px,0) rotate(${rotation.toFixed(2)}deg)`;
        });
      }
      document.documentElement.style.setProperty('--scroll', Math.min(1, y / Math.max(1, document.documentElement.scrollHeight - innerHeight)).toFixed(4));
    }

    function schedule() {
      if (!scheduled && !document.hidden) {
        scheduled = true;
        requestAnimationFrame(render);
      }
    }

    addEventListener('scroll', schedule, { passive: true });
    addEventListener('resize', schedule, { passive: true });
    document.addEventListener('visibilitychange', () => { if (!document.hidden) schedule(); });
    schedule();

    $$('[data-tilt-card]').forEach(card => {
      card.addEventListener('pointermove', event => {
        if (innerWidth < 900 || event.pointerType === 'touch') return;
        const rect = card.getBoundingClientRect();
        const x = (event.clientX - rect.left) / rect.width - .5;
        const y = (event.clientY - rect.top) / rect.height - .5;
        card.style.transform = `perspective(900px) rotateX(${-y * 3}deg) rotateY(${x * 4}deg) translateY(-2px)`;
      });
      card.addEventListener('pointerleave', () => { card.style.transform = ''; });
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