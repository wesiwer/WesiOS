# Wesi AI Relay

Зарубежный посредник между основным сервером WesiOS и AI providers.

```text
WesiOS → api.wesi-inc.ru → Foreign Relay → AI provider → Relay → api.wesi-inc.ru → WesiOS
```

Provider credentials живут **только на Foreign Relay**. Flutter-клиент и основной сервер не получают `GEMINI_API_KEY` и другие provider keys.

## Архитектурная роль

Main Server оперирует только логическими маршрутами `wesi/fast`, `wesi/pro`, `wesi/ultra`. Конкретный provider, model и credential slot выбираются на Foreign Relay. Поэтому клиент не может сам повысить уровень модели или подменить provider/model selector.

## Что нужно для production

Минимальный внешний набор:

1. зарубежный Debian/Ubuntu VPS с:
   - Node.js 20 или новее;
   - SSH;
   - пользователем с passwordless `sudo` для deployment-команд;
   - открытыми TCP 22, 80 и 443;
2. DNS hostname, например `ai.wesi-wf.su`;
3. основной `GEMINI_API_KEY` с доступом к нужным Google AI моделям.

Firebase Android API key из `android/app/google-services.json` **не является заменой Gemini key**.

## GitHub Secrets

Обязательно:

| Secret | Назначение |
|---|---|
| `WESI_RELAY_SSH_USER` | SSH-пользователь Foreign Relay с `sudo` |
| `WESI_RELAY_SSH_KEY` | приватный SSH-ключ Relay |
| `GEMINI_API_KEY` | основной Gemini credential; хранится только на Relay |

Дополнительная Gemini capacity / failover:

| Secret | Назначение |
|---|---|
| `GEMINI_API_KEY_2` | резервный Gemini credential slot |
| `GEMINI_API_KEY_3` | резервный Gemini credential slot |
| `GEMINI_API_KEY_4` | резервный Gemini credential slot |
| `GEMINI_API_KEY_5` | резервный Gemini credential slot |

Одинаковые значения автоматически дедуплицируются. Credential slot **не определяет качество модели**: все Gemini slots в конкретном запросе вызывают только модель, назначенную текущему tier.

Дополнительные providers:

- `GROQ_API_KEY`;
- `MISTRAL_API_KEY`;
- `OPENROUTER_API_KEY`.

Уже существующие Main Server secrets workflow использует автоматически:

- `WESI_SERVER_HOST`;
- `WESI_SERVER_USER`;
- `WESI_SERVER_SSH_KEY`;
- `WESI_SERVER_KNOWN_HOSTS` — если задан.

Остальные необязательные параметры:

| Secret | Назначение |
|---|---|
| `WESI_RELAY_SSH_HOST` | отдельный SSH host; если не задан, используется DNS hostname |
| `WESI_RELAY_SSH_KNOWN_HOSTS` | pinned SSH host key Relay |
| `WESI_MAIN_SHARED_SECRET` | постоянный HMAC secret Main ↔ Relay |
| `WESI_ZANE_TTS_VOICE` | override натурального голоса Зейна |
| `WESI_NIRVANA_TTS_VOICE` | override натурального голоса Нирваны |

Дефолты голосов: Зейн — `Charon`, Нирвана — `Sulafat`.

## Tier-aware routing

Модельный tier и API credential — две разные сущности. Наличие пяти ключей не даёт Fast права использовать модель из Pro/Maximum.

### Fast

Цель: минимальная задержка и дешёвая ёмкость.

Порядок:

1. `gemini-3.5-flash-lite` через основной Gemini slot;
2. та же `gemini-3.5-flash-lite` через `GEMINI_API_KEY_2…5`;
3. fast-модель Groq;
4. fast-модель Mistral;
5. OpenRouter только если для Fast явно задан конкретный allowlisted model override.

Динамический `openrouter/free` в Fast не используется: выбранная им модель заранее не гарантирована, поэтому он мог бы нарушить правило `Fast < Pro < Maximum`.

### Pro

Цель: более качественный анализ и проверка ответа.

Pro собирает независимые Pro-advisor notes, затем использует **только Pro finalizer pool**:

1. Pro Gemini model через primary и secondary Gemini slots;
2. Pro Mistral finalizer;
3. Pro Groq finalizer;
4. необязательный явно назначенный Pro OpenRouter model.

Fast-кандидаты в этот pool не входят; Maximum-кандидаты также не могут случайно попасть в Pro благодаря runtime tier assertion.

### Maximum

Цель: самый широкий доступный анализ.

Maximum использует собственный `ultra` advisor/finalizer pool. Он может привлекать больше независимых advisor providers, чем Pro, затем выполняет финальную синтезацию в Maximum-only pool. Fast-кандидаты не используются.

Если весь Maximum pool недоступен, Relay возвращает честную ошибку вместо того, чтобы незаметно выдать одиночный слабый advisor answer как «Maximum».

## Automatic failover и cooldown

Для каждого сочетания `provider + model + credential slot` Relay ведёт отдельное in-memory health state.

- `429 / rate limit` — слот временно уходит в exponential cooldown; базово 60 секунд, максимум 6 часов;
- transient `5xx / unavailable / timeout` — базовый cooldown 15 секунд, максимум 5 минут;
- provider auth failure — более длинный cooldown;
- успешный запрос сбрасывает failure state;
- после окончания cooldown primary slot автоматически снова получает первый приоритет;
- `400`-класс ошибок запроса/вложения не размножается по всем providers;
- streaming может переключиться на другой provider только **до** выдачи первой части ответа. После emitted bytes failover запрещён, чтобы два provider-ответа не склеились в один текст.

Несколько credentials предназначены для легитимной отказоустойчивости и доступной provider capacity. Router не должен использоваться для обхода ограничений или условий конкретного провайдера.

## Attachments

Вложения остаются Gemini-only, пока non-Gemini adapters не получат проверенный multimodal transport. При этом attachment request также умеет перебирать Gemini credential slots, **не меняя tier-модель**:

- Fast → Fast Gemini model;
- Pro → Pro Gemini model;
- Maximum → Maximum Gemini model.

Файлы никогда не отбрасываются молча ради fallback на text-only provider.

## Обновление provider credentials без client release

После добавления/изменения GitHub Secrets можно запустить:

`Configure Wesi AI Router`

Workflow сформирует закрытый provider bundle, обновит `/etc/wesi-ai-providers.env` на Relay и перезапустит только Relay. Flutter APK и Main Server не получают сами credentials.

Полный `Deploy Wesi AI End-to-End` также сохраняет `GEMINI_API_KEY_2…5`, поэтому обычный redeploy больше не стирает failover pool.

## Защита Main ↔ Relay

Подписывается точная строка:

```text
requestId + "." + timestamp + "." + rawBody
```

Relay:

- проверяет HMAC;
- проверяет freshness;
- запоминает принятый request id;
- отклоняет replay;
- не резервирует request id для запроса с неверной подписью;
- fail-closed при переполнении bounded replay cache.

Одинаковый контракт покрыт Relay tests и production deployment smoke-test.

## Media

Основной Gemini credential по-прежнему используется для provider operations, которые пока не переведены на text tier pool: natural speech и разрешённые cloud media operations. Бесплатные локальные Wesi Media Engines остаются отдельным контуром.

Image/music/video bytes не передаются клиенту как provider base64 и provider URL не сохраняется в истории.

```text
Provider → Relay → short-lived one-time Relay artifact
         → signed Main fetch
         → WesiOS-controlled storage
         → WesiOS media URL
         → client
```

Relay artifact имеет opaque id, ограниченный TTL и bounded storage, выдаётся только по подписанному Main request и уничтожается после успешного получения.

## Natural voice fallback

Клиент сначала пытается получить натуральный голос через Main → Relay → provider. Если Relay/провайдер недоступен, разговор автоматически продолжает работать через системный Android/Windows TTS.

## Проверка

```bash
node --check server/wesi-ai-relay/*.mjs
node --test server/wesi-ai-relay/*.test.mjs
bash -n server/wesi-ai-relay/deploy-relay.sh
```

Regression tests отдельно фиксируют:

- Fast не принимает Pro/Maximum candidates;
- Pro не принимает Maximum candidates;
- реальные Fast pools не содержат higher-tier candidates;
- Pro/Maximum finalizer pools остаются внутри своего tier;
- primary Gemini `429` переключает Fast на secondary Gemini credential, но URL модели остаётся `gemini-3.5-flash-lite`;
- cooling primary slot пропускается и автоматически возвращается после cooldown;
- invalid request не fan-out'ится;
- streaming не переключается после частичного ответа;
- пользовательская cancellation останавливает весь pool.
