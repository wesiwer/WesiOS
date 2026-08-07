/// Портал WesiOS: статическая страница, надёжная выдача релизов и
/// информационный слой.
///
/// Релизный workflow и portal deploy исторически умеют работать в двух
/// каталогах. Поэтому ни страница, ни manifest больше не зависят от того,
/// была ли переменная WESI_ARTIFACTS_DIR задана именно процессу PocketBase.

const WESI_STORAGE_ROOTS = [
  $os.getenv("WESI_ARTIFACTS_DIR"),
  "/opt/pocketbase/pb_public/artifacts",
  "/srv/wesi-artifacts",
].filter((value, index, all) => value && all.indexOf(value) === index);

function wesiReadText(fs, name) {
  const raw = fs.readFile(name);
  if (typeof raw === "string") return raw;
  return String.fromCharCode.apply(null, raw);
}

function wesiPortalRoot() {
  let lastError = null;
  for (const root of WESI_STORAGE_ROOTS) {
    try {
      const fs = $os.dirFS(root + "/portal");
      const html = wesiReadText(fs, "index.html");
      if (html.indexOf("WesiOS") >= 0) return root + "/portal";
    } catch (error) {
      lastError = error;
    }
  }
  console.log("employee portal static lookup error:", lastError);
  throw new NotFoundError("Портал WesiOS ещё не опубликован");
}

function wesiRelease() {
  let lastError = null;
  for (const root of WESI_STORAGE_ROOTS) {
    try {
      const fs = $os.dirFS(root);
      const manifest = JSON.parse(wesiReadText(fs, "app/app-manifest.json"));
      if (!manifest || typeof manifest !== "object") continue;
      return {root: root, manifest: manifest};
    } catch (error) {
      lastError = error;
    }
  }
  console.log("employee portal release lookup error:", lastError);
  throw new NotFoundError("Актуальная сборка WesiOS ещё не опубликована");
}

function wesiSafeArtifactPath(value) {
  if (typeof value !== "string" || value === "") {
    throw new NotFoundError("Файл сборки не указан");
  }
  const clean = $filepath.clean(value).replace(/\\/g, "/");
  if (!clean.startsWith("app/") || clean.indexOf("../") >= 0 || clean.startsWith("/")) {
    throw new ForbiddenError("Недопустимый путь сборки");
  }
  return clean;
}

function wesiSafePortalPath(value) {
  const source = String(value || "index.html");
  const clean = $filepath.clean(source).replace(/\\/g, "/");
  if (clean === "." || clean === "") return "index.html";
  if (clean.startsWith("/") || clean.startsWith("../") || clean.indexOf("/../") >= 0) {
    throw new ForbiddenError("Недопустимый путь портала");
  }
  return clean;
}

function wesiArtifactName(value, fallback) {
  if (typeof value !== "string" || value === "") return fallback;
  return value.replace(/[^a-zA-Z0-9._-]/g, "_");
}

/// Manifest v2. Старый маршрут остаётся для совместимости старого app.js,
/// а этот всегда использует фактически найденный каталог релиза.
routerAdd("GET", "/api/wesi/portal/release-manifest", (e) => {
  const release = wesiRelease();
  const manifest = release.manifest;
  const result = {
    "version": manifest.version,
    "build": manifest.build,
    "publishedAt": manifest.publishedAt || null,
    "protected": true,
  };

  ["windows", "android"].forEach((platform) => {
    const source = manifest[platform];
    if (!source || typeof source !== "object") return;
    result[platform] = {
      "version": source.version || manifest.version,
      "build": source.build || manifest.build,
      "asset": source.asset,
      "sizeBytes": source.sizeBytes || null,
      "sha256": source.sha256 || null,
      "notes": source.notes || null,
      "download": "/api/wesi/portal/release-download/" + platform,
    };
  });

  e.response.header().set("Cache-Control", "private, no-store");
  return e.json(200, result);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/portal/release-download/{platform}", (e) => {
  const platform = e.request.pathValue("platform");
  if (platform !== "windows" && platform !== "android") {
    throw new NotFoundError("Неизвестная платформа");
  }

  const release = wesiRelease();
  const manifest = release.manifest;
  const entry = manifest[platform];
  if (!entry || typeof entry !== "object") {
    throw new NotFoundError("Сборка для платформы не опубликована");
  }

  const path = wesiSafeArtifactPath(entry.path);
  const fallback = platform === "windows"
    ? "wesios-windows-x64.zip"
    : "wesios-android.apk";
  const name = wesiArtifactName(entry.asset, fallback);

  e.response.header().set("Cache-Control", "private, no-store");
  e.response.header().set("Content-Disposition", "attachment; filename=\"" + name + "\"");
  e.response.header().set("Content-Type", platform === "windows"
    ? "application/zip"
    : "application/vnd.android.package-archive");
  e.response.header().set("X-Content-Type-Options", "nosniff");
  e.response.header().set("X-WesiOS-Version", String(entry.version || manifest.version || ""));
  e.response.header().set("X-WesiOS-Build", String(entry.build || manifest.build || ""));
  return e.fileFS($os.dirFS(release.root), path);
}, $apis.requireAuth("users"));

/// Вклеивается только в HTML главной страницы. Это позволяет исправить
/// скачивание даже у браузера, который держал старый app.js, и не требует
/// дублировать весь большой index.html в hook.
const WESI_PORTAL_ENHANCEMENT = `
<style id="wesiProductStyles">
.product-info{padding:92px 3vw 108px;border-top:1px solid rgba(var(--veil-rgb),.06)}
.product-info-head{max-width:850px}.product-info-head h2{margin:18px 0 16px;font-size:clamp(38px,5vw,64px);line-height:1;letter-spacing:-.05em}.product-info-head>p{max-width:760px;margin:0;color:var(--muted);font-size:15px;line-height:1.75}
.product-facts{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin-top:38px}.product-fact{padding:22px}.product-fact small,.req-cols small{color:var(--orange);font-size:9px;font-weight:850;letter-spacing:.16em}.product-fact strong{display:block;margin:10px 0 9px;font-size:18px}.product-fact p{margin:0;color:var(--muted);font-size:12px;line-height:1.65}
.requirements{margin-top:58px}.requirements-title{display:grid;grid-template-columns:1fr 1.2fr;gap:18px 38px;align-items:end}.requirements-title .section-label{grid-column:1/-1}.requirements-title h3{margin:0;font-size:clamp(28px,3.4vw,44px);letter-spacing:-.04em}.requirements-title>p{margin:0;color:var(--muted);font-size:12px;line-height:1.65}.requirements-grid{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-top:24px}.req-card{padding:22px}.req-platform{display:flex;align-items:center;justify-content:space-between;padding-bottom:16px;border-bottom:1px solid var(--soft)}.req-platform b{font-size:21px}.req-platform span{padding:6px 9px;border:1px solid var(--soft);border-radius:9px;color:var(--t1);font-size:10px;font-weight:800}.req-cols{display:grid;grid-template-columns:1fr 1fr;gap:18px;margin-top:18px}.req-cols .recommended{padding-left:18px;border-left:1px solid var(--soft)}.req-cols dl{display:grid;grid-template-columns:auto 1fr;gap:8px 10px;margin:14px 0 0}.req-cols dt{color:var(--t3);font-size:10px}.req-cols dd{margin:0;color:var(--t1);font-size:11px;text-align:right}.requirements-proof{margin:14px 0 0;color:var(--t3);font-size:10px;line-height:1.6}.requirements-proof code{color:var(--t1);font-family:ui-monospace,SFMono-Regular,Consolas,monospace}.download-button[data-progress]:after{content:attr(data-progress);margin-left:8px;font-variant-numeric:tabular-nums;opacity:.75}
@media(max-width:800px){.product-info{padding:68px 0 82px}.product-facts,.requirements-grid{grid-template-columns:1fr}.requirements-title{grid-template-columns:1fr}.requirements-title .section-label{grid-column:auto}.req-cols{grid-template-columns:1fr}.req-cols .recommended{padding:18px 0 0;border-left:0;border-top:1px solid var(--soft)}}
@media(max-width:480px){.req-card,.product-fact{padding:18px}.req-cols dl{grid-template-columns:1fr}.req-cols dd{text-align:left;margin-bottom:4px}}
</style>
<script id="wesiProductRuntime">
(function(){
  'use strict';
  var TOKEN_KEY='wesi_portal_token';
  function token(){try{return sessionStorage.getItem(TOKEN_KEY)||'';}catch(_){return '';}}
  function authHeaders(){var t=token();return t?{Authorization:t}:{};}
  function size(value){var bytes=Number(value);if(!bytes)return '—';var mb=bytes/1048576;return mb>=1024?(mb/1024).toFixed(1)+' ГБ':mb.toFixed(mb>=10?0:1)+' МБ';}
  function date(value){var d=new Date(value);if(Number.isNaN(d.getTime()))return 'Дата не указана';return new Intl.DateTimeFormat('ru-RU',{day:'2-digit',month:'long',year:'numeric',hour:'2-digit',minute:'2-digit'}).format(d);}
  function toast(text,type){var stack=document.getElementById('toastStack');if(!stack)return;var n=document.createElement('div');n.className='toast '+(type||'');n.textContent=text;stack.appendChild(n);setTimeout(function(){n.remove();},4400);}
  function label(button,text){var span=button&&button.querySelector('span');if(span)span.textContent=text;}

  function addProductInfo(){
    if(document.getElementById('productInfo'))return;
    var showcase=document.getElementById('showcase');
    if(!showcase||!showcase.parentNode)return;
    var section=document.createElement('section');
    section.className='product-info';section.id='productInfo';
    section.innerHTML='<div class="product-info-head"><span class="section-label">О WESIOS</span><h2>Рабочая система компании,<br>а не ещё один набор сервисов.</h2><p>WesiOS объединяет финансы, задачи, календарь, рабочие чаты, аналитику, базу знаний, CRM, Roadmap и Wesi AI. Данные хранятся локально и синхронизируются между авторизованными устройствами через корпоративный сервер.</p></div>'+
      '<div class="product-facts"><article class="product-fact surface"><small>ПЛАТФОРМЫ</small><strong>Windows + Android</strong><p>Windows поставляется как портативная x64-сборка. Android — подписанный корпоративный APK.</p></article><article class="product-fact surface"><small>СИНХРОНИЗАЦИЯ</small><strong>Между устройствами</strong><p>Изменения отправляются автоматически; второе устройство получает обновления без перезапуска приложения.</p></article><article class="product-fact surface"><small>РЕЖИМ РАБОТЫ</small><strong>Offline-first</strong><p>Основные данные остаются доступны локально. Сервер нужен для входа, обмена между устройствами и корпоративных функций.</p></article></div>'+
      '<div class="requirements"><div class="requirements-title"><span class="section-label">СИСТЕМНЫЕ ТРЕБОВАНИЯ</span><h3>Минимальные и рекомендуемые</h3><p>ОС и архитектура взяты из текущих сборок WesiOS. RAM и место на диске — практический эксплуатационный минимум; приложение не ставит искусственного программного запрета по объёму памяти.</p></div><div class="requirements-grid">'+
      '<article class="req-card surface"><div class="req-platform"><b>Windows</b><span>x64</span></div><div class="req-cols"><div><small>МИНИМАЛЬНО</small><dl><dt>ОС</dt><dd>Windows 10, 64-bit</dd><dt>Процессор</dt><dd>x86-64</dd><dt>ОЗУ</dt><dd>4 ГБ</dd><dt>Диск</dt><dd>500 МБ свободно</dd><dt>Сеть</dt><dd>Для входа и синхронизации</dd></dl></div><div class="recommended"><small>РЕКОМЕНДУЕТСЯ</small><dl><dt>ОС</dt><dd>Windows 11, 64-bit</dd><dt>Процессор</dt><dd>4 ядра x86-64</dd><dt>ОЗУ</dt><dd>8 ГБ+</dd><dt>Диск</dt><dd>1 ГБ+ на SSD</dd><dt>Экран</dt><dd>1366×768+</dd></dl></div></div></article>'+
      '<article class="req-card surface"><div class="req-platform"><b>Android</b><span>API 21+</span></div><div class="req-cols"><div><small>МИНИМАЛЬНО</small><dl><dt>ОС</dt><dd>Android 5.0 (API 21)</dd><dt>Архитектура</dt><dd>ARMv7 / ARM64 / x86-64</dd><dt>ОЗУ</dt><dd>2 ГБ</dd><dt>Диск</dt><dd>300 МБ свободно</dd><dt>Сеть</dt><dd>Для входа и синхронизации</dd></dl></div><div class="recommended"><small>РЕКОМЕНДУЕТСЯ</small><dl><dt>ОС</dt><dd>Android 10+</dd><dt>Архитектура</dt><dd>ARM64</dd><dt>ОЗУ</dt><dd>4 ГБ+</dd><dt>Диск</dt><dd>500 МБ+</dd><dt>Экран</dt><dd>720p+</dd></dl></div></div></article></div><p class="requirements-proof">Жёсткие ограничения сборки: Android <code>minSdkVersion 21</code>; Windows-релиз публикуется как <code>x64</code>. Для Windows Flutter поддерживает Windows 10 и 11.</p></div>';
    showcase.parentNode.insertBefore(section,showcase);
    var hint=document.querySelector('.scroll-hint');if(hint)hint.setAttribute('href','#productInfo');
  }

  var manifestPromise=null;
  async function getManifest(force){
    if(!token())throw new Error('Сначала войдите в WesiOS');
    if(force||!manifestPromise){manifestPromise=fetch('/api/wesi/portal/release-manifest',{cache:'no-store',headers:authHeaders()}).then(async function(r){var b=null;try{b=await r.json();}catch(_){}if(!r.ok)throw new Error((b&&b.message)||'Не удалось получить релиз');return b;}).catch(function(e){manifestPromise=null;throw e;});}
    return manifestPromise;
  }

  async function hydrate(){
    if(!token())return;
    try{
      var m=await getManifest(true);var w=m.windows||null;var a=m.android||null;var version=m.version||(w&&w.version)||(a&&a.version)||'—';var build=m.build!=null?m.build:((w&&w.build)||(a&&a.build)||'—');
      var set=function(id,v){var n=document.getElementById(id);if(n)n.textContent=v;};
      set('heroVersion','v'+version);set('heroBuild','build '+build);set('releaseVersion','v'+version);set('releaseBuild',String(build));set('publishedAt',date(m.publishedAt));set('windowsSize',size(w&&w.sizeBytes));set('androidSize',size(a&&a.sizeBytes));
      var notes=(w&&w.notes)||(a&&a.notes)||m.notes||'Актуальная корпоративная сборка WesiOS.';var ch=document.querySelector('#changelog p');if(ch)ch.textContent=notes;
      document.querySelectorAll('[data-download]').forEach(function(b){b.disabled=!m[b.dataset.download];});set('footerStatus','Релиз v'+version+' доступен');
    }catch(e){var f=document.getElementById('footerStatus');if(f)f.textContent=e.message||'Список сборок пока недоступен';}
  }

  async function download(platform,button){
    var original=button.querySelector('span')?button.querySelector('span').textContent:'';var writable=null;
    try{
      if(platform==='windows'&&window.showSaveFilePicker){try{var handle=await window.showSaveFilePicker({suggestedName:'wesios-windows-x64.zip',types:[{description:'WesiOS Windows',accept:{'application/zip':['.zip']}}]});writable=await handle.createWritable();}catch(e){if(e&&e.name==='AbortError')return;writable=null;}}
      var m=await getManifest(false);var item=m&&m[platform];if(!item)throw new Error('Сборка для этой платформы не опубликована');var name=item.asset||(platform==='windows'?'wesios-windows-x64.zip':'wesios-android.apk');
      button.disabled=true;label(button,'Скачиваем');button.dataset.progress='';
      var response=await fetch('/api/wesi/portal/release-download/'+platform,{method:'GET',cache:'no-store',headers:authHeaders()});if(!response.ok){var body=null;try{body=await response.json();}catch(_){}throw new Error((body&&body.message)||('Ошибка скачивания: HTTP '+response.status));}
      var total=Number(response.headers.get('content-length')||item.sizeBytes||0),received=0;
      function progress(){if(total)button.dataset.progress=Math.min(100,Math.round(received*100/total))+'%';}
      if(writable&&response.body){var reader=response.body.getReader();try{while(true){var part=await reader.read();if(part.done)break;received+=part.value.byteLength;await writable.write(part.value);progress();}await writable.close();writable=null;toast('WesiOS сохранён на компьютер');return;}catch(e){try{await writable.abort();}catch(_){}writable=null;throw e;}}
      var blob=await response.blob();var url=URL.createObjectURL(blob);var a=document.createElement('a');a.href=url;a.download=name;a.style.display='none';document.body.appendChild(a);a.click();a.remove();setTimeout(function(){URL.revokeObjectURL(url);},60000);toast('Скачивание началось');
    }catch(e){toast((e&&e.message)||'Не удалось скачать сборку','error');}
    finally{if(writable){try{await writable.abort();}catch(_){}}delete button.dataset.progress;button.disabled=false;label(button,original||('Скачать для '+(platform==='windows'?'Windows':'Android')));}
  }

  document.addEventListener('click',function(event){var button=event.target&&event.target.closest?event.target.closest('[data-download]'):null;if(!button)return;event.preventDefault();event.stopImmediatePropagation();download(button.dataset.download,button);},true);
  addProductInfo();
  var dashboard=document.getElementById('dashboardView');if(dashboard){new MutationObserver(function(){if(dashboard.classList.contains('active'))hydrate();}).observe(dashboard,{attributes:true,attributeFilter:['class']});if(dashboard.classList.contains('active'))hydrate();}
})();
</script>`;

routerAdd("GET", "/portal", (e) => e.redirect(308, "/portal/"));

/// Один wildcard обслуживает и главную, и ресурсы. Это намеренно: два
/// пересекающихся ServeMux pattern (`/portal/` и `/portal/{path...}`) могут
/// конфликтовать. Для index.html добавляем enhancement, прочее отдаём как файл.
routerAdd("GET", "/portal/{path...}", (e) => {
  const root = wesiPortalRoot();
  const requested = e.request.pathValue("path");
  const path = wesiSafePortalPath(requested);
  e.response.header().set("Cache-Control", "no-cache, must-revalidate");

  if (path === "index.html") {
    const fs = $os.dirFS(root);
    let html = wesiReadText(fs, "index.html");
    if (html.indexOf("wesiProductRuntime") < 0) {
      html = html.replace("</body>", WESI_PORTAL_ENHANCEMENT + "\n</body>");
    }
    e.response.header().set("Content-Type", "text/html; charset=utf-8");
    return e.string(200, html);
  }

  return e.fileFS($os.dirFS(root), path);
});
