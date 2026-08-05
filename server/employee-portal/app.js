(() => {
  'use strict';

  const API = window.location.origin;
  const TOKEN_KEY = 'wesi_portal_token';
  const USER_KEY = 'wesi_portal_user';

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

  function authHeaders(extra = {}) {
    return state.token ? { ...extra, Authorization: state.token } : extra;
  }

  async function request(path, options = {}) {
    const response = await fetch(`${API}${path}`, {
      cache: 'no-store',
      ...options,
      headers: authHeaders(options.headers || {}),
    });

    let payload = null;
    const type = response.headers.get('content-type') || '';
    if (type.includes('application/json')) {
      try { payload = await response.json(); } catch (_) { payload = null; }
    }

    if (!response.ok) {
      const error = new Error(payload?.message || `HTTP ${response.status}`);
      error.status = response.status;
      error.payload = payload;
      throw error;
    }
    return payload;
  }

  async function signIn(identity, password) {
    const response = await fetch(`${API}/api/collections/users/auth-with-password`, {
      method: 'POST',
      cache: 'no-store',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ identity: normalizeIdentity(identity), password }),
    });
    const body = await response.json().catch(() => null);
    if (!response.ok || !body?.token) {
      const error = new Error('Неверный логин или пароль');
      error.status = response.status;
      throw error;
    }
    state.token = body.token;
    state.user = body.record || {};
    sessionStorage.setItem(TOKEN_KEY, state.token);
    sessionStorage.setItem(USER_KEY, JSON.stringify(state.user));
  }

  async function verifySession() {
    if (!state.token) return false;
    try {
      const body = await request('/api/collections/users/auth-refresh', { method: 'POST' });
      if (body?.token) {
        state.token = body.token;
        state.user = body.record || state.user || {};
        sessionStorage.setItem(TOKEN_KEY, state.token);
        sessionStorage.setItem(USER_KEY, JSON.stringify(state.user));
      }
      return true;
    } catch (_) {
      clearSession();
      return false;
    }
  }

  function clearSession() {
    state.token = '';
    state.user = null;
    state.manifest = null;
    sessionStorage.removeItem(TOKEN_KEY);
    sessionStorage.removeItem(USER_KEY);
  }

  function displayName(record) {
    const candidates = [record?.name, record?.fullName, record?.username, record?.email];
    const value = candidates.find((item) => typeof item === 'string' && item.trim());
    if (!value) return 'сотрудник';
    const cleaned = value.replace(/@wesi\.local$/i, '').trim();
    return cleaned || 'сотрудник';
  }

  function showView(next) {
    const current = $('.view.active');
    if (current === next) return;
    if (!current) {
      next.classList.add('active');
      return;
    }
    current.classList.add('leaving');
    setTimeout(() => {
      current.classList.remove('active', 'leaving');
      next.classList.add('active');
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }, 320);
  }

  function setLoading(button, loading, text = '') {
    button.disabled = loading;
    button.dataset.original ||= $('span', button)?.textContent || '';
    const label = $('span', button);
    if (label) label.textContent = loading ? text : button.dataset.original;
  }

  function formatSize(bytes) {
    const size = Number(bytes);
    if (!Number.isFinite(size) || size <= 0) return 'размер уточняется';
    const units = ['Б', 'КБ', 'МБ', 'ГБ'];
    let value = size;
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    return `${value >= 10 || unit === 0 ? value.toFixed(0) : value.toFixed(1)} ${units[unit]}`;
  }

  function formatDate(value) {
    if (!value) return 'Дата публикации не указана';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return 'Дата публикации не указана';
    return new Intl.DateTimeFormat('ru-RU', {
      day: '2-digit', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit',
    }).format(date);
  }

  function manifestPlatform(manifest, platform) {
    const data = manifest?.[platform];
    return data && typeof data === 'object' ? data : null;
  }

  async function loadManifest() {
    let manifest;
    try {
      manifest = await request('/api/wesi/portal/manifest');
    } catch (error) {
      // Совместимость с сервером, на котором защищённый hook ещё не установлен.
      // Вход сотрудника всё равно обязателен в интерфейсе, а после установки
      // hook этот fallback перестанет использоваться автоматически.
      if (![404, 405].includes(error.status)) throw error;
      const candidates = [
        '/artifacts/app/app-manifest.json',
        '/app/app-manifest.json',
      ];
      for (const path of candidates) {
        const response = await fetch(`${API}${path}`, { cache: 'no-store' });
        if (response.ok) {
          manifest = await response.json();
          manifest.__publicBase = path.replace(/\/app-manifest\.json$/, '');
          break;
        }
      }
      if (!manifest) throw new Error('Сервер пока не опубликовал сборку WesiOS');
    }
    state.manifest = manifest;
    renderManifest(manifest);
  }

  function renderManifest(manifest) {
    const version = manifest.version || manifest.windows?.version || manifest.android?.version || '—';
    const build = manifest.build ?? manifest.windows?.build ?? manifest.android?.build ?? '—';
    const windows = manifestPlatform(manifest, 'windows');
    const android = manifestPlatform(manifest, 'android');
    const notes = windows?.notes || android?.notes || manifest.notes || 'Актуальная корпоративная сборка WesiOS.';

    els.heroVersion.textContent = `v${version}`;
    els.heroBuild.textContent = `build ${build}`;
    els.releaseVersion.textContent = `v${version}`;
    els.releaseBuild.textContent = String(build);
    els.publishedAt.textContent = formatDate(manifest.publishedAt);
    els.changelog.textContent = notes;
    els.windowsSize.textContent = formatSize(windows?.sizeBytes);
    els.androidSize.textContent = formatSize(android?.sizeBytes);

    $$('[data-download]').forEach((button) => {
      const platform = button.dataset.download;
      button.disabled = !manifestPlatform(manifest, platform);
    });

    els.systemStatus.textContent = 'Сервер отвечает';
    els.footerStatus.textContent = `Релиз v${version} доступен для загрузки`;
  }

  async function enterDashboard() {
    els.employeeName.textContent = displayName(state.user);
    els.logoutButton.classList.remove('hidden');
    showView(els.dashboardView);
    try {
      await loadManifest();
    } catch (error) {
      els.systemStatus.textContent = 'Сборка недоступна';
      els.footerStatus.textContent = error.message;
      toast(error.message, 'error');
    }
  }

  function showLogin() {
    els.logoutButton.classList.add('hidden');
    els.systemStatus.textContent = 'Защищённый контур';
    showView(els.loginView);
  }

  async function download(platform, button) {
    const item = manifestPlatform(state.manifest, platform);
    if (!item) return;

    const card = button.closest('.download-card');
    const progress = $('.download-progress', card);
    const bar = $('.download-progress i', card);
    progress.classList.add('active');
    bar.style.width = '12%';
    setLoading(button, true, 'Подготавливаем файл…');

    try {
      let response = await fetch(`${API}/api/wesi/portal/download/${platform}`, {
        headers: authHeaders(),
        cache: 'no-store',
      });

      if ([404, 405].includes(response.status) && state.manifest.__publicBase && item.path) {
        response = await fetch(`${API}${state.manifest.__publicBase}/${item.path.replace(/^\/+/, '')}`);
      }
      if (!response.ok) throw new Error(`Файл недоступен: HTTP ${response.status}`);

      const total = Number(response.headers.get('content-length')) || Number(item.sizeBytes) || 0;
      const reader = response.body?.getReader();
      let blob;

      if (reader) {
        const chunks = [];
        let loaded = 0;
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          chunks.push(value);
          loaded += value.byteLength;
          const percent = total > 0 ? Math.min(94, Math.max(12, (loaded / total) * 94)) : 45;
          bar.style.width = `${percent}%`;
          $('span', button).textContent = total > 0
            ? `Загрузка ${Math.round((loaded / total) * 100)}%`
            : 'Загрузка…';
        }
        blob = new Blob(chunks, { type: response.headers.get('content-type') || 'application/octet-stream' });
      } else {
        blob = await response.blob();
      }

      bar.style.width = '100%';
      const disposition = response.headers.get('content-disposition') || '';
      const encoded = disposition.match(/filename\*=UTF-8''([^;]+)/i)?.[1];
      const plain = disposition.match(/filename="?([^";]+)"?/i)?.[1];
      const fallback = item.asset || (platform === 'windows' ? 'wesios-windows-x64.zip' : 'wesios-android.apk');
      const fileName = encoded ? decodeURIComponent(encoded) : (plain || fallback);

      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = fileName;
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      setTimeout(() => URL.revokeObjectURL(url), 30_000);
      toast(`${fileName} готов к установке`, 'success');
    } catch (error) {
      toast(error.message || 'Не удалось скачать сборку', 'error');
    } finally {
      setTimeout(() => {
        setLoading(button, false);
        progress.classList.remove('active');
        bar.style.width = '0';
      }, 650);
    }
  }

  function toast(message, type = '') {
    const node = document.createElement('div');
    node.className = `toast ${type}`.trim();
    node.textContent = message;
    els.toastStack.appendChild(node);
    setTimeout(() => {
      node.style.opacity = '0';
      node.style.transform = 'translateY(8px)';
      setTimeout(() => node.remove(), 250);
    }, 4200);
  }

  function constellation() {
    const canvas = $('#constellation');
    const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (!canvas || reduced) return;
    const ctx = canvas.getContext('2d');
    let points = [];
    let animation;

    function resize() {
      const ratio = Math.min(devicePixelRatio || 1, 2);
      canvas.width = innerWidth * ratio;
      canvas.height = innerHeight * ratio;
      canvas.style.width = `${innerWidth}px`;
      canvas.style.height = `${innerHeight}px`;
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
      const count = Math.min(70, Math.max(28, Math.floor(innerWidth / 24)));
      points = Array.from({ length: count }, () => ({
        x: Math.random() * innerWidth,
        y: Math.random() * innerHeight,
        vx: (Math.random() - .5) * .09,
        vy: (Math.random() - .5) * .09,
        r: Math.random() * 1.2 + .25,
      }));
    }

    function frame() {
      ctx.clearRect(0, 0, innerWidth, innerHeight);
      for (const p of points) {
        p.x += p.vx; p.y += p.vy;
        if (p.x < -10) p.x = innerWidth + 10;
        if (p.x > innerWidth + 10) p.x = -10;
        if (p.y < -10) p.y = innerHeight + 10;
        if (p.y > innerHeight + 10) p.y = -10;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(169,156,255,.45)';
        ctx.fill();
      }
      for (let i = 0; i < points.length; i += 1) {
        for (let j = i + 1; j < points.length; j += 1) {
          const dx = points[i].x - points[j].x;
          const dy = points[i].y - points[j].y;
          const distance = Math.hypot(dx, dy);
          if (distance < 115) {
            ctx.beginPath();
            ctx.moveTo(points[i].x, points[i].y);
            ctx.lineTo(points[j].x, points[j].y);
            ctx.strokeStyle = `rgba(117,101,205,${(1 - distance / 115) * .11})`;
            ctx.lineWidth = .7;
            ctx.stroke();
          }
        }
      }
      animation = requestAnimationFrame(frame);
    }

    resize(); frame();
    addEventListener('resize', () => {
      cancelAnimationFrame(animation);
      resize(); frame();
    }, { passive: true });
  }

  function bind() {
    els.passwordToggle.addEventListener('click', () => {
      const visible = els.password.type === 'text';
      els.password.type = visible ? 'password' : 'text';
      els.passwordToggle.setAttribute('aria-label', visible ? 'Показать пароль' : 'Скрыть пароль');
    });

    els.loginForm.addEventListener('submit', async (event) => {
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
        toast('Доступ подтверждён', 'success');
      } catch (_) {
        els.loginMessage.textContent = 'Неверный логин или пароль';
      } finally {
        setLoading(els.loginButton, false);
      }
    });

    els.logoutButton.addEventListener('click', () => {
      clearSession();
      showLogin();
      toast('Сеанс завершён');
    });

    $$('[data-download]').forEach((button) => {
      button.addEventListener('click', () => download(button.dataset.download, button));
    });
  }

  async function boot() {
    bind();
    constellation();
    const minimum = new Promise((resolve) => setTimeout(resolve, 900));
    const valid = await verifySession();
    await minimum;
    els.boot.classList.add('done');
    els.app.classList.add('ready');
    els.app.setAttribute('aria-hidden', 'false');
    if (valid) await enterDashboard();
    else showLogin();
  }

  boot().catch((error) => {
    els.boot.classList.add('done');
    els.app.classList.add('ready');
    showLogin();
    toast(error.message || 'Не удалось открыть портал', 'error');
  });
})();
