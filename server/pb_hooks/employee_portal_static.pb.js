/// Публичная страница портала WesiOS.
///
/// Статику отдаём штатным обработчиком PocketBase. Предыдущая версия
/// перехватывала /portal/{path...} собственным JS-кодом, читала файлы и
/// собирала HTML во время запроса. Runtime-ошибка такого hook превращала
/// весь портал в JSON 400 до того, как браузер получал хоть один байт HTML.
/// Для статической страницы это лишний и опасный слой.

const WESI_PORTAL_STATIC_ROOT =
  ($os.getenv("WESI_ARTIFACTS_DIR") ||
    "/opt/pocketbase/pb_public/artifacts") + "/portal";

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
