# Wesi AI Relay

Зарубежный посредник между основным сервером WesiOS и Google AI API.

```text
WesiOS → api.wesi-inc.ru → Foreign Relay → Google AI → Relay → api.wesi-inc.ru → WesiOS
```

Provider credentials живут **только на Foreign Relay**. Flutter-клиент и основной сервер не получают `GEMINI_API_KEY`.

## Текущий статус

Код Relay, Main hooks, anti-replay, натуральный TTS, image/music/video adapters, WesiOS media storage и end-to-end deployment workflow подготовлены.

**Сам Foreign Relay ещё не развёрнут**, потому что в доступных WesiOS/GitHub данных нет зарубежного VPS и отдельного `GEMINI_API_KEY`.

## Что нужно предоставить один раз

Минимальный внешний набор:

1. зарубежный Debian/Ubuntu VPS с:
   - Node.js 20 или новее;
   - SSH;
   - пользователем с passwordless `sudo` для deployment-команд;
   - открытыми TCP 22, 80 и 443;
2. DNS hostname, например `ai-relay.example.com`, который уже указывает на этот VPS;
3. `GEMINI_API_KEY` с доступом к нужным Google AI моделям.

Firebase Android API key из `android/app/google-services.json` **не является заменой Gemini key**.

Отдельный Vertex key для музыки не требуется: текущий Relay использует Lyria 3 через Gemini API.

## Что добавить в GitHub Secrets

Обязательно:

| Secret | Назначение |
|---|---|
| `WESI_RELAY_SSH_USER` | SSH-пользователь зарубежного VPS с `sudo` |
| `WESI_RELAY_SSH_KEY` | приватный SSH-ключ этого пользователя |
| `GEMINI_API_KEY` | provider credential, устанавливается только на Relay |

Уже существующие Main Server secrets workflow использует автоматически:

- `WESI_SERVER_HOST`;
- `WESI_SERVER_USER`;
- `WESI_SERVER_SSH_KEY`;
- `WESI_SERVER_KNOWN_HOSTS` — если задан.

Необязательно:

| Secret | Назначение |
|---|---|
| `WESI_RELAY_SSH_HOST` | отдельный SSH host; если не задан, используется DNS hostname из workflow input |
| `WESI_RELAY_SSH_KNOWN_HOSTS` | pinned SSH host key Relay |
| `WESI_MAIN_SHARED_SECRET` | постоянный HMAC secret; если не задан, первый deployment генерирует сильный secret и ставит его на Relay и Main |
| `WESI_ZANE_TTS_VOICE` | override натурального голоса Зейна |
| `WESI_NIRVANA_TTS_VOICE` | override натурального голоса Нирваны |

Дефолты голосов: Зейн — `Charon`, Нирвана — `Sulafat`.

Для первого запуска `WESI_MAIN_SHARED_SECRET` можно не задавать. Для будущих повторных production-deploy рекомендуется сохранить постоянное случайное значение длиной не менее 32 символов в GitHub Secret: так даже оборванный redeploy не сможет временно оставить Main и Relay на разных HMAC secret.

## Единственный production запуск

После появления VPS, DNS и Secrets запустить GitHub Actions workflow:

`Deploy Wesi AI End-to-End`

Единственный input — DNS hostname Foreign Relay, например:

`ai-relay.example.com`

Workflow сам:

1. валидирует конфигурацию;
2. собирает Persona Bundle;
3. проверяет JS/shell и запускает весь Relay test suite;
4. создаёт единый HMAC secret, если постоянный не задан;
5. передаёт Relay credentials в закрытом временном bundle, не помещая API key в SSH command line;
6. ставит Relay как hardened systemd service;
7. устанавливает nginx и получает Let's Encrypt certificate;
8. проверяет HTTPS `/health`;
9. проверяет, что unsigned `/v1/wesi-ai` и `/v1/wesi-ai-artifact` возвращают 401;
10. делает живой Relay → Gemini text roundtrip;
11. повторяет тот же подписанный запрос и проверяет `WAI_RELAY_REPLAY_DETECTED`;
12. делает живой Gemini natural TTS roundtrip;
13. собирает `.wesi-ai-relay.json` для Main Server;
14. выкладывает все актуальные `wesi_ai_*` hooks и Persona Bundle на `api.wesi-inc.ru`;
15. устанавливает private configs с mode 600 и владельцем PocketBase;
16. перезапускает PocketBase;
17. проверяет Main → Relay HTTPS;
18. проверяет, что защищённые Wesi AI routes реально загрузились.

Ручного копирования shared secret между двумя серверами после этого нет.

## Provider operations

Один `GEMINI_API_KEY` используется Relay для:

- text routing:
  - `google/gemini-3.5-flash-lite` — fast;
  - `google/gemini-3.6-flash` — pro;
  - `google/gemini-3.6-flash` — maximum;
- natural speech: `gemini-3.1-flash-tts-preview`;
- images: `gemini-3.1-flash-image`;
- video: Veo 3.1 / Veo 3.1 Fast;
- music: Lyria 3 Clip / Lyria 3 Pro.

Модельные имена являются внутренней инфраструктурой. Пользователь WesiOS видит уровни Wesi AI, а не provider/model selector.

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

## Передача тяжёлых media artifacts

Image/music/video bytes не передаются клиенту как provider base64 и provider URL не сохраняется в истории.

Путь:

```text
Google → Relay → short-lived one-time Relay artifact
       → signed Main fetch
       → WesiOS-controlled storage
       → WesiOS media URL
       → client
```

Relay artifact:

- криптографический opaque id;
- ограниченный TTL;
- bounded memory;
- выдаётся только по отдельному подписанному Main request;
- уничтожается при первом успешном получении.

Для Veo Relay сам скачивает provider result с `GEMINI_API_KEY`. Каждый HTTP redirect обрабатывается вручную и повторно проверяется по Google API host allowlist **до** передачи API key следующему адресу. Затем проверяются MIME и максимальный размер, и Main получает только Wesi artifact handoff.

## Natural voice fallback

Клиент сначала пытается получить натуральный голос через Main → Relay → Gemini. Если Relay/провайдер недоступен, разговор автоматически продолжает работать через системный Android/Windows TTS.

Gemini TTS возвращает raw PCM 24 kHz mono 16-bit. Relay заворачивает PCM в настоящий RIFF/WAV перед отправкой Main/client. Android bridge завершает `speak()` только после фактического `onDone` озвучки, поэтому hands-free session не открывает микрофон, пока динамик ещё говорит.

## Локальная проверка

```bash
node --test server/wesi-ai-relay/*.test.mjs
```

Также production PR gate выполняет `node --check`, Relay tests, Persona validation, Flutter analyze/test, Android и Windows builds.
