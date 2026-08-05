const API = 'https://api.wesi-inc.ru';
const AUTH_URL = `${API}/api/collections/users/auth-with-password`;
const MANIFEST_URL = '/portal/manifest';
const STORAGE_KEY = 'wesios.portal.auth';

const $ = (id) => document.getElementById(id);
const state = { auth: null, profile: null, manifest: null };

function showToast(message) {
  const node = $('toast');
  node.textContent = message;
  node.classList.add('show');
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => node.classList.remove('show'), 3200);
}

function formatBytes(value) {
  if (!Number.isFinite(value) || value <= 0) return 'размер уточняется';
  const units = ['Б', 'КБ', 'МБ', 'ГБ'];
  let size = value;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) { size /= 1024; unit += 1; }
  return `${size.toFixed(unit > 1 ? 1 : 0)} ${units[unit]}`;
}

function safeName(record) {
  return record.displayName || record.name || record.username || record.email?.split('@')[0] || 'сотрудник';
}

function initials(value) {
  return value.split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]).join('').toUpperCase() || 'W';
}

function saveAuth(auth) {
  sessionStorage.setItem(STORAGE_KEY, JSON.stringify(auth));
}

function clearAuth() {
  sessionStorage.removeItem(STORAGE_KEY);
  state.auth = null;
  state.profile = null;
  document.cookie = 'wesios_portal=; Max-Age=0; path=/; Secure; SameSite=Strict';
}

async function createPortalSession(token) {
  const response = await fetch('/portal/session', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    credentials: 'include',
    body: JSON.stringify({ token }),
  });
  if (!response.ok) throw new Error('Не удалось создать защищённую сессию загрузки');
}

async function refreshAuth(auth) {
  const response = await fetch(`${API}/api/collections/users/auth-refresh`, {
    method: 'POST',
    headers: { Authorization: auth.token },
  });
  if (!response.ok) throw new Error('Сессия истекла');
  return response.json();
}

function profileAllowed(record) {
  return record.portalAccess !== false && record.verified !== false;
}

function renderPortal(auth) {
  const profile = auth.record;
  state.auth = auth;
  state.profile = profile;
  const name = safeName(profile);
  $('profile-name').textContent = name;
  $('profile-card-name').textContent = name;
  $('profile-avatar').textContent = initials(name);
  $('profile-role').textContent = profile.jobTitle || profile.role || 'Employee';
  $('profile-subtitle').textContent = profile.department
    ? `${profile.department} · защищённое рабочее пространство готово.`
    : 'Ваше защищённое рабочее пространство готово.';
  $('download-access').textContent = profile.portalAccess === false ? 'Запрещено' : 'Разрешено';
  $('auth-scene').classList.add('hidden');
  $('portal').classList.remove('hidden');
  $('logout-button').classList.remove('hidden');
  window.scrollTo({ top: 0, behavior: 'instant' });
  loadManifest();
}

async function login(email, password) {
  const response = await fetch(AUTH_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ identity: email, password }),
  });
  if (!response.ok) throw new Error('Неверная рабочая почта или пароль');
  const auth = await response.json();
  if (!profileAllowed(auth.record)) throw new Error('Профиль не подтверждён для доступа к порталу');
  await createPortalSession(auth.token);
  saveAuth(auth);
  renderPortal(auth);
}

async function restoreSession() {
  const raw = sessionStorage.getItem(STORAGE_KEY);
  if (!raw) return;
  try {
    const saved = JSON.parse(raw);
    const auth = await refreshAuth(saved);
    if (!profileAllowed(auth.record)) throw new Error('Доступ отключён');
    await createPortalSession(auth.token);
    saveAuth(auth);
    renderPortal(auth);
  } catch (_) {
    clearAuth();
  }
}

async function loadManifest() {
  try {
    const response = await fetch(MANIFEST_URL, { credentials: 'include', cache: 'no-store' });
    if (response.status === 401 || response.status === 403) throw new Error('Нет доступа к релизам');
    if (!response.ok) throw new Error(`Manifest HTTP ${response.status}`);
    const manifest = await response.json();
    state.manifest = manifest;
    const version = manifest.version || manifest.windows?.version || manifest.android?.version || 'latest';
    $('release-version').textContent = version;
    $('release-note').textContent = manifest.windows?.notes || manifest.android?.notes || 'Актуальная внутренняя сборка компании.';
    $('windows-meta').textContent = `Версия ${manifest.windows?.version || version} · ${formatBytes(manifest.windows?.sizeBytes)}`;
    $('android-meta').textContent = `Версия ${manifest.android?.version || version} · ${formatBytes(manifest.android?.sizeBytes)}`;
  } catch (error) {
    $('release-note').textContent = error.message;
    $('windows-meta').textContent = 'Сборка временно недоступна';
    $('android-meta').textContent = 'Сборка временно недоступна';
  }
}

async function download(platform, button) {
  if (!state.profile || state.profile.portalAccess === false) {
    showToast('У профиля нет разрешения на скачивание');
    return;
  }
  const original = button.querySelector('span').textContent;
  button.disabled = true;
  button.querySelector('span').textContent = 'Подготовка файла…';
  try {
    const response = await fetch(`/portal/download/${platform}`, { credentials: 'include' });
    if (response.status === 401 || response.status === 403) throw new Error('Сессия или разрешение недействительны');
    if (!response.ok) throw new Error(`Не удалось получить файл (${response.status})`);
    const blob = await response.blob();
    const disposition = response.headers.get('Content-Disposition') || '';
    const matched = disposition.match(/filename="?([^";]+)"?/i);
    const fallback = platform === 'windows' ? 'wesios-windows-x64.zip' : 'wesios-android.apk';
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = matched?.[1] || fallback;
    document.body.append(anchor);
    anchor.click();
    anchor.remove();
    URL.revokeObjectURL(url);
    showToast('Загрузка WesiOS началась');
  } catch (error) {
    showToast(error.message);
  } finally {
    button.disabled = false;
    button.querySelector('span').textContent = original;
  }
}

async function checkHealth() {
  try {
    const started = performance.now();
    const response = await fetch(`${API}/api/health`, { cache: 'no-store' });
    if (!response.ok) throw new Error();
    const latency = Math.round(performance.now() - started);
    $('server-state').classList.add('online');
    $('server-state').querySelector('span').textContent = 'Система онлайн';
    $('api-detail').textContent = `Защищённое соединение · ${latency} ms`;
  } catch (_) {
    $('server-state').querySelector('span').textContent = 'Система недоступна';
    $('api-detail').textContent = 'Нет соединения';
  }
}

function startAmbient() {
  const canvas = $('ambient');
  const ctx = canvas.getContext('2d');
  const dots = Array.from({ length: 44 }, () => ({ x: Math.random(), y: Math.random(), r: .4 + Math.random() * 1.5, v: .00008 + Math.random() * .0002, a: .08 + Math.random() * .22 }));
  function resize() { canvas.width = innerWidth * devicePixelRatio; canvas.height = innerHeight * devicePixelRatio; }
  function draw() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const gradient = ctx.createRadialGradient(canvas.width * .68, 0, 0, canvas.width * .68, 0, canvas.width * .72);
    gradient.addColorStop(0, 'rgba(117,88,255,.16)'); gradient.addColorStop(.55, 'rgba(20,24,40,.045)'); gradient.addColorStop(1, 'rgba(7,9,13,0)');
    ctx.fillStyle = gradient; ctx.fillRect(0, 0, canvas.width, canvas.height);
    for (const dot of dots) {
      dot.y -= dot.v; if (dot.y < -.02) { dot.y = 1.02; dot.x = Math.random(); }
      ctx.beginPath(); ctx.fillStyle = `rgba(210,220,255,${dot.a})`; ctx.arc(dot.x * canvas.width, dot.y * canvas.height, dot.r * devicePixelRatio, 0, Math.PI * 2); ctx.fill();
    }
    requestAnimationFrame(draw);
  }
  addEventListener('resize', resize); resize(); draw();
}

$('login-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const button = $('login-button');
  const error = $('form-error');
  error.textContent = '';
  button.disabled = true;
  button.querySelector('span').textContent = 'Проверка профиля…';
  try { await login($('email').value.trim(), $('password').value); }
  catch (exception) { error.textContent = exception.message; }
  finally { button.disabled = false; button.querySelector('span').textContent = 'Войти в систему'; }
});

$('password-toggle').addEventListener('click', () => {
  const input = $('password');
  input.type = input.type === 'password' ? 'text' : 'password';
});

$('logout-button').addEventListener('click', async () => {
  try { await fetch('/portal/session', { method: 'DELETE', credentials: 'include' }); } catch (_) {}
  clearAuth();
  location.reload();
});

document.querySelectorAll('[data-download]').forEach((button) => button.addEventListener('click', () => download(button.dataset.download, button)));
document.addEventListener('pointermove', (event) => { $('cursor-glow').style.left = `${event.clientX}px`; $('cursor-glow').style.top = `${event.clientY}px`; });

startAmbient();
checkHealth();
restoreSession();
