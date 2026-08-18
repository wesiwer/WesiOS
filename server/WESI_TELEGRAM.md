# Wesi Telegram — production contour

`telegram-webhook/` в корне репозитория — исторический Vercel-прототип. Он
не является финальной архитектурой и не должен развиваться как отдельная
база/CRM.

Production Gateway живёт в основном Wesi server contour:

- `pb_hooks/wesi_telegram.pb.js` — HTTP routes, Telegram webhook, команды,
  callback-кнопки и cron notifier;
- `pb_hooks/wesi_telegram_store.js` — link codes, identity link, revoke,
  active org и notification preferences;
- `pb_hooks/wesi_telegram_lib.js` — чистые правила парсинга, callback,
  rate-limit, quiet hours и форматирования;
- `wesi_ai_finance_tools.js`, `wesi_ai_horizon_tools.js`,
  `wesi_ai_task_tools.js` — общий Tool Layer. Бот не считает отдельную
  «правду» о деньгах или задачах.

## Identity

Связка хранится как server record:

`telegram_user_id -> auth_user_id -> current portal account / employee`

В link record намеренно нет копии прав, которой можно доверять в будущем.
Каждая команда и каждая callback-кнопка заново разрешает текущий Wesi auth
identity и текущие organization grants. Удаление/деактивация сотрудника или
revoke Telegram link прекращает доступ без ожидания истечения Telegram
сессии.

Код привязки:

- генерируется криптографически;
- в RID хранится только SHA-256 кода;
- TTL — 10 минут;
- одноразовый;
- выдаётся только уже аутентифицированному WesiOS client с действующим
  `X-WesiOS-Session`.

## Main routes

Authenticated WesiOS client:

- `POST /api/wesi/telegram/link/create`
- `GET /api/wesi/telegram/status`
- `POST /api/wesi/telegram/revoke`
- `POST /api/wesi/telegram/context`
- `POST /api/wesi/telegram/preferences`

Telegram:

- `POST /api/wesi/telegram/webhook`
- `GET /api/wesi/telegram/open?...` — whitelist redirect обратно в WesiOS

## MVP commands

- `/brief`
- `/cash`
- `/risk`
- `/today`
- `/overdue`
- `/org`

В личке поддерживается базовый естественный язык (`сколько денег`,
`кассовый риск`, `просрочки`, `задачи сегодня`). Неизвестный NL intent пока
не отправляется в LLM: Wesi AI Telegram chat — отдельный этап v1.2.

Группы в MVP не получают финансовые цифры или тела задач. Чувствительные
команды перенаправляются в личный чат.

## Risk semantics

`/risk` вызывает общий `horizon_snapshot`. Этот server snapshot даёт
фактический ledger balance, 90-day spend rate и runway (`cushionDays`). Он
не воспроизводит полный клиентский Monte-Carlo Horizon, поэтому Telegram
**не придумывает процент вероятности разрыва**. До появления server-side
полного Horizon бот показывает честный runway level:

- `< 14 дней` — critical;
- `< 30 дней` — warning;
- `>= 30 дней` — moderate;
- нет расходного темпа — unknown.

## Proactive notifier

PocketBase cron `wesios_telegram_alerts_v1` запускается каждые 5 минут.
MVP categories:

- cash/runway risk;
- overdue tasks.

Preferences живут per-link. Quiet hours по умолчанию `23:00–08:00` с
timezone offset устройства, которое создало link. Delivery fingerprints
не дают одному и тому же состоянию отправляться на каждом cron tick.

## Secrets

Ни bot token, ни webhook secret не коммитятся.

На production server Gateway читает `/opt/pocketbase/pb_hooks/.wesi-telegram.json`:

```json
{
  "botToken": "...",
  "webhookSecret": "...",
  "botUsername": "WesiOSBot",
  "publicBaseUrl": "https://api.wesi-inc.ru"
}
```

Файл создаёт workflow `.github/workflows/deploy-wesi-telegram.yml` из GitHub
Actions secrets и ставит mode `0600`.

Предпочтительный secret:

- `WESI_TELEGRAM_BOT_TOKEN`

Для совместимости workflow также понимает старое имя:

- `TELEGRAM_BOT_TOKEN`

Опционально можно задать независимый `WESI_TELEGRAM_WEBHOOK_SECRET`. Если
его нет, deploy workflow детерминированно производит webhook secret из bot
token; это не заменяет защиту bot token и не попадает в репозиторий.

## Deployment

`Deploy Wesi Telegram`:

1. syntax-check серверных JS files;
2. запускает `wesi_telegram_lib_test.mjs`;
3. атомарно ставит shared tools, Telegram helpers/config и только затем
   route hook;
4. ждёт PocketBase hot reload и проверяет `/api/health`;
5. вызывает Telegram `setWebhook` с secret token и allowed updates
   `message`, `callback_query`;
6. проверяет `getWebhookInfo`;
7. убеждается, что webhook без secret отвечает `401`, а deep-link route
   существует.

## Acceptance MVP

Production нельзя считать закрытым только по CI. Нужен реальный E2E:

1. owner: Profile -> Telegram -> connect;
2. `/brief` совпадает с server records выбранной org;
3. `/cash`, `/risk`, `/today`, `/overdue` работают;
4. `/org` переключает только разрешённые org;
5. revoke из приложения сразу блокирует следующую Telegram команду;
6. employee с ограниченными grants не видит finance другой org;
7. warning/critical risk и overdue notifier приходят один раз на изменение,
   а не каждые 5 минут;
8. группа не получает чувствительные цифры.
