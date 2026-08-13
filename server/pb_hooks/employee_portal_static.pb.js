/// Публичная страница портала WesiOS.
///
/// Статику портала отдаём штатным обработчиком PocketBase. Корень выбирается
/// один раз при загрузке hook. Основной production-каталог /srv проверяется
/// первым, затем явно настроенный WESI_ARTIFACTS_DIR и только после этого
/// legacy /opt.

const WESI_PORTAL_STATIC_ROOT = (() => {
  const configured = $os.getenv("WESI_ARTIFACTS_DIR");
  const roots = [
    "/srv/wesi-artifacts",
    configured,
    "/opt/pocketbase/pb_public/artifacts",
  ].filter((value, index, all) => value && all.indexOf(value) === index);

  for (const root of roots) {
    try {
      $os.dirFS(root + "/portal").readFile("index.html");
      console.log("WesiOS portal static root:", root + "/portal");
      return root + "/portal";
    } catch (_) {
      // Пробуем следующий известный production-каталог.
    }
  }

  return "/srv/wesi-artifacts/portal";
})();

/// Релизный workflow публикует updater-артефакты сюда. На живом сервере
/// встроенная раздача pb_public для /artifacts сейчас возвращает пустое тело,
/// хотя файл на диске существует и валиден. Поэтому регистрируем явный route
/// на тот же физический каталог: manifest/APK/ZIP теперь проходят через один
/// и тот же источник истины.
const WESI_RELEASE_STATIC_ROOT = "/opt/pocketbase/pb_public/artifacts";

/// Корневой адрес домена — тоже сайт, а не сырой ответ API.
///
/// `{$}` здесь обязателен: без него образец `/` совпадает не с корнем, а с
/// любым адресом, который не подобрал никто другой, — и уносит его на
/// портал. Именно это и происходило: `/wesios-status.json` отвечал 308 и
/// отдавал HTML портала, приложение не могло разобрать его как JSON и
/// показывало «Агент указан, но не отвечает по этому адресу». Агент при
/// этом мог работать исправно — до его файла просто нельзя было достучаться,
/// как и до любого другого файла в pb_public.
routerAdd("GET", "/{$}", (e) => e.redirect(308, "/portal/"));
routerAdd("GET", "/portal", (e) => e.redirect(308, "/portal/"));

/// Страница должна перепроверяться при каждом открытии, иначе браузер может
/// часами держать старую встроенную CSS/JS-разметку после выкладки.
routerAdd(
  "GET",
  "/portal/{path...}",
  $apis.static(WESI_PORTAL_STATIC_ROOT, true),
  (e) => {
    e.response.header().set("Cache-Control", "no-cache, must-revalidate");
    return e.next();
  },
);

/// Публичный канал обновлений WesiOS. Здесь нет секретов: только подписанный
/// APK, Windows ZIP и manifest с размером/sha256. Manifest не кешируем, чтобы
/// устройство увидело новый build сразу после атомарной публикации.
routerAdd(
  "GET",
  "/artifacts/{path...}",
  $apis.static(WESI_RELEASE_STATIC_ROOT, false),
  (e) => {
    e.response.header().set("Cache-Control", "no-cache, must-revalidate");
    return e.next();
  },
);
