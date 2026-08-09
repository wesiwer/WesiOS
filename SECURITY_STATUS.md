# WesiOS — статус защищённого входа

Актуально на 2026-08-09. Этот файл — обязательный контекст для AI и разработчиков перед изменениями авторизации, портала, сотрудников, почты или релизов.

## Текущий релиз

- Версия приложения: **0.19.13+61**.
- `pubspec.yaml`, `lib/core/constants/app_version.dart` и README синхронизированы.
- Канонический production workflow: `.github/workflows/publish-wesios-production.yml` (`Publish WesiOS Production`).
- Подписанные Android/Windows assets публикуются через низкоуровневый `release-app.yml`, после чего канонический workflow выкладывает ровно опубликованные файлы в PocketBase `pb_public/artifacts` и публично перепроверяет их.
- Production run **`31293093499`** полностью **SUCCESS**: signed release builder **`31293098729`**, GitHub `app-latest`, PocketBase deployment, public Windows/Android artifact verification и Windows installer run **`31293453932`**.
- Windows fresh-install installer собирается отдельным `.github/workflows/publish-windows-installer.yml`; канонический production workflow ждёт его полного success, включая silent install/uninstall, GitHub `app-latest`, PocketBase upload и public verification.
- Windows ZIP **сохраняется** как канал встроенного автообновления `AppUpdateService`; `.exe` — канал первой установки. Не переключать `app-manifest.json` на installer без изменения updater.

## Защищённый вход — реализовано

### Сотрудники

- Электронная почта обязательна при создании и редактировании сотрудника.
- Адрес нормализуется и проверяется на дубликат.
- Реальная почта хранится в `EmployeeModel` и server-side `portal-account` snapshot.
- PocketBase auth-record использует внутренний адрес `<login>@wesi.local`; он не является адресом доставки OTP.
- При изменении сотрудника владелец передаёт актуальный реальный email на server-side access endpoint.

### Вход в приложение

1. Логин + пароль.
2. Сервер проверяет пароль, но не выдаёт рабочую WesiOS-сессию.
3. На реальную security email профиля отправляется 6-значный OTP.
4. Только правильный OTP создаёт revocable WesiOS session.
5. Код действует 10 минут, одноразовый, максимум 5 неверных попыток.
6. Прямой PocketBase password auth `/api/collections/users/auth-with-password` заблокирован server hook.

`Запомнить меня` применяется только после успешной 2FA. Если флаг выключен, persistent remembered session не остаётся после закрытия процесса.

### Хранение remembered session

- PocketBase auth token и WesiOS `sessionId` не хранятся plaintext в Hive.
- Persistent remembered session хранится через `flutter_secure_storage` (`wesios_server_session_v2`).
- Legacy `sync_session` из Hive мигрируется и удаляется.
- Plaintext fallback запрещён: при недоступном secure storage сессия может жить только в текущем процессе.

### Employee portal

Портал использует тот же сценарий: login/password → email OTP → подтверждённая server session → manifest/download.

Для старого owner-профиля без security email предусмотрена только миграция с подтверждением адреса. Фиксированный owner recovery login/password/hash **удалён**. Скрытого break-glass входа нет.

### Одноразовое восстановление владельца 2026-08-09

Для восстановления уже существующего owner-сеанса при недоступной почтовой доставке подготовлена одна краткоживущая операция:

- временные пароль и шестизначный код передаются владельцу вне GitHub;
- в репозитории и deployment workflow находится только salted SHA-256 высокоэнтропийного временного пароля;
- recovery привязан к конкретному owner `userId`, повторно использует только один созданный challenge и не может выпустить второй после его использования;
- activation workflow подставляет срок жизни на 45 минут только в развёртываемую копию hook;
- после начала входа OTP challenge живёт не более 10 минут и подчиняется штатному `/api/wesi/auth/verify`;
- исходники Flutter уже не содержат фиксированных recovery-данных и отдельной recovery-кнопки;
- после подтверждения owner-сеанса production bootstrap должен быть немедленно заменён чистой версией из `main`, а одноразовый workflow удалён.

Эта операция не является постоянным способом входа и не заменяет завершение SMTP/DNS-настройки.

### Активные сеансы и revoke

- Server session имеет случайный ID и device/platform/IP/timezone/user-agent/createdAt/lastSeenAt/expiresAt.
- В профиле можно видеть и отзывать активные сеансы.
- Heartbeat проверяет валидность server session; server-side revoke приводит к глобальному выходу.
- Удаление сотрудника удаляет auth account и отзывает его sessions/pending OTP.

## Реальные данные вместо demo/random

- Новые сотрудники получают `demoStats: const {}`.
- `generateDemoStats()` оставлен только как deprecated compatibility API и возвращает пустой map.
- Экран показателей считает реальные assigned/done/open/overdue/completion.
- Случайность допустима только для безопасных технических значений: соли, OTP/session ID, временных паролей и свободных логинов.

## Android icon и Windows installer

- Android launcher использует актуальный WesiOS resource во всех density buckets.
- Windows release содержит WesiOS icon.
- Fresh install: `wesios-windows-x64-setup.exe`, Inno Setup, per-user install в `%LOCALAPPDATA%\Programs\WesiOS`, Start Menu shortcut, optional Desktop shortcut, uninstall support.
- Installer workflow на чистом Windows runner выполняет silent install, проверяет `wesios.exe`, затем silent uninstall; только после этого публикует `.exe`.
- Public installer для **0.19.13+61** проверен каноническим production run `31293093499` и installer run `31293453932`.
- Auto-update остаётся ZIP-механизмом: `AppUpdateService` скачивает ZIP, проверяет SHA-256, делает `Expand-Archive` и атомарную замену файлов после выхода приложения.

## Production portal и artifacts

- PocketBase production root: `/opt/pocketbase`.
- Публичные артефакты: `/opt/pocketbase/pb_public/artifacts` → `https://api.wesi-inc.ru/artifacts/...`.
- `server/deploy-artifact.sh` приведён к фактическому формату release: принимает Windows ZIP (и installer, если он используется отдельно), Android APK, пишет SHA-256/size manifest и чистит старые версии.
- `Publish WesiOS Production` — единственная рекомендуемая точка production-выпуска. Legacy server-deploy ветку `release-app.yml` с `/srv/wesi-artifacts` не использовать вручную.

## Единственный незакрытый production-блокер авторизации: DNS для self-hosted email

### Что уже подтверждено на production VPS

- Postfix: **active**.
- OpenDKIM: **active**.
- PocketBase: **active**.
- `/usr/sbin/sendmail` существует.
- `myhostname=mail.wesi-inc.ru`.
- Postfix слушает loopback и использует OpenDKIM milter `127.0.0.1:8891`.
- Relayhost пустой: планируется прямая доставка к MX получателя.
- Исходящий **TCP/25 OPEN** — ограничение хостера снято и проверено непосредственно с VPS соединением к Gmail MX.
- PTR для production IPv4 уже указывает на `mail.wesi-inc.ru`.
- Mail queue на последней проверке пустая.

### Что пока отсутствует в публичном DNS

Nameservers домена: Aéza DNS (`a.aeza-dns.net`, `b.aeza-dns.net`). На последней production-проверке отсутствовали:

- `A mail.wesi-inc.ru`;
- SPF TXT для `wesi-inc.ru`;
- DKIM TXT `wesios._domainkey.wesi-inc.ru`;
- DMARC TXT `_dmarc.wesi-inc.ru`.

Из-за этого реальная отправка OTP пока намеренно **не активирована**, а `/api/wesi/auth/mail-ready` возвращает `503 transport_not_configured`.

Deploy SSH user не имеет root/passwordless sudo и не может прочитать `/etc/opendkim/keys/wesi-inc.ru/wesios.txt`. Это правильная граница прав; private DKIM key обходить нельзя. Для получения публичного TXT требуется одно root-действие на VPS: прочитать именно `wesios.txt`, не `.private`.

### Подготовленная безопасная активация

`.github/workflows/activate-wesios-local-mail.yml` (`Activate WesiOS Local Mail`) уже готов, но **не запускается автоматически**.

Он fail-closed и сначала проверяет:

1. `mail.wesi-inc.ru` A совпадает с текущим public IPv4 VPS;
2. PTR совпадает с `mail.wesi-inc.ru`;
3. SPF разрешает этот IPv4;
4. DKIM TXT существует и `opendkim-testkey` проходит;
5. DMARC существует;
6. Postfix/OpenDKIM active;
7. outbound TCP/25 открыт.

Только если все проверки зелёные, workflow кратковременно устанавливает server-side SMTP settings PocketBase на локальный Postfix:

- host `127.0.0.1`;
- port `25`;
- TLS/credentials не требуются для локального trusted hop;
- sender `WesiOS <security@wesi-inc.ru>`;
- localName `mail.wesi-inc.ru`.

Затем временный конфигурационный hook сразу восстанавливается, и workflow требует `200 ready=true smtpReady=true` от `/api/wesi/auth/mail-ready`.

`wesi_auth_bootstrap.pb.js` уже умеет использовать `app.newMailClient()` при включённом PocketBase SMTP, поэтому отдельный sendmail transport в auth hook не нужен.

### Что осталось для полной production-активации OTP

1. Получить публичное значение DKIM из `/etc/opendkim/keys/wesi-inc.ru/wesios.txt` под root.
2. Опубликовать A/SPF/DKIM/DMARC в Aéza DNS.
3. Дождаться, пока публичные DNS queries возвращают новые записи.
4. Запустить `Activate WesiOS Local Mail`.
5. Получить `200` от `/api/wesi/auth/mail-ready` с `smtpReady=true`.
6. Выполнить реальный end-to-end тест: password → письмо → OTP → session → app/portal access → remote revoke.
7. Только после этого считать email OTP production-ready.

HTTPS/Resend fallback в серверном hook может оставаться как резервная архитектура, но **текущий основной production-путь — собственный Postfix/OpenDKIM**. Не требовать сторонний mail provider, если self-hosted transport проходит все проверки.

## Запрещённые откаты

- Не возвращать прямой `/api/collections/users/auth-with-password` в клиент или портал.
- Не выдавать доступ после одного пароля без OTP.
- Не возвращать фиксированный owner recovery login/password/hash или скрытую recovery-кнопку.
- Не хранить auth token/session ID plaintext в Hive.
- Не хранить mail/API/private DKIM secrets в Flutter, portal JS, git или публичных workflow logs.
- Не ослаблять обязательность email из-за неготового DNS.
- Не активировать локальный SMTP до A/PTR/SPF/DKIM/DMARC и `opendkim-testkey`.
- Не возвращать случайные/demo бизнес-данные.
- Не считать отсутствие `sessionId` валидной авторизацией.
- Не обходить server-side revoke локальной owner/session логикой.
- Не менять Windows update manifest с ZIP на `.exe` без одновременного изменения `AppUpdateService`.
