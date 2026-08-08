# WesiOS — статус защищённого входа

Актуально на 2026-08-08. Этот файл — обязательный контекст для AI и разработчиков перед изменениями авторизации, портала, сотрудников или релизов.

## Текущий релиз

- Версия: **0.19.8+56**.
- `pubspec.yaml`, `lib/core/constants/app_version.dart` и README синхронизированы.
- GitHub Actions run **31247762231** (`Build signed WesiOS release`) завершён полностью **SUCCESS**.
- Android: launcher icon регенерирован из актуального WesiOS mark; APK подписан постоянным корпоративным keystore; package/signature/certificate проверены CI.
- Windows: Flutter release собран; WesiOS icon регенерирован; NSIS `wesios-windows-x64-setup.exe` собран успешно.
- Publish: Android APK и Windows Setup проверены по SHA-256, опубликованы атомарно на production, production manifest перепроверен скачиванием файлов, GitHub Release `app-latest` обновлён.

## Защищённый вход — реализовано

### Сотрудники

- Электронная почта обязательна при создании и редактировании сотрудника.
- Адрес нормализуется и проверяется на дубликат.
- Реальная почта хранится в `EmployeeModel` и в server-side `portal-account` snapshot.
- PocketBase auth-record сотрудника использует внутренний адрес `<login>@wesi.local`; этот технический адрес не является адресом доставки OTP.
- При изменении сотрудника владелец отправляет обновлённый реальный email на `/api/wesi/portal/employees/access`, поэтому OTP использует актуальный адрес из server-side snapshot.

### Вход в приложение

1. Логин + пароль.
2. Сервер проверяет пароль, но **не выдаёт рабочую WesiOS-сессию**.
3. На реальную почту профиля отправляется 6-значный одноразовый код.
4. Только правильный код создаёт revocable WesiOS session и открывает профиль.
5. Код действует 10 минут, одноразовый, максимум 5 неверных попыток.
6. Прямой PocketBase password auth `/api/collections/users/auth-with-password` заблокирован server hook.

`Запомнить меня` применяется только после успешной 2FA. Если флаг выключен, при следующем запуске серверная сессия отзывается и локальная авторизация очищается.

### Хранение remembered session

- PocketBase auth token и WesiOS `sessionId` больше **не хранятся plaintext в Hive**.
- Persistent remembered session хранится через `flutter_secure_storage` (`wesios_server_session_v2`).
- Legacy `sync_session` из Hive мигрируется один раз и сразу удаляется.
- Plaintext fallback запрещён: если platform secure storage недоступен, подтверждённая сессия может жить только до закрытия процесса; после перезапуска требуется новый вход.
- `test/sync_endpoint_secure_storage_test.dart` фиксирует инвариант: token/sessionId не должны появляться в обычном Hive settings.

### Вход на employee portal

Портал использует тот же двухэтапный сценарий: login/password → email OTP → подтверждённая server session → доступ к manifest/download. Скачать WesiOS без подтверждённой session нельзя.

Для старого owner-профиля без security email предусмотрена одноразовая миграция: адрес становится security email только после проверки кода, отправленного на этот адрес.

Фиксированный owner recovery login/password/hash **удалён**. Скрытого break-glass входа нет: владелец проходит обычный пароль + email OTP.

### Активные сеансы

- Server-side session имеет собственный случайный ID и хранит device/platform/IP/timezone/user-agent/createdAt/lastSeenAt/expiresAt.
- В профиле можно посмотреть активные сеансы, устройство, платформу, IP, страну/часовой пояс (если доступны), время входа и последнюю активность.
- Чужой сеанс того же аккаунта можно завершить удалённо.
- Текущий сеанс можно завершить — приложение очищает локальные данные авторизации и возвращается на `/login`.
- Heartbeat приложения проверяет session примерно раз в 2 секунды; server-side revoke приводит к глобальному выходу даже из уже открытого экрана.

### Удаление сотрудника

Удаление сотрудника владельцем удаляет его server auth account. `onRecordAfterDeleteSuccess(..., "users")` отзывает все server sessions и pending OTP challenges. После ближайшего heartbeat открытое приложение сотрудника получает отказ, очищает локальную авторизацию и возвращается на экран входа. Повторный вход невозможен, потому что auth account и `portal-account` link закрыты.

## Реальные данные вместо demo/random

- Новые сотрудники получают `demoStats: const {}`.
- `generateDemoStats()` оставлен только как deprecated compatibility API и всегда возвращает пустой map.
- Экран показателей считает только реальные задачи: assigned/done/open/overdue/completion.
- Если задач нет, показывается «данных пока нет»; случайные бизнес-показатели не создаются.
- Случайность остаётся только там, где она нужна технически: безопасная соль, временный пароль, OTP/session ID и выбор свободного логина.

## Иконка и Windows installer

- `AndroidManifest.xml` и launcher aliases используют **`@mipmap/launcher_icon`**.
- Release CI перед каждой Android сборкой запускает `flutter_launcher_icons` и проверяет `launcher_icon.png` во всех density buckets.
- Windows release CI тоже регенерирует `windows/runner/resources/app_icon.ico`.
- Windows теперь распространяется как полноценный **`wesios-windows-x64-setup.exe`**, а не ZIP.
- NSIS installer использует WesiOS icon; проблема относительного пути к `.ico` закрыта fallback-путём относительно `windows/installer`.
- Portal download route отдаёт `.exe` и MIME `application/vnd.microsoft.portable-executable`.

## Production portal

- Deploy run **31248036587**: validation, SSH, upload и `Upload and publish portal` завершены SUCCESS.
- На production подтверждена установка hooks:
  - `employee_portal.pb.js`
  - `employee_portal_static.pb.js`
  - `wesi_security.pb.js`
  - `wesi_auth_bootstrap.pb.js`
  - `wesi_mail_health.pb.js`
- Портал опубликован в `/opt/pocketbase/pb_public/artifacts/portal`, production HTML содержит OTP UI и новые markers, Cache-Control отключает stale cache.
- Сам job завершился failure **только** на mail-readiness: `/api/wesi/auth/mail-ready` вернул HTTP 503.

## Единственный незакрытый production-блокер: реальная доставка email

Клиентская 2FA, server hooks и production portal уже готовы. Но на production пока нет credentials реального почтового транспорта, поэтому вход намеренно остаётся fail-closed.

Проверено ранее:

- PocketBase sender address настроен.
- SMTP в PocketBase выключен.
- Исходящие SMTP-порты 25/465/587 были недоступны.
- Исходящий HTTPS доступен.
- На момент последней проверки `WESI_RESEND_API_KEY` и/или `WESI_MAIL_FROM` в GitHub Environment `employee-portal` отсутствовали: mail-config workflow пропустил install/verify steps.

### Подготовленный основной путь: HTTPS / Resend

- `wesi_auth_bootstrap.pb.js` сначала использует реально настроенный SMTP, а при его отсутствии/ошибке — server-only HTTPS provider config.
- Resend вызывается сервером через `$http.send(POST https://api.resend.com/emails)`.
- API key **не хранится в git, Flutter или portal JS**.
- Private config читается только из `/opt/pocketbase/pb_hooks/.wesi-mail.json`.
- `.github/workflows/configure-wesi-mail.yml` — ручной workflow, который требует secrets `WESI_RESEND_API_KEY` и `WESI_MAIL_FROM`, устанавливает private config с mode `0600` владельцу процесса PocketBase и затем проверяет `/api/wesi/auth/mail-ready`.
- `wesi_mail_health.pb.js` возвращает `ready=true` только если реально готов SMTP или валидный HTTPS provider config.
- `Deploy employee portal` также принимает только `smtpReady=true` либо `httpsProviderConfigured=true`; отсутствие транспорта остаётся ошибкой.

### Запасной self-hosted вариант

`server/setup-wesios-mail-server.sh` может настроить Postfix + OpenDKIM, но он **не запускается автоматически** и не считается текущим решением. Для прямой доставки обязательны открытый outbound TCP/25, DNS A/SPF/DKIM/DMARC и корректный PTR. Пока TCP/25 не подтверждён повторной диагностикой и реальной доставкой, основной путь — HTTPS provider.

### Что осталось сделать для полной production-активации OTP

1. Создать/подтвердить sender/domain у Resend (или эквивалентного HTTPS mail provider).
2. Добавить в GitHub Environment `employee-portal` secrets `WESI_RESEND_API_KEY` и `WESI_MAIL_FROM`.
3. Запустить `Configure WesiOS HTTPS mail transport`.
4. Получить `200` от `/api/wesi/auth/mail-ready` с `httpsProviderConfigured=true`.
5. Выполнить реальный end-to-end тест на внешний ящик: password → письмо → OTP → session → download/app access → remote revoke.
6. После этого повторный `Deploy employee portal` должен быть полностью зелёным.

## Запрещённые откаты

- Не возвращать прямой `/api/collections/users/auth-with-password` в клиент или портал.
- Не выдавать доступ после одного пароля без OTP.
- Не возвращать фиксированный owner recovery login/password/hash.
- Не хранить auth token/session ID plaintext в Hive.
- Не хранить mail/API secrets в Flutter, portal JS, git или публичных workflow logs.
- Не ослаблять обязательность email из-за отсутствия mail provider.
- Не возвращать случайные/demo бизнес-данные.
- Не считать отсутствие `sessionId` валидной авторизацией.
- Не обходить server-side revoke локальной owner/session логикой.
- Не переключать production обратно на sendmail-only без повторной проверки TCP/25, DNS/PTR и реальной доставки.
