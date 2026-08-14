# Wesi AI Relay

Зарубежный multi-provider посредник между основным сервером WesiOS и AI API.

```text
WesiOS → Main Wesi Server → Foreign Relay → Gemini / OpenAI / Claude / Grok
```

Provider credentials живут **только на Foreign Relay**. Flutter-клиент и Main Server никогда не получают API keys.

## Поддерживаемые провайдеры

- Google Gemini — `GEMINI_API_KEY`;
- OpenAI / ChatGPT — `OPENAI_API_KEY`;
- Anthropic / Claude — `ANTHROPIC_API_KEY`;
- xAI / Grok — `XAI_API_KEY`.

Текстовые API:

- Google: Gemini `generateContent`;
- OpenAI: Responses API `/v1/responses`;
- Anthropic: Messages API `/v1/messages`;
- xAI: Responses API `/v1/responses`.

Relay также умеет получать актуальный каталог моделей непосредственно у каждого провайдера. Protected Main endpoint: `GET /api/wesi/ai/models`.

## GitHub Secrets

Обязательные для deployment:

| Secret | Назначение |
|---|---|
| `WESI_RELAY_SSH_USER` | SSH-пользователь зарубежного VPS |
| `WESI_RELAY_SSH_KEY` | приватный SSH-ключ Relay VPS |
| `GEMINI_API_KEY` | Gemini + media/TTS credential |
| `WESI_SERVER_HOST` | Main Wesi Server |
| `WESI_SERVER_USER` | Main SSH user |
| `WESI_SERVER_SSH_KEY` | Main SSH key |

Опциональные provider keys:

| Secret | Назначение |
|---|---|
| `OPENAI_API_KEY` | ChatGPT/OpenAI models |
| `ANTHROPIC_API_KEY` | Claude models |
| `XAI_API_KEY` | Grok models |

Опциональная инфраструктура:

- `WESI_RELAY_SSH_HOST`;
- `WESI_RELAY_SSH_KNOWN_HOSTS`;
- `WESI_SERVER_KNOWN_HOSTS`;
- `WESI_MAIN_SHARED_SECRET`;
- `WESI_ZANE_TTS_VOICE`;
- `WESI_NIRVANA_TTS_VOICE`.

## Маршруты моделей

Маршруты не зашиты в приложение. Их можно менять GitHub Secrets без Flutter release:

| Secret | Пример |
|---|---|
| `WESI_AI_ROUTE_FAST` | `google/gemini-3.5-flash-lite` |
| `WESI_AI_ROUTE_PRO` | `google/gemini-3.6-flash` |
| `WESI_AI_ROUTE_MAXIMUM` | `google/gemini-3.6-flash` |
| `WESI_AI_ROUTE_ULTRA_LOW` | `xai/<актуальная-модель>` |
| `WESI_AI_ROUTE_ULTRA_MEDIUM` | `openai/<актуальная-модель>` |
| `WESI_AI_ROUTE_ULTRA_HIGH` | `anthropic/<актуальная-модель>` |

Если route secret не задан, workflow использует рабочий Gemini fallback. Поэтому отсутствие OpenAI/Anthropic/xAI не ломает Wesi AI.

Для получения точных актуальных model IDs после установки используется `GET /api/wesi/ai/models`; Relay сам обращается к provider Models APIs. Это предпочтительнее хранения длинного списка моделей в исходниках.

## Ultra

Логическая схема:

```text
Low    → обычно Grok
Medium → обычно ChatGPT
High   → обычно Claude
```

Server-side router оценивает сложность запроса и выбирает минимально достаточный уровень. При rate limit, отсутствии provider key, timeout или исчезновении выбранной модели выполняется fallback на следующий доступный уровень. История и память Wesi AI сохраняются.

## Adaptive Context

Relay собирает контекст уже после выбора фактического provider/model. Поэтому при Ultra fallback контекст пересчитывается под окно следующей модели. Клиент не привязан к одному фиксированному context limit.

## Media и голос

Gemini credential дополнительно используется для натурального TTS и Google generative media adapters. Тяжёлые media results передаются через одноразовые Relay artifacts; provider URLs и API keys не передаются Flutter-клиенту.

## Deployment

Запустить GitHub Actions workflow:

`Deploy Wesi AI End-to-End`

Input: DNS hostname Foreign Relay.

Workflow:

1. валидирует JS/shell/tests;
2. упаковывает API keys в временный sealed base64 bundle;
3. устанавливает все Relay `.mjs` modules как hardened systemd service;
4. настраивает HTTPS;
5. проверяет `/health`, signed model discovery, Gemini text, TTS и anti-replay;
6. строит `.wesi-ai-relay.json` с выбранными routes;
7. выкладывает Main hooks;
8. проверяет protected Wesi AI routes.

## Безопасность

Main ↔ Relay подписывает:

```text
requestId + "." + timestamp + "." + rawBody
```

Relay проверяет HMAC, freshness и replay. Provider keys записываются только в `/etc/wesi-ai-relay.env` с ограниченными правами и не попадают в Main Server config или приложение.

## Локальная проверка

```bash
node --test server/wesi-ai-relay/*.test.mjs
```
