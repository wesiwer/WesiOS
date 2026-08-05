const repo = 'wesiwer/WesiOS';
const tag = 'app-latest';
const releaseBase = `https://github.com/${repo}/releases/download/${tag}`;
const manifestUrl = `${releaseBase}/app-manifest.json`;

const formatBytes = (value) => {
  if (!Number.isFinite(value) || value <= 0) return null;
  const units = ['Б', 'КБ', 'МБ', 'ГБ'];
  let size = value;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit += 1;
  }
  return `${size.toFixed(unit > 1 ? 1 : 0)} ${units[unit]}`;
};

const setMeta = (id, platform, manifest) => {
  const node = document.getElementById(id);
  const data = manifest?.[platform];
  if (!node || !data) return;
  const parts = [];
  if (data.version) parts.push(`Версия ${data.version}`);
  const size = formatBytes(data.sizeBytes);
  if (size) parts.push(size);
  node.textContent = parts.length ? parts.join(' · ') : 'Актуальная сборка';
};

const choosePrimary = () => {
  const ua = navigator.userAgent.toLowerCase();
  const primary = document.getElementById('download-primary');
  if (!primary) return;
  if (ua.includes('android')) {
    primary.href = `${releaseBase}/wesios-android.apk`;
    primary.textContent = 'Скачать для Android';
  } else if (ua.includes('windows')) {
    primary.href = `${releaseBase}/wesios-windows-x64.zip`;
    primary.textContent = 'Скачать для Windows';
  }
};

choosePrimary();

fetch(manifestUrl, { cache: 'no-store' })
  .then((response) => {
    if (!response.ok) throw new Error(`Manifest HTTP ${response.status}`);
    return response.json();
  })
  .then((manifest) => {
    const version = manifest.version || manifest.windows?.version || manifest.android?.version;
    const versionNode = document.getElementById('release-version');
    if (versionNode) versionNode.textContent = version ? `Версия ${version}` : 'Актуальная версия';
    const notes = manifest.windows?.notes || manifest.android?.notes;
    const noteNode = document.getElementById('release-note');
    if (noteNode && notes) noteNode.textContent = notes;
    setMeta('windows-meta', 'windows', manifest);
    setMeta('android-meta', 'android', manifest);
  })
  .catch(() => {
    const versionNode = document.getElementById('release-version');
    if (versionNode) versionNode.textContent = 'Актуальная сборка';
    const windowsMeta = document.getElementById('windows-meta');
    const androidMeta = document.getElementById('android-meta');
    if (windowsMeta) windowsMeta.textContent = 'Windows 10/11 · x64';
    if (androidMeta) androidMeta.textContent = 'Android · APK';
  });
