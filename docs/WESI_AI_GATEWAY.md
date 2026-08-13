# Wesi AI — Main Server и зарубежный AI Relay

> **Статус:** AUTHORITATIVE SERVER BOUNDARY
>
> Главный продуктовый источник истины: `docs/WESI_AI_SPEC.md`.

## 1. Неизменяемая граница

```text
WesiOS client
   ↓ HTTPS + Wesi session
ОСНОВНОЙ СЕРВЕР WESI
   ↓ signed server-to-server request
ЗАРУБЕЖНЫЙ WESI AI RELAY
   ↓ provider API
ВНЕШНИЙ AI PROVIDER
   ↓
RELAY
   ↓
ОСНОВНОЙ СЕРВЕР
   ↓
WesiOS client
```

**Основной сервер — мозг Wesi AI. Foreign Relay — только транспортный посредник.**

## 2. Основной сервер отвечает за

- auth сотрудника и device/session context;
- permissions/grants и Organization scope;
- Persona Engine Зейна/Нирваны;
- PromptComposer / ContextBuilder / Output Guard;
- обработку присланного клиентом local-first context package;
- shared + persona memory processing;
- внутренний Model Router;
- mapping `Wesi AI Быстрый / Pro / Максимальный` → внутренний route;
- Budget/Quota Manager;
- handoff и Lobby orchestration;
- Capability Registry;
- permission-aware WesiOS read tools;
- Action Broker;
- risk/confirmation policy;
- audit;
- media job ownership;
- retries/fallback policy;
- финальную validation результата.

Обычная история локального чата не становится постоянной server-side conversation DB: основной сервер обрабатывает присланный context на время request/stream и после завершения не хранит его, кроме явно сохранённого backup и обязательных audit/action records.

## 3. Relay отвечает только за

1. проверку доверенного server-to-server запроса;
2. использование защищённых provider credentials;
3. адаптацию внутреннего transport contract к API выбранного provider;
4. отправку запроса;
5. passthrough/adaptation stream/result/status/error;
6. provider-side cancel/status для media jobs;
7. инфраструктурные rate/size/abuse limits самого Relay.

Relay не определяет persona, права, Organization scope, WesiOS actions, Lobby, память, продуктовый budget, user-facing tier и не читает Treasury/CRM/Tasks/PocketBase.

## 4. Скрытие underlying providers от сотрудника

Реальные provider/model names являются внутренней инфраструктурной информацией.

Сотрудник видит только:

```text
Wesi AI Быстрый
Wesi AI Pro
Wesi AI Максимальный
```

Эта настройка общая для Зейна и Нирваны. Клиентские API и UI не должны возвращать реальный provider/model name как пользовательскую функцию. Зейн, Нирвана и Lobby также не раскрывают underlying providers/models.

Внутренние защищённые admin/ops logs могут содержать provider metadata для эксплуатации, но она не передаётся сотруднику и не является частью persona identity.

## 5. Provider credentials

Provider API keys находятся только в защищённом secret storage зарубежного Relay либо заменяются эквивалентным short-lived provider credential mechanism.

Запрещено помещать provider keys в Flutter, conversation history, prompts, обычные логи или ответы клиенту.

Основной сервер хранит только секреты доверенного канала Main ↔ Relay и собственные WesiOS secrets.

## 6. Main → Relay contract

Relay получает уже выбранный внутренний route и готовый provider payload, например:

```json
{
  "request_id": "wai_req_123",
  "provider": "internal-provider-id",
  "model": "internal-model-id",
  "operation": "chat.stream",
  "payload": {
    "messages": [],
    "tools": [],
    "generation_config": {}
  },
  "deadline_ms": 60000
}
```

`provider`/`model` существуют только внутри доверенного server-to-server контура.

Relay предпочтительно не получает `employeeId`, роль или grant list. Для трассировки используется opaque `request_id`.

## 7. Доверенный канал

Минимум:

- TLS;
- server-to-server authentication;
- mTLS либо short-lived HMAC/JWT signature;
- request id;
- timestamp/expiry;
- replay protection;
- body-size limits;
- rate limits;
- технический audit без полного prompt по умолчанию.

Публичный unauthenticated Relay endpoint запрещён.

## 8. Tool calls

Underlying-модель возвращает только structured intent. Он проходит обратно через Relay на основной сервер.

```text
model tool intent
→ Relay
→ Main Server
→ fresh employee identity
→ Organization scope
→ permissions
→ validation
→ risk gate
→ штатный WesiOS service
→ verified ActionResult
```

Relay не выполняет WesiOS tools.

Запрещённые business data не должны попадать в provider payload вообще.

## 9. Streaming

```text
Provider
→ Relay stream adaptation
→ Main Server validation/state
→ WesiOS
```

Relay может нормализовать транспортный формат stream, но не меняет persona или смысл ответа.

## 10. Media jobs

Продуктовая media job принадлежит основному серверу. Relay хранит только минимальный provider-side technical state, необходимый для продолжения/cancel/status.

Основной сервер связывает job с employee, conversation, persona, source artifact и audit state.

## 11. Error contract

Relay нормализует provider/network failures, например:

```text
WAI_RELAY_AUTH_FAILED
WAI_PROVIDER_UNAVAILABLE
WAI_PROVIDER_TIMEOUT
WAI_PROVIDER_RATE_LIMIT
WAI_PROVIDER_REJECTED
WAI_MEDIA_JOB_FAILED
WAI_RELAY_BAD_RESPONSE
```

Основной сервер решает retry, fallback, quota accounting и user-facing response.

## 12. Privacy

Relay не хранит prompts/responses постоянно. По умолчанию допустимы только технические метаданные: request id, internal provider/model id, operation, timing, status, latency, bytes, token/cost metadata и error code.

Основной сервер получает от клиента минимально необходимый context package. Обычная local-first conversation history после request не сохраняется на сервере.

## 13. Wi-Fi перенос чатов

Device-to-device перенос чатов/памяти по одной локальной сети **не проходит через Foreign Relay**.

Основной сервер может помочь подтвердить пользователя/устройства и выдать короткоживущий handshake token, но содержимое transfer идёт напрямую между устройствами.

## 14. Критерии готовности

- клиент не вызывает external AI providers напрямую;
- клиент не вызывает Foreign Relay напрямую;
- вся продуктовая логика находится на Main Server;
- Relay не имеет доступа к WesiOS business services;
- provider keys отсутствуют в клиенте;
- employee-facing surfaces не раскрывают provider/model names;
- permissions/org scope проверяются на Main Server при каждом tool call;
- Persona Bible применяется только authoritative server logic;
- streaming проходит Provider → Relay → Main → Client;
- local-first context не превращается в скрытую server-side history;
- D2D transfer не маршрутизирует содержимое через Relay/Main;
- media job ownership находится на Main Server;
- Relay является заменяемым transport component, а не владельцем Wesi AI.
