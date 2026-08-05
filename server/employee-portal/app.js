(() => {
  'use strict';

  const API = window.location.origin;
  const TOKEN_KEY = 'wesi_portal_token';
  const USER_KEY = 'wesi_portal_user';
  const STARTUP_TIMEOUT_MS = 2800;
  const REQUEST_TIMEOUT_MS = 8000;

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

  const state = {
    token: sessionStorage.getItem(TOKEN_KEY) || '',
    user: safeJson(sessionStorage.getItem(USER_KEY)),
    manifest: null,
  };

  const els = {
    boot: $('#boot'),
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
    systemStatus: $('#systemStatus'),
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

  function safeJson(value) {
    if (!value) return null;
    try { return JSON.parse(value); } catch (_) { return null; }
  }

  function normalizeIdentity(value) {
    const identity = value.trim();
    if (!identity) return identity;
    return identity.includes('@') ? identity : `${identity.toLowerCase()}@wesi.local`;
  }

  function clearSession() {
    state.token = '';
    state.user = null;
    state.manifest = null;
    sessionStorage.removeItem(TOKEN_KEY);
    sessionStorage.removeItem(USER_KEY);
  }

  function authHeaders(extra = {}) {
    return state.token ? { ...extra, Authorization: state.token } : extra;
  }

  async function fetchWithTimeout(url, options = {}, timeout = REQUEST_TIMEOUT_MS) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);
    try {
      return await fetch(url, { ...options, signal: controller.signal });
    } finally {
      clearTimeout(timer);
    }
  }

  async function request(path, options = {}, timeout = REQUEST_TIMEOUT_MS) {
    const response = await fetchWithTimeout(`${API}${path}`, {
      cache: 'no-store',
      ...options,
      headers: authHeaders(options.headers || {}),
    }, timeout);

    let payload = null;
    const type = response.headers.get('content-type') || '';
    if (type.includes('application/json')) {
      try { payload = await response.json(); } catch (_) { payload = null; }
    }
    if (!response.ok) {
      const error = new Error(payload?.message || `HTTP ${response.status}`);
      error.status = response.status;
      throw error;
    }
    return payload;
  }

  function revealApp() {
    els.boot?.classList.add('done');
    els.app?.classList.add('ready');
    els.app?.setAttribute('aria-hidden', 'false');
  }

  function showView(next) {
    if (!next) return;
    const current = $('.view.active');
    if (current === next) return;
    current?.classList.remove('active', 'leaving');
    next.classList.add('active');
    window.scrollTo({ top: 0, behavior: 'auto' });
  }

  function showLogin() {
    els.logoutButton?.classList.add('hidden');
    if (els.systemStatus) els.systemStatus.textContent = 'Защищённый контур';
    showView(els.loginView);
  }

  function displayName(record) {
    const values = [record?.name, record?.fullName, record?.username, record?.email];
    const value = values.find((item) => typeof item === 'string' && item.trim());
    return (value || 'сотрудник').replace(/@wesi\.local$/i, '').trim();
  }

  function setLoading(button, loading, text = '') {
    if (!button) return;
    button.dataset.original ||= $('span', button)?.textContent || '';
    button.disabled = loading;
    const label = $('span', button);
    if (label) label.textContent = loading ? text : button.dataset.original;
  }

  async function signIn(identity, password) {
    const response = await fetchWithTimeout(`${API}/api/collections/users/auth-with-password`, {
      method: 'POST',
      cache: 'no-store',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ identity: normalizeIdentity(identity), password }),
    });
    const body = await response.json().catch(() => null);
    if (!response.ok || !body?.token) throw new Error('Неверный логин или пароль');
    state.token = body.token;
    state.user = body.record || {};
    sessionStorage.setItem(TOKEN_KEY, state.token);
    sessionStorage.setItem(USER_KEY, JSON.stringify(state.user));
  }

  async function verifySession() {
    if (!state.token) return false;
    try {
      const body = await request('/api/collections/users/auth-refresh', { method: 'POST' }, STARTUP_TIMEOUT_MS);
      state.token = body?.token || state.token;
      state.user = body?.record || state.user || {};
      sessionStorage.setItem(TOKEN_KEY, state.token);
      sessionStorage.setItem(USER_KEY, JSON.stringify(state.user));
      return true;
    } catch (_) {
      clearSession();
      return false;
    }
  }

  function manifestPlatform(manifest, platform) {
    const value = manifest?.[platform];
    return value && typeof value === 'object' ? value : null;
  }

  function formatSize(bytes) {
    const size = Number(bytes);
    if (!Number.isFinite(size) || size <= 0) return '—';
    const mb = size / 1024 / 1024;
    return mb >= 1024 ? `${(mb / 1024).toFixed(1)} ГБ` : `${mb.toFixed(mb >= 10 ? 0 : 1)} МБ`;
  }

  function formatDate(value) {
    const date = value ? new Date(value) : null;
    if (!date || Number.isNaN(date.getTime())) return 'Дата не указана';
    return new Intl.DateTimeFormat('ru-RU', {
      day: '2-digit', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit',
    }).format(date);
  }

  function renderManifest(manifest) {
    const version = manifest.version || manifest.windows?.version || manifest.android?.version || '—';
    const build = manifest.build ?? manifest.windows?.build ?? manifest.android?.build ?? '—';
    const windows = manifestPlatform(manifest, 'windows');
    const android = manifestPlatform(manifest, 'android');
    const notes = windows?.notes || android?.notes || manifest.notes || 'Актуальная корпоративная сборка WesiOS.';

    if (els.heroVersion) els.heroVersion.textContent = `v${version}`;
    if (els.heroBuild) els.heroBuild.textContent = `build ${build}`;
    if (els.releaseVersion) els.releaseVersion.textContent = `v${version}`;
    if (els.releaseBuild) els.releaseBuild.textContent = String(build);
    if (els.publishedAt) els.publishedAt.textContent = formatDate(manifest.publishedAt);
    if (els.changelog) els.changelog.textContent = notes;
    if (els.windowsSize) els.windowsSize.textContent = formatSize(windows?.sizeBytes);
    if (els.androidSize) els.androidSize.textContent = formatSize(android?.sizeBytes);
    $$('[data-download]').forEach((button) => {
      button.disabled = !manifestPlatform(manifest, button.dataset.download);
    });
    if (els.systemStatus) els.systemStatus.textContent = 'Сервер отвечает';
    if (els.footerStatus) els.footerStatus.textContent = `Релиз v${version} доступен`;
  }

  async function loadManifest() {
    state.manifest = await request('/api/wesi/portal/manifest');
    renderManifest(state.manifest);
  }

  async function enterDashboard() {
    if (els.employeeName) els.employeeName.textContent = displayName(state.user);
    els.logoutButton?.classList.remove('hidden');
    showView(els.dashboardView);
    try {
      await loadManifest();
    } catch (error) {
      if (els.systemStatus) els.systemStatus.textContent = 'Сборка недоступна';
      if (els.footerStatus) els.footerStatus.textContent = error.name === 'AbortError' ? 'Сервер отвечает слишком долго' : error.message;
      toast('Не удалось загрузить список сборок', 'error');
    }
  }

  async function download(platform, button) {
    const item = manifestPlatform(state.manifest, platform);
    if (!item) return;
    setLoading(button, true, 'Подготавливаем…');
    try {
      const response = await fetchWithTimeout(`${API}/api/wesi/portal/download/${platform}`, {
        headers: authHeaders(), cache: 'no-store',
      }, 30000);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const blob = await response.blob();
      const disposition = response.headers.get('content-disposition') || '';
      const plain = disposition.match(/filename="?([^";]+)"?/i)?.[1];
      const fallback = item.asset || (platform === 'windows' ? 'wesios-windows-x64.zip' : 'wesios-android.apk');
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = plain || fallback;
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      setTimeout(() => URL.revokeObjectURL(url), 30000);
      toast('Загрузка началась', 'success');
    } catch (_) {
      toast('Не удалось скачать сборку', 'error');
    } finally {
      setLoading(button, false);
    }
  }

  function toast(message, type = '') {
    if (!els.toastStack) return;
    const node = document.createElement('div');
    node.className = `toast ${type}`.trim();
    node.textContent = message;
    els.toastStack.appendChild(node);
    setTimeout(() => node.remove(), 4200);
  }

  function bind() {
    els.passwordToggle?.addEventListener('click', () => {
      els.password.type = els.password.type === 'password' ? 'text' : 'password';
    });

    els.loginForm?.addEventListener('submit', async (event) => {
      event.preventDefault();
      if (els.loginMessage) els.loginMessage.textContent = '';
      if (!els.identity.value.trim() || !els.password.value) {
        if (els.loginMessage) els.loginMessage.textContent = 'Введите логин и пароль';
        return;
      }
      setLoading(els.loginButton, true, 'Проверяем доступ…');
      try {
        await signIn(els.identity.value, els.password.value);
        els.password.value = '';
        await enterDashboard();
      } catch (error) {
        if (els.loginMessage) els.loginMessage.textContent = error.name === 'AbortError'
          ? 'Сервер не ответил. Повторите попытку.'
          : 'Неверный логин или пароль';
      } finally {
        setLoading(els.loginButton, false);
      }
    });

    els.logoutButton?.addEventListener('click', () => {
      clearSession();
      showLogin();
    });

    $$('[data-download]').forEach((button) => {
      button.addEventListener('click', () => download(button.dataset.download, button));
    });
  }

  async function boot() {
    bind();

    // Экран загрузки всегда исчезает максимум через 3 секунды, даже если
    // PocketBase, мобильная сеть или браузер зависли.
    const watchdog = setTimeout(() => {
      revealApp();
      showLogin();
      clearSession();
    }, STARTUP_TIMEOUT_MS + 200);

    try {
      const valid = await verifySession();
      clearTimeout(watchdog);
      revealApp();
      if (valid) await enterDashboard();
      else showLogin();
    } catch (_) {
      clearTimeout(watchdog);
      clearSession();
      revealApp();
      showLogin();
    }
  }

  boot();
})();
