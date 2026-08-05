/// Короткий красивый адрес портала.
///
/// Сами файлы лежат рядом с артефактами, куда уже умеет писать пользователь
/// GitHub Actions. PocketBase публикует их также по /portal/, поэтому nginx
/// и отдельный virtual host не нужны.

const WESI_PORTAL_STATIC_ROOT =
  ($os.getenv("WESI_ARTIFACTS_DIR") ||
    "/opt/pocketbase/pb_public/artifacts") + "/portal";

routerAdd("GET", "/portal", (e) => e.redirect(308, "/portal/"));
routerAdd(
  "GET",
  "/portal/{path...}",
  $apis.static(WESI_PORTAL_STATIC_ROOT, true),
);
