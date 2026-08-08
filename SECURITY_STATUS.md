# WesiOS — статус защищённого входа

Актуально на 2026-08-08. Этот файл — обязательный контекст для AI и разработчиков перед изменениями авторизации, портала, сотрудников или релизов.

## Текущий релиз

- Версия: **0.19.6+54**.
- `pubspec.yaml` и `lib/core/constants/app_version.dart` синхронизированы.
- GitHub Actions run `31245859377` (`Build signed WesiOS release`) завершён успешно.
- Windows release собран и опубликован.
- Android APK собран с постоянным корпоративным keystore; package/signature/certificate проверены CI и опубликованы.
- Production manifest/files и GitHub Release assets обновлены успешно.

## Защищённый вход — реализовано

### Сотрудники

- Электронная почта обязательна при создании и редактировании сотрудника.
- Адрес нормализуется и проверяется на дубликат.
- Реальная почта хранится в `EmployeeModel` и в server-side `portal-account` snapshot.
- PocketBase auth-record сотрудника использует внутренний адрес `<login>@wesi.local`; этот технический адрес не является адресом доставки OTP.
- При изменении сотрудника владелец отправляет обновлённый реальный email на `/api/wesi/portal/employees/access`, поэтому OTP использует актуальный адрес из server-side snapshot.

### Вход в приложение

1. Логин + пароль.
2. Сервер проверяет пароль, но **не выдаёт рабочую сессию**.
3. На реальную почту профиля должен быть отправлен 6-значный одноразовый код.
4. Только правильный код создаёт revocable WesiOS session и открывает профиль.
5. Код действует 10 минут, одноразовый, максимум 5 неверных попыток.
6. Прямой PocketBase password auth заблокирован server hook.

`Запомнить меня` применяется только после успешной 2FA. Если флаг выключен, при следующем запуске серверная сессия отзывается и локальная авторизация очищается.

### Вход на employee portal

Портал использует тот же двухэтапный сценарий: login/password → email OTP → подтверждённая server session → доступ к manifest/download. Скачать WesiOS без подтверждённой session нельзя.

Для старого owner-профиля без security email предусмотрена одноразовая миграция: адрес становится security email только после проверки кода, отправленного на этот адрес.

### Активные сеансы

- Server-side session имеет собственный случайный ID и хранит device/platform/IP/timezone/user-agent/createdAt/lastSeenAt/expiresAt.
- В профиле можно посмотреть активные сеансы.
- Чужой сеанс того же аккаунта можно завершить удалённо.
- Текущий сеанс можно завершить — приложение очищает локальные данные авторизации и возвращается на `/login`.
- Heartbeat приложения проверяет session примерно раз в 2 секунды; server-side revoke приводит к глобальному выходу даже из уже открытого экрана.

### Удаление сотрудника

Удаление сотрудника владельцем сначала удаляет его server auth account. `onRecordAfterDeleteSuccess(..., "users")` отзывает все его server sessions и pending OTP challenges. После ближайшего heartbeat открытое приложение сотрудника получает отказ, очищает локальную авторизацию и возвращается на экран входа. Повторный вход невозможен, потому что auth account и `portal-account` link закрыты.

## Реальные данные вместо demo/random

- Новые сотрудники получают `demoStats: const {}`.
- `generateDemoStats()` оставлен только как deprecated compatibility API и всегда возвращает пустой map.
- Экран показателей считает только реальные задачи: assigned/done/open/overdue/completion.
- Если задач нет, показывается «данных пока нет»; случайные бизнес-показатели не создаются.
- Случайность остаётся только там, где она нужна технически: безопасная соль, временный пароль, session ID и выбор свободного логина.

## Android launcher icon

- `AndroidManifest.xml` и оба activity-alias используют `@mipmap/ic_launcher` и `roundIcon`.
- PNG launcher resources присутствуют для density buckets, поэтому старые Android/launcher больше не зависят от API-26-only adaptive icon.
- Release CI проверяет итоговый подписанный APK.

## Единственный незакрытый production-блокер: доставка email

Код 2FA и hooks **уже опубликованы на production**, но реальная доставка письма сейчас не может работать.

Проверено production deployment/diagnostics:

- PocketBase sender address настроен.
- SMTP в PocketBase выключен.
- На сервере нет `sendmail`, Postfix, msmtp или Exim.
- Исходящие SMTP-порты 25/465/587 недоступны по проведённой диагностике.
- Исходящий HTTPS доступен.
- В GitHub Environment на момент проверки не было настроено известных SMTP/API mail secrets (`WESI_SMTP_*`, Resend, SendGrid, Brevo, Postmark, Mailgun и т.п.).

Поэтому portal deploy намеренно считается неготовым на шаге mail readiness. Это **fail-closed поведение**, а не повод отключать OTP.

### Что нужно для окончательного включения почты

Предпочтительный вариант в текущей сети — HTTPS mail API (например Resend/SendGrid/Brevo/Postmark), потому что HTTPS доступен, а SMTP-порты закрыты. Нужны реальные credentials провайдера и подтверждённый sender/domain. Альтернатива — рабочий SMTP relay, если сетевой доступ к нему будет разрешён.

После появления credentials необходимо:

1. Хранить ключ только в server environment / GitHub Environment Secret, не в репозитории и не в клиентском приложении.
2. Подключить отправку в server hook; PocketBase JSVM поддерживает `$http.send(...)` для HTTPS API.
3. Проверить реальную доставку тестового 6-значного кода на внешний почтовый ящик.
4. Добиться успешного `/api/wesi/auth/mail-ready` и зелёного `Deploy employee portal`.
5. Проверить полный сценарий app + portal: password → письмо → OTP → session → remote revoke.

## Запрещённые откаты

- Не возвращать прямой `/api/collections/users/auth-with-password` в клиент или портал.
- Не выдавать доступ после одного пароля без OTP.
- Не хранить mail/API secrets в Flutter, JS portal, git или публичных workflow logs.
- Не ослаблять обязательность email из-за отсутствия mail provider.
- Не возвращать случайные/demo бизнес-данные.
- Не считать отсутствие `sessionId` валидной авторизацией.
- Не обходить server-side revoke локальной owner/session логикой.
