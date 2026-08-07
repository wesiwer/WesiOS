/// Публичная страница портала WesiOS.
///
/// Статику отдаём штатным обработчиком PocketBase. Корень выбирается один
/// раз при загрузке hook: сначала явно настроенный WESI_ARTIFACTS_DIR, затем
/// фактическое production-хранилище /srv, затем legacy /opt. Это исключает
/// ситуацию, когда deploy пишет новую страницу в /srv, а PocketBase продолжает
/// раздавать старую копию из /opt.

const WESI_PORTAL_STATIC_ROOT = (() => {
  const configured = $os.getenv("WESI_ARTIFACTS_DIR");
  const roots = [
    configured,
    "/srv/wesi-artifacts",
    "/opt/pocketbase/pb_public/artifacts",
  ].filter((value, index, all) => value && all.indexOf(value) === index);

  for (const root of roots) {
    try {
      // Читаем только для проверки существования. HTML не преобразуется в
      // строку и не обрабатывается в runtime-запросе — поэтому большой
      // встроенный bundle не может уронить /portal/.
      $os.dirFS(root + "/portal").readFile("index.html");
      console.log("WesiOS portal static root:", root + "/portal");
      return root + "/portal";
    } catch (_) {
      // Пробуем следующий известный production-каталог.
    }
  }

  // Если портал ещё не опубликован, оставляем стандартный путь: $apis.static
  // вернёт обычный 404 вместо падения hook при загрузке.
  return (configured || "/opt/pocketbase/pb_public/artifacts") + "/portal";
})();

/// Корневой адрес домена — тоже сайт, а не сырой ответ API.
routerAdd("GET", "/", (e) => e.redirect(308, "/portal/"));
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
