from pathlib import Path
import re


def read(path):
    return Path(path).read_text(encoding='utf-8')


def write(path, text):
    Path(path).write_text(text, encoding='utf-8')


def replace_once(path, old, new):
    text = read(path)
    if old not in text:
        raise SystemExit(f'anchor not found in {path}: {old[:100]!r}')
    write(path, text.replace(old, new, 1))


# ---------------------------------------------------------------- portal HTML
index = 'server/employee-portal/index.html'
text = read(index)
text = text.replace('./styles.css?v=13', './styles.css?v=14')
text = text.replace('./portal-v6.css?v=13', './portal-v6.css?v=14')

marker = '<section class="product-info" id="productInfo">'
if marker not in text:
    anchor = '      <section class="showcase" id="showcase">'
    if anchor not in text:
        raise SystemExit('showcase anchor not found')
    product = r'''      <section class="product-info" id="productInfo">
        <div class="product-info-head" data-scroll-reveal>
          <span class="section-label">О WESIOS</span>
          <h2>Рабочая система компании,<br>а не ещё один набор сервисов.</h2>
          <p>WesiOS объединяет финансы, задачи, календарь, рабочие чаты, аналитику, базу знаний, CRM, Roadmap и Wesi AI. Данные хранятся локально и синхронизируются между авторизованными устройствами через корпоративный сервер.</p>
        </div>

        <div class="product-facts" data-scroll-reveal>
          <article class="product-fact surface"><small>ПЛАТФОРМЫ</small><strong>Windows + Android</strong><p>Windows поставляется как портативная x64-сборка. Android — подписанный корпоративный APK.</p></article>
          <article class="product-fact surface"><small>СИНХРОНИЗАЦИЯ</small><strong>Между устройствами</strong><p>Изменения отправляются автоматически; второе устройство получает обновления без перезапуска приложения.</p></article>
          <article class="product-fact surface"><small>РЕЖИМ РАБОТЫ</small><strong>Offline-first</strong><p>Основные данные остаются доступны локально. Сервер нужен для входа, обмена между устройствами и корпоративных функций.</p></article>
        </div>

        <div class="requirements" data-scroll-reveal>
          <div class="requirements-title"><span class="section-label">СИСТЕМНЫЕ ТРЕБОВАНИЯ</span><h3>Минимальные и рекомендуемые</h3><p>Жёсткие ограничения ОС и архитектуры взяты из текущих сборок WesiOS. RAM и свободное место указаны как практический эксплуатационный минимум, а не как искусственный блокировщик запуска.</p></div>
          <div class="requirements-grid">
            <article class="requirement-card surface">
              <div class="requirement-platform"><b>Windows</b><span>x64</span></div>
              <div class="requirement-columns">
                <div><small>МИНИМАЛЬНО</small><dl><dt>ОС</dt><dd>Windows 10, 64-bit</dd><dt>Процессор</dt><dd>x86-64</dd><dt>ОЗУ</dt><dd>4 ГБ</dd><dt>Диск</dt><dd>500 МБ свободно</dd><dt>Сеть</dt><dd>Интернет для входа и синхронизации</dd></dl></div>
                <div class="recommended"><small>РЕКОМЕНДУЕТСЯ</small><dl><dt>ОС</dt><dd>Windows 11, 64-bit</dd><dt>Процессор</dt><dd>4 ядра x86-64</dd><dt>ОЗУ</dt><dd>8 ГБ+</dd><dt>Диск</dt><dd>1 ГБ+ на SSD</dd><dt>Экран</dt><dd>1366×768 или выше</dd></dl></div>
              </div>
            </article>
            <article class="requirement-card surface">
              <div class="requirement-platform"><b>Android</b><span>API 21+</span></div>
              <div class="requirement-columns">
                <div><small>МИНИМАЛЬНО</small><dl><dt>ОС</dt><dd>Android 5.0 (API 21)</dd><dt>Архитектура</dt><dd>ARMv7 / ARM64 / x86-64</dd><dt>ОЗУ</dt><dd>2 ГБ</dd><dt>Диск</dt><dd>300 МБ свободно</dd><dt>Сеть</dt><dd>Интернет для входа и синхронизации</dd></dl></div>
                <div class="recommended"><small>РЕКОМЕНДУЕТСЯ</small><dl><dt>ОС</dt><dd>Android 10 или новее</dd><dt>Архитектура</dt><dd>ARM64</dd><dt>ОЗУ</dt><dd>4 ГБ+</dd><dt>Диск</dt><dd>500 МБ+ свободно</dd><dt>Экран</dt><dd>720p или выше</dd></dl></div>
              </div>
            </article>
          </div>
          <p class="requirements-proof">Фактические ограничения сборки: Android <code>minSdkVersion 21</code>; Windows-релиз собирается и публикуется как <code>x64</code>. WesiOS не вводит отдельного программного запрета по объёму RAM.</p>
        </div>
      </section>

'''
    text = text.replace(anchor, product + anchor, 1)
write(index, text)


# -------------------------------------------------------------------- styles
styles = 'server/employee-portal/styles.css'
css = read(styles)
if '/* WESIOS_PRODUCT_INFO_V1 */' not in css:
    css += r'''

/* WESIOS_PRODUCT_INFO_V1 */
.product-info{padding:92px 3vw 108px;border-top:1px solid rgba(var(--veil-rgb),.06)}
.product-info-head{max-width:850px}.product-info-head h2{margin:18px 0 16px;font-size:clamp(38px,5vw,64px);line-height:1;letter-spacing:-.05em}.product-info-head>p{max-width:760px;margin:0;color:var(--muted);font-size:15px;line-height:1.75}
.product-facts{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin-top:38px}.product-fact{padding:22px}.product-fact small,.requirement-columns small{color:var(--orange);font-size:9px;font-weight:850;letter-spacing:.16em}.product-fact strong{display:block;margin:10px 0 9px;font-size:18px}.product-fact p{margin:0;color:var(--muted);font-size:12px;line-height:1.65}
.requirements{margin-top:58px}.requirements-title{display:grid;grid-template-columns:1fr 1.2fr;gap:18px 38px;align-items:end}.requirements-title .section-label{grid-column:1/-1}.requirements-title h3{margin:0;font-size:clamp(28px,3.4vw,44px);letter-spacing:-.04em}.requirements-title>p{margin:0;color:var(--muted);font-size:12px;line-height:1.65}.requirements-grid{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-top:24px}.requirement-card{padding:22px}.requirement-platform{display:flex;align-items:center;justify-content:space-between;padding-bottom:16px;border-bottom:1px solid var(--soft)}.requirement-platform b{font-size:21px}.requirement-platform span{padding:6px 9px;border:1px solid var(--soft);border-radius:9px;color:var(--t1);font-size:10px;font-weight:800}.requirement-columns{display:grid;grid-template-columns:1fr 1fr;gap:18px;margin-top:18px}.requirement-columns>div{min-width:0}.requirement-columns .recommended{padding-left:18px;border-left:1px solid var(--soft)}.requirement-columns dl{display:grid;grid-template-columns:auto 1fr;gap:8px 10px;margin:14px 0 0}.requirement-columns dt{color:var(--t3);font-size:10px}.requirement-columns dd{margin:0;color:var(--t1);font-size:11px;text-align:right}.requirements-proof{margin:14px 0 0;color:var(--t3);font-size:10px;line-height:1.6}.requirements-proof code{color:var(--t1);font-family:ui-monospace,SFMono-Regular,Consolas,monospace}
.download-button[data-progress]:after{content:attr(data-progress);margin-left:8px;font-variant-numeric:tabular-nums;opacity:.75}
@media(max-width:800px){.product-info{padding:68px 0 82px}.product-facts,.requirements-grid{grid-template-columns:1fr}.requirements-title{grid-template-columns:1fr}.requirements-title .section-label{grid-column:auto}.requirement-columns{grid-template-columns:1fr}.requirement-columns .recommended{padding:18px 0 0;border-left:0;border-top:1px solid var(--soft)}}
@media(max-width:480px){.requirement-card,.product-fact{padding:18px}.requirement-columns dl{grid-template-columns:1fr}.requirement-columns dd{text-align:left;margin-bottom:4px}}
'''
write(styles, css)


# ------------------------------------------------------------- download JS
app = 'server/employee-portal/app.js'
js = read(app)
pattern = re.compile(r"  async function download\(platformName, button\) \{.*?\n  \}\n\n  function toast", re.S)
match = pattern.search(js)
if not match:
    raise SystemExit('download function not found')
new_download = r'''  async function download(platformName, button) {
    const item = platform(state.manifest, platformName);
    if (!item || !button) return;

    const fallbackName = platformName === 'windows'
      ? 'wesios-windows-x64.zip'
      : 'wesios-android.apk';
    const fileName = item.asset || fallbackName;
    let writable = null;

    try {
      // На desktop сначала открываем системный диалог сохранения, пока клик
      // пользователя ещё считается активным. Потом поток пишется сразу в
      // файл: большой Windows ZIP не копируется целиком в память браузера.
      if (platformName === 'windows' && 'showSaveFilePicker' in window) {
        const handle = await window.showSaveFilePicker({
          suggestedName: fileName,
          types: [{ description: 'WesiOS Windows', accept: { 'application/zip': ['.zip'] } }],
        });
        writable = await handle.createWritable();
      }

      setLoading(button, true, 'Скачиваем');
      button.dataset.progress = '';

      // Предыдущая версия обрывала запрос через 30 секунд. Для большой
      // сборки это превращало нормальный медленный интернет в «скачивание не
      // работает». Здесь намеренно нет клиентского таймаута.
      const response = await fetch(`${API}/api/wesi/portal/download/${platformName}`, {
        method: 'GET',
        headers: headers(),
        cache: 'no-store',
      });
      if (!response.ok) {
        let body = null;
        try { body = await response.json(); } catch (_) {}
        throw new Error(describeFailure(response.status, body?.message));
      }

      const total = Number(response.headers.get('content-length') || item.sizeBytes || 0);
      let received = 0;
      const showProgress = () => {
        if (!total) return;
        const percent = Math.min(100, Math.round(received * 100 / total));
        button.dataset.progress = `${percent}%`;
      };

      if (writable && response.body) {
        const reader = response.body.getReader();
        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            received += value.byteLength;
            await writable.write(value);
            showProgress();
          }
          await writable.close();
          writable = null;
          button.dataset.progress = '100%';
          toast('WesiOS сохранён на компьютер');
          return;
        } catch (error) {
          try { await writable.abort(); } catch (_) {}
          writable = null;
          throw error;
        }
      }

      // Android и браузеры без File System Access API: стандартный fallback.
      // Таймаута здесь тоже нет; URL освобождается после старта скачивания.
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = fileName;
      anchor.style.display = 'none';
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      setTimeout(() => URL.revokeObjectURL(url), 60000);
      toast('Скачивание началось');
    } catch (error) {
      if (error?.name === 'AbortError') return; // пользователь закрыл Save As
      toast(error?.message || 'Не удалось скачать сборку', 'error');
    } finally {
      if (writable) {
        try { await writable.abort(); } catch (_) {}
      }
      delete button.dataset.progress;
      setLoading(button, false);
    }
  }

  function toast'''
js = pattern.sub(new_download, js, count=1)
write(app, js)


# ---------------------------------------------------------- artifact lookup
hook = 'server/pb_hooks/employee_portal.pb.js'
h = read(hook)
old = '''const PORTAL_ARTIFACTS_ROOT = $os.getenv("WESI_ARTIFACTS_DIR") ||
  "/opt/pocketbase/pb_public/artifacts";
'''
new = '''const PORTAL_ARTIFACTS_ROOTS = [
  $os.getenv("WESI_ARTIFACTS_DIR"),
  "/opt/pocketbase/pb_public/artifacts",
  "/srv/wesi-artifacts",
].filter((value, index, all) => value && all.indexOf(value) === index);
'''
if old not in h:
    raise SystemExit('artifact root constant anchor not found')
h = h.replace(old, new, 1)

old_manifest = re.compile(r'''function portalManifest\(\) \{.*?\n\}\n\nfunction portalSafePath''', re.S)
m = old_manifest.search(h)
if not m:
    raise SystemExit('portalManifest block not found')
manifest_block = r'''function portalRelease() {
  let lastError = null;
  for (const root of PORTAL_ARTIFACTS_ROOTS) {
    try {
      const fs = $os.dirFS(root);
      const manifest = JSON.parse(portalReadText(fs, "app/app-manifest.json"));
      return {root: root, manifest: manifest};
    } catch (error) {
      lastError = error;
    }
  }
  console.log("employee portal manifest error:", lastError);
  throw new NotFoundError("Актуальная сборка WesiOS ещё не опубликована");
}

function portalManifest() {
  return portalRelease().manifest;
}

function portalSafePath'''
h = old_manifest.sub(manifest_block, h, count=1)

old_dl = '''  const manifest = portalManifest();
  const entry = manifest[platform];
'''
new_dl = '''  const release = portalRelease();
  const manifest = release.manifest;
  const entry = manifest[platform];
'''
# Only replace the download-route occurrence: last occurrence in file.
pos = h.rfind(old_dl)
if pos < 0:
    raise SystemExit('download manifest anchor not found')
h = h[:pos] + new_dl + h[pos+len(old_dl):]
h = h.replace('  return e.fileFS($os.dirFS(PORTAL_ARTIFACTS_ROOT), path);',
              '  e.response.header().set("Content-Type", platform === "windows" ? "application/zip" : "application/vnd.android.package-archive");\n  e.response.header().set("X-Content-Type-Options", "nosniff");\n  return e.fileFS($os.dirFS(release.root), path);', 1)
write(hook, h)


# --------------------------------------------------------------- deploy CI
wf = '.github/workflows/deploy-employee-portal.yml'
y = read(wf)
if "grep -q 'productInfo' server/employee-portal/index.html" not in y:
    anchor = "          grep -q 'siteBoot' server/employee-portal/index.html\n"
    addition = anchor + "          grep -q 'productInfo' server/employee-portal/index.html\n          grep -q 'СИСТЕМНЫЕ ТРЕБОВАНИЯ' server/employee-portal/index.html\n          grep -q 'showSaveFilePicker' server/employee-portal/app.js\n          grep -q 'PORTAL_ARTIFACTS_ROOTS' server/pb_hooks/employee_portal.pb.js\n"
    if anchor not in y:
        raise SystemExit('workflow validation anchor not found')
    y = y.replace(anchor, addition, 1)

    prod_anchor = "          grep -q 'siteBoot' portal.html\n"
    prod_add = prod_anchor + "          grep -q 'productInfo' portal.html\n          grep -q 'СИСТЕМНЫЕ ТРЕБОВАНИЯ' portal.html\n"
    if prod_anchor not in y:
        raise SystemExit('workflow production anchor not found')
    y = y.replace(prod_anchor, prod_add, 1)
write(wf, y)

print('portal patch applied')
