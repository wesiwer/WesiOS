from pathlib import Path

root = Path('server/employee-portal')
index_path = root / 'index.html'
css_path = root / 'portal-v6.css'
js_path = root / 'app.js'

html = index_path.read_text(encoding='utf-8')
css = css_path.read_text(encoding='utf-8')
js = js_path.read_text(encoding='utf-8')

old_hint = '''          <a class="scroll-hint" href="#showcase"><span>Листайте дальше</span><i aria-hidden="true"></i></a>'''
new_hint = '''          <button class="scroll-hint requirements-trigger" id="requirementsTrigger" type="button" aria-expanded="false" aria-controls="requirementsPopover">
            <span>Системные требования</span><i aria-hidden="true"></i>
          </button>
          <div class="requirements-popover" id="requirementsPopover" aria-hidden="true">
            <div class="requirements-title">
              <span class="section-label">СИСТЕМНЫЕ ТРЕБОВАНИЯ</span>
              <h3>Минимальные и рекомендуемые</h3>
              <p>Показываем только подтверждённые ограничения. WesiOS не задаёт жёсткий минимум ОЗУ, частоты CPU или фиксированного объёма диска, поэтому таких выдуманных цифр здесь нет.</p>
            </div>
            <div class="requirements-grid">
              <article class="req-card surface">
                <div class="req-platform"><b>Windows</b><span>x64</span></div>
                <div class="req-cols">
                  <div><small>МИНИМАЛЬНО</small><dl>
                    <dt>ОС</dt><dd>Windows 10, 64-bit</dd>
                    <dt>Архитектура</dt><dd>x64</dd>
                    <dt>ОЗУ</dt><dd>Порог WesiOS не задан</dd>
                    <dt>Диск</dt><dd>Сборка + локальные данные</dd>
                    <dt>Сеть</dt><dd>Для входа и синхронизации</dd>
                  </dl></div>
                  <div class="recommended"><small>РЕКОМЕНДУЕТСЯ</small><dl>
                    <dt>ОС</dt><dd>Windows 11, 64-bit</dd>
                    <dt>Накопитель</dt><dd>SSD</dd>
                    <dt>Сеть</dt><dd>Стабильное подключение</dd>
                    <dt>ОЗУ / CPU</dt><dd>Без искусственного порога</dd>
                  </dl></div>
                </div>
              </article>
              <article class="req-card surface">
                <div class="req-platform"><b>Android</b><span>API 21+</span></div>
                <div class="req-cols">
                  <div><small>МИНИМАЛЬНО</small><dl>
                    <dt>ОС</dt><dd>Android 5.0 (API 21)</dd>
                    <dt>ОЗУ</dt><dd>Порог WesiOS не задан</dd>
                    <dt>Диск</dt><dd>APK + локальные данные</dd>
                    <dt>Сеть</dt><dd>Для входа и синхронизации</dd>
                  </dl></div>
                  <div class="recommended"><small>РЕКОМЕНДУЕТСЯ</small><dl>
                    <dt>ОС</dt><dd>Android 10 или новее</dd>
                    <dt>Архитектура</dt><dd>ARM64</dd>
                    <dt>Обновления</dt><dd>Актуальные системные патчи</dd>
                    <dt>Сеть</dt><dd>Стабильное подключение</dd>
                  </dl></div>
                </div>
              </article>
            </div>
            <p class="requirements-proof">Android minimum подтверждён <code>minSdkVersion 21</code>. Windows release собирается как <code>x64</code>. Рекомендованные параметры справа не являются блокировкой запуска.</p>
          </div>'''
if 'id="requirementsTrigger"' not in html:
    if old_hint not in html:
        raise SystemExit('scroll hint anchor not found')
    html = html.replace(old_hint, new_hint, 1)

showcase_anchor = '''      <section class="showcase" id="showcase">'''
product = '''      <section class="product-info" id="productInfo">
        <div class="product-info-head" data-scroll-reveal>
          <span class="section-label">О WESIOS</span>
          <h2>Рабочая система компании,<br>а не ещё один набор сервисов.</h2>
          <p>WesiOS объединяет финансы, задачи, календарь, рабочие чаты, аналитику, базу знаний, CRM, Roadmap и Wesi AI. Данные работают offline-first, а авторизованные устройства синхронизируются через корпоративный сервер.</p>
        </div>
        <div class="product-facts" data-scroll-reveal>
          <article class="product-fact surface"><small>ПЛАТФОРМЫ</small><strong>Windows + Android</strong><p>Windows — x64-сборка. Android — подписанный корпоративный APK.</p></article>
          <article class="product-fact surface"><small>СИНХРОНИЗАЦИЯ</small><strong>Между устройствами</strong><p>Изменения отправляются автоматически и появляются на другом активном устройстве без перезапуска.</p></article>
          <article class="product-fact surface"><small>РЕЖИМ</small><strong>Offline-first</strong><p>Основные рабочие данные остаются локально. Интернет нужен для входа, межустройственного обмена и сетевых функций.</p></article>
        </div>
      </section>

'''
if 'id="productInfo"' not in html:
    if showcase_anchor not in html:
        raise SystemExit('showcase anchor not found')
    html = html.replace(showcase_anchor, product + showcase_anchor, 1)

css_marker = '/* WESIOS_STATIC_PRODUCT_INFO_V1 */'
if css_marker not in css:
    css += r'''

/* WESIOS_STATIC_PRODUCT_INFO_V1 */
.product-info{padding:92px 3vw 108px;border-top:1px solid rgba(var(--veil-rgb),.06)}
.product-info-head{max-width:850px}.product-info-head h2{margin:18px 0 16px;font-size:clamp(38px,5vw,64px);line-height:1;letter-spacing:-.05em}.product-info-head>p{max-width:780px;margin:0;color:var(--muted);font-size:15px;line-height:1.75}
.product-facts{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin-top:38px}.product-fact{padding:22px}.product-fact small,.req-cols small{color:var(--orange);font-size:9px;font-weight:850;letter-spacing:.16em}.product-fact strong{display:block;margin:10px 0 9px;font-size:18px}.product-fact p{margin:0;color:var(--muted);font-size:12px;line-height:1.65}
.hero-extras{position:relative}.requirements-trigger{appearance:none;background:transparent;border:0;color:inherit;font:inherit;cursor:pointer;user-select:none}.requirements-trigger i{transition:transform .24s var(--ease)}.requirements-trigger[aria-expanded="true"] i{transform:rotate(180deg)}
.requirements-popover{position:absolute;z-index:40;right:0;bottom:58px;width:min(860px,calc(100vw - 42px));max-height:min(72vh,650px);padding:22px;border:1px solid var(--line);border-radius:22px;background:linear-gradient(155deg,var(--panel-u),var(--sunken));box-shadow:0 30px 90px rgba(var(--shadow-rgb),.62),inset 0 1px rgba(var(--veil-rgb),.04);overflow:auto;overscroll-behavior:contain;opacity:0;visibility:hidden;pointer-events:none;transform:translateY(12px) scale(.985);transform-origin:100% 100%;transition:opacity .2s var(--ease),transform .2s var(--ease),visibility .2s}
.requirements-popover.is-open{opacity:1;visibility:visible;pointer-events:auto;transform:translateY(0) scale(1)}
.requirements-title{display:grid;grid-template-columns:1fr 1.2fr;gap:18px 38px;align-items:end}.requirements-title .section-label{grid-column:1/-1}.requirements-title h3{margin:0;font-size:clamp(24px,3vw,36px);letter-spacing:-.04em}.requirements-title>p{margin:0;color:var(--muted);font-size:12px;line-height:1.65}
.requirements-grid{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-top:20px}.req-card{padding:22px}.req-platform{display:flex;align-items:center;justify-content:space-between;padding-bottom:16px;border-bottom:1px solid var(--soft)}.req-platform b{font-size:21px}.req-platform span{padding:6px 9px;border:1px solid var(--soft);border-radius:9px;color:var(--t1);font-size:10px;font-weight:800}.req-cols{display:grid;grid-template-columns:1fr 1fr;gap:18px;margin-top:18px}.req-cols .recommended{padding-left:18px;border-left:1px solid var(--soft)}.req-cols dl{display:grid;grid-template-columns:auto 1fr;gap:8px 10px;margin:14px 0 0}.req-cols dt{color:var(--t3);font-size:10px}.req-cols dd{margin:0;color:var(--t1);font-size:11px;text-align:right}.requirements-proof{margin:14px 0 0;color:var(--t3);font-size:10px;line-height:1.65}.requirements-proof code{color:var(--t1);font-family:ui-monospace,SFMono-Regular,Consolas,monospace}
.download-button[data-progress]:after{content:attr(data-progress);margin-left:8px;font-variant-numeric:tabular-nums;opacity:.75}
@media(max-width:800px){.product-info{padding:68px 0 82px}.product-facts,.requirements-grid{grid-template-columns:1fr}.requirements-title{grid-template-columns:1fr}.requirements-title .section-label{grid-column:auto}.req-cols{grid-template-columns:1fr}.req-cols .recommended{padding:18px 0 0;border-left:0;border-top:1px solid var(--soft)}}
@media(max-width:480px){.req-card,.product-fact{padding:18px}.req-cols dl{grid-template-columns:1fr}.req-cols dd{text-align:left;margin-bottom:4px}.requirements-popover{position:fixed;left:12px;right:12px;bottom:max(18px,env(safe-area-inset-bottom));width:auto;max-height:78vh;padding:18px;transform-origin:50% 100%}.requirements-title>p{font-size:11px}}
'''

old_download = '''  async function download(platformName, button) {
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
'''
new_download = '''  async function download(platformName, button) {
    const item = platform(state.manifest, platformName);
    if (!item) return;
    const fallback = platformName === 'windows' ? 'wesios-windows-x64.zip' : 'wesios-android.apk';
    const name = item.asset || fallback;
    let writable = null;
    setLoading(button, true, 'Скачиваем…');
    try {
      // Для большого Windows ZIP Chromium может сразу писать поток на диск.
      // Это не держит весь архив в памяти и не ограничивает загрузку 30 секундами.
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
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
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
'''
if 'showSaveFilePicker' not in js:
    if old_download not in js:
        raise SystemExit('download function anchor not found')
    js = js.replace(old_download, new_download, 1)

bind_anchor = '''  function bind() {
    preventPinchZoom();'''
bind_replacement = '''  function bindRequirements() {
    const trigger = $('#requirementsTrigger');
    const popover = $('#requirementsPopover');
    if (!trigger || !popover) return;
    const setOpen = open => {
      trigger.setAttribute('aria-expanded', open ? 'true' : 'false');
      popover.setAttribute('aria-hidden', open ? 'false' : 'true');
      popover.classList.toggle('is-open', open);
    };
    const toggle = event => {
      event?.preventDefault();
      event?.stopPropagation();
      setOpen(trigger.getAttribute('aria-expanded') !== 'true');
    };
    trigger.addEventListener('click', toggle);
    trigger.addEventListener('keydown', event => {
      if (event.key === 'Enter' || event.key === ' ') toggle(event);
      if (event.key === 'Escape') setOpen(false);
    });
    popover.addEventListener('click', event => event.stopPropagation());
    document.addEventListener('click', () => setOpen(false));
    document.addEventListener('keydown', event => { if (event.key === 'Escape') setOpen(false); });
  }

  function bind() {
    bindRequirements();
    preventPinchZoom();'''
if 'function bindRequirements()' not in js:
    if bind_anchor not in js:
        raise SystemExit('bind anchor not found')
    js = js.replace(bind_anchor, bind_replacement, 1)

index_path.write_text(html, encoding='utf-8')
css_path.write_text(css, encoding='utf-8')
js_path.write_text(js, encoding='utf-8')
print('static portal content repaired')
