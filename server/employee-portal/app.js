(() => {
  'use strict';

  const API = location.origin;
  const TOKEN_KEY = 'wesi_portal_token';
  const USER_KEY = 'wesi_portal_user';
  const SESSION_KEY = 'wesi_portal_session';
  const TIMEOUT = 10000;
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

  function json(value) {
    try { return value ? JSON.parse(value) : null; } catch (_) { return null; }
  }

  function stored(key) {
    try { return localStorage.getItem(key) || sessionStorage.getItem(key) || ''; }
    catch (_) { return ''; }
  }

  const state = {
    token: stored(TOKEN_KEY),
    sessionId: stored(SESSION_KEY),
    user: json(stored(USER_KEY)),
    manifest: null,
    challengeId: '',
    maskedEmail: '',
    remember: false,
    heartbeat: 0,
  };

  const els = {
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
    themeSwitch: $('#themeSwitch'),
    themeColor: $('#themeColor'),
  };

  const THEME_KEY = 'wesi-theme';
  const THEME_BAR = { dark: '#08080b', light: '#f4f6fb' };

  function currentTheme() {
    return document.documentElement.getAttribute('data-theme') === 'light' ? 'light' : 'dark';
  }

  function applyTheme(theme, animate) {
    const root = document.documentElement;
    if (animate) {
      root.classList.add('theme-shifting');
      clearTimeout(applyTheme.timer);
      applyTheme.timer = setTimeout(() => root.classList.remove('theme-shifting'), 460);
    }
    if (theme === 'light') root.setAttribute('data-theme', 'light');
    else root.removeAttribute('data-theme');
    els.themeColor?.setAttribute('content', THEME_BAR[theme] || THEME_BAR.dark);
    if (els.themeSwitch) {
      els.themeSwitch.setAttribute('aria-checked', theme === 'light' ? 'true' : 'false');
      els.themeSwitch.setAttribute('aria-label', theme === 'light' ? 'Тёмная тема' : 'Светлая тема');
    }
    try { localStorage.setItem(THEME_KEY, theme); } catch (_) {}
  }

  function clearSession() {
    stopHeartbeat();
    state.token = '';
    state.sessionId = '';
    state.user = null;
    state.manifest = null;
    for (const storage of [localStorage, sessionStorage]) {
      try {
        storage.removeItem(TOKEN_KEY);
        storage.removeItem(USER_KEY);
        storage.removeItem(SESSION_KEY);
      } catch (_) {}
    }
  }

  function persistSession(remember) {
    const target = remember ? localStorage : sessionStorage;
    const other = remember ? sessionStorage : localStorage;
    try {
      other.removeItem(TOKEN_KEY);
      other.removeItem(USER_KEY);
      other.removeItem(SESSION_KEY);
      target.setItem(TOKEN_KEY, state.token);
      target.setItem(SESSION_KEY, state.sessionId);
      target.setItem(USER_KEY, JSON.stringify(state.user || {}));
    } catch (_) {}
  }

  function headers(extra = {}) {
    if (!state.token || !state.sessionId) return extra;
    return {
      ...extra,
      Authorization: state.token,
      'X-WesiOS-Session': state.sessionId,
    };
  }

  async function fetchTimeout(url, options = {}, timeout = TIMEOUT) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);
    try { return await fetch(url, { ...options, signal: controller.signal }); }
    finally { clearTimeout(timer); }
  }

  const GENERIC_FAILURES = [
    'something went wrong',
    'failed to authenticate',
    'the request requires valid record authorization token',
  ];

  function describeFailure(status, message) {
    const raw = (message || '').trim();
    const generic = !raw || GENERIC_FAILURES.some(p => raw.toLowerCase().includes(p));
    if (!generic) return raw;
    if (status === 401) return 'Неверные данные или сеанс завершён';
    if (status === 403) return 'Доступ к профилю закрыт';
    if (status === 429) return 'Слишком много попыток — повторите позже';
    if (status === 404) return 'Сборка ещё не опубликована на сервере';
    if (status >= 500) return 'Сервер не смог ответить — попробуйте позже';
    return 'Не удалось получить данные с сервера';
  }

  async function request(path, options = {}, timeout = TIMEOUT, authenticated = true) {
    const response = await fetchTimeout(`${API}${path}`, {
      cache: 'no-store',
      ...options,
      headers: authenticated ? headers(options.headers || {}) : (options.headers || {}),
    }, timeout);
    let body = null;
    try { body = await response.json(); } catch (_) {}
    if (!response.ok) {
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
    document.documentElement.classList.toggle('view-dashboard', next?.id === 'dashboardView');
    if (resetScroll) scrollTo(0, 0);
  }

  function showLogin(resetScroll = false) {
    els.logoutButton?.classList.add('hidden');
    showPasswordStep();
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
    return (record?.name || record?.login || record?.email || 'сотрудник').replace(/@wesi\.local$/i, '');
  }

  function ensureSecurityUi() {
    if ($('#otpForm')) return;
    const style = document.createElement('style');
    style.textContent = `
      .remember-row{display:flex;align-items:center;gap:10px;margin:12px 0 4px;color:var(--t2);font-size:13px;cursor:pointer}
      .remember-row input{width:18px;height:18px;accent-color:rgb(var(--a3))}
      .otp-form{display:none}.otp-form.active{display:block}.login-form-hidden{display:none!important}
      .otp-destination{font-size:12px;line-height:1.5;color:var(--t2);margin:0 0 14px}
      .otp-code{text-align:center!important;font-size:25px!important;font-weight:750!important;letter-spacing:9px!important;font-variant-numeric:tabular-nums}
      .otp-actions{display:flex;justify-content:center;gap:8px;flex-wrap:wrap;margin-top:8px}
      .otp-actions button{border:0;background:transparent;color:var(--t2);padding:8px 10px;cursor:pointer;font:inherit}
      .otp-actions button:hover{color:var(--t1)}
    `;
    document.head.appendChild(style);

    const message = els.loginMessage;
    const remember = document.createElement('label');
    remember.className = 'remember-row';
    remember.innerHTML = '<input id="rememberLogin" type="checkbox" checked><span>Запомнить меня на этом устройстве</span>';
    message?.parentNode?.insertBefore(remember, message);

    const form = document.createElement('form');
    form.id = 'otpForm';
    form.className = 'otp-form';
    form.noValidate = true;
    form.innerHTML = `
      <p class="otp-destination" id="otpDestination">Код отправлен на вашу почту.</p>
      <label class="field"><span>6-значный код</span><span class="input-wrap"><svg viewBox="0 0 24 24"><path d="M7 10V8a5 5 0 0 1 10 0v2M6 10h12a2 2 0 0 1 2 2v7H4v-7a2 2 0 0 1 2-2Z"/></svg><input class="otp-code" id="otpCode" inputmode="numeric" autocomplete="one-time-code" maxlength="6" pattern="[0-9]{6}" placeholder="000000" required></span></label>
      <div class="form-message" id="otpMessage" role="alert"></div>
      <button class="primary-button" id="otpButton" type="submit"><span>Подтвердить и продолжить</span><svg viewBox="0 0 24 24"><path d="m9 18 6-6-6-6"/></svg></button>
      <div class="otp-actions"><button id="otpResend" type="button">Отправить новый код</button><button id="otpBack" type="button">Назад</button></div>
    `;
    els.loginForm?.parentNode?.insertBefore(form, els.loginForm.nextSibling);
  }

  function showOtpStep(maskedEmail) {
    els.loginForm?.classList.add('login-form-hidden');
    $('#otpForm')?.classList.add('active');
    const destination = $('#otpDestination');
    if (destination) destination.textContent = `Код отправлен на ${maskedEmail || 'почту профиля'}. Он действует 10 минут.`;
    const code = $('#otpCode');
    if (code) { code.value = ''; setTimeout(() => code.focus(), 60); }
    if (els.loginMessage) els.loginMessage.textContent = '';
    const otpMessage = $('#otpMessage');
    if (otpMessage) otpMessage.textContent = '';
  }

  function showPasswordStep() {
    state.challengeId = '';
    state.maskedEmail = '';
    els.loginForm?.classList.remove('login-form-hidden');
    $('#otpForm')?.classList.remove('active');
    const otpMessage = $('#otpMessage');
    if (otpMessage) otpMessage.textContent = '';
  }

  async function beginSignIn() {
    const login = els.identity.value.trim().toLowerCase();
    const password = els.password.value;
    if (!login || !password) throw new Error('Введите логин и пароль');
    const body = await request('/api/wesi/auth/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ login, password, purpose: 'portal' }),
    }, 20000, false);
    if (!body?.challengeId) throw new Error('Сервер не создал проверку входа');
    state.challengeId = body.challengeId;
    state.maskedEmail = body.maskedEmail || '';
    state.remember = $('#rememberLogin')?.checked !== false;
    showOtpStep(state.maskedEmail);
  }

  async function verifyCode() {
    const code = ($('#otpCode')?.value || '').trim();
    if (!/^\d{6}$/.test(code)) throw new Error('Введите 6 цифр из письма');
    const body = await request('/api/wesi/auth/verify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        challengeId: state.challengeId,
        code,
        remember: state.remember,
        device: {
          platform: navigator.platform || 'browser',
          deviceName: navigator.userAgentData?.platform || navigator.platform || 'Браузер',
          timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || '',
        },
      }),
    }, 20000, false);
    if (!body?.token || !body?.sessionId) throw new Error('Сервер не вернул подтверждённый сеанс');
    state.token = body.token;
    state.sessionId = body.sessionId;
    state.user = body.record || {};
    persistSession(state.remember);
    els.password.value = '';
  }

  async function pingSession() {
    if (!state.token || !state.sessionId) return false;
    try {
      await request('/api/wesi/security/session/ping', { method: 'GET' }, 5000);
      return true;
    } catch (error) {
      if (error?.status === 401 || error?.status === 403) {
        clearSession();
        showLogin(true);
        toast('Сеанс завершён. Войдите заново.', 'error');
      }
      return false;
    }
  }

  function startHeartbeat() {
    stopHeartbeat();
    state.heartbeat = setInterval(() => { pingSession(); }, 5000);
  }

  function stopHeartbeat() {
    if (state.heartbeat) clearInterval(state.heartbeat);
    state.heartbeat = 0;
  }

  async function verifySession() {
    if (!state.token || !state.sessionId) return false;
    return pingSession();
  }

  async function remoteLogout() {
    if (state.token && state.sessionId) {
      try {
        await request('/api/wesi/security/sessions/revoke', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ sessionId: state.sessionId }),
        }, 5000);
      } catch (_) {}
    }
    clearSession();
    showLogin(true);
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
    startHeartbeat();
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
    const fallback = platformName === 'windows' ? 'wesios-windows-x64.zip' : 'wesios-android.apk';
    const name = item.asset || fallback;
    let writable = null;
    setLoading(button, true, 'Скачиваем…');
    try {
      if (platformName === 'windows' && window.showSaveFilePicker) {
        try {
          const handle = await window.showSaveFilePicker({
            suggestedName: name,
            types: [{ description: 'WesiOS Windows', accept: { 'application/zip': ['.zip'] } }],
          });
          writable = await handle.createWritable();
        } catch (error) {
          if (error?.name === 'AbortError') return;
        }
      }
      const response = await fetch(`${API}/api/wesi/portal/download/${platformName}`, {
        method: 'GET', cache: 'no-store', headers: headers(),
      });
      if (!response.ok) {
        if (response.status === 401 || response.status === 403) {
          clearSession(); showLogin(true);
        }
        throw new Error(`HTTP ${response.status}`);
      }
      const total = Number(response.headers.get('content-length') || item.sizeBytes || 0);
      let received = 0;
      const progress = () => {
        if (total) button.dataset.progress = `${Math.min(100, Math.round(received * 100 / total))}%`;
      };
      if (writable && response.body) {
        const reader = response.body.getReader();
        while (true) {
          const chunk = await reader.read();
          if (chunk.done) break;
          received += chunk.value.byteLength;
          await writable.write(chunk.value);
          progress();
        }
        await writable.close();
        writable = null;
        toast('WesiOS сохранён на компьютер');
        return;
      }
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = name;
      anchor.style.display = 'none';
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      setTimeout(() => URL.revokeObjectURL(url), 60000);
      toast('Скачивание началось');
    } catch (_) {
      if (writable) try { await writable.abort(); } catch (_) {}
      toast('Не удалось скачать сборку', 'error');
    } finally {
      delete button.dataset.progress;
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
    if (reduced || !('IntersectionObserver' in window)) revealNodes.forEach(reveal);
    else {
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
  }

  function preventPinchZoom() {
    document.addEventListener('gesturestart', event => event.preventDefault(), { passive: false });
    document.addEventListener('touchmove', event => {
      if (event.touches.length > 1) event.preventDefault();
    }, { passive: false });
  }

  function bindRequirements() {
    const trigger = $('#requirementsTrigger');
    const popover = $('#requirementsPopover');
    if (!trigger || !popover) return;
    const setOpen = open => {
      trigger.setAttribute('aria-expanded', open ? 'true' : 'false');
      popover.setAttribute('aria-hidden', open ? 'false' : 'true');
      popover.classList.toggle('is-open', open);
    };
    trigger.addEventListener('click', event => {
      event.preventDefault(); event.stopPropagation();
      setOpen(trigger.getAttribute('aria-expanded') !== 'true');
    });
    popover.addEventListener('click', event => event.stopPropagation());
    document.addEventListener('click', () => setOpen(false));
    document.addEventListener('keydown', event => { if (event.key === 'Escape') setOpen(false); });
  }

  function bind() {
    ensureSecurityUi();
    bindRequirements();
    preventPinchZoom();
    applyTheme(currentTheme(), false);
    els.themeSwitch?.addEventListener('click', () => {
      applyTheme(currentTheme() === 'light' ? 'dark' : 'light', true);
    });
    els.passwordToggle?.addEventListener('click', () => {
      els.password.type = els.password.type === 'password' ? 'text' : 'password';
    });
    els.loginForm?.addEventListener('submit', async event => {
      event.preventDefault();
      els.loginMessage.textContent = '';
      setLoading(els.loginButton, true, 'Отправляем код…');
      try { await beginSignIn(); }
      catch (error) {
        els.loginMessage.textContent = error?.name === 'AbortError'
          ? 'Сервер не ответил. Повторите попытку.'
          : (error?.message || 'Не удалось войти');
      } finally { setLoading(els.loginButton, false); }
    });
    $('#otpForm')?.addEventListener('submit', async event => {
      event.preventDefault();
      const message = $('#otpMessage');
      if (message) message.textContent = '';
      const button = $('#otpButton');
      setLoading(button, true, 'Проверяем код…');
      try {
        await verifyCode();
        await enterDashboard();
      } catch (error) {
        if (message) message.textContent = error?.message || 'Неверный код';
      } finally { setLoading(button, false); }
    });
    $('#otpResend')?.addEventListener('click', async () => {
      const message = $('#otpMessage');
      try {
        await beginSignIn();
        if (message) message.textContent = 'Новый код отправлен.';
      } catch (error) {
        if (message) message.textContent = error?.message || 'Не удалось отправить новый код';
      }
    });
    $('#otpBack')?.addEventListener('click', showPasswordStep);
    els.logoutButton?.addEventListener('click', () => { remoteLogout(); });
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
