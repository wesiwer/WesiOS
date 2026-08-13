# Wesi AI — серверная граница и зарубежный AI Relay

> **Актуальное решение владельца от 13 августа 2026.**
>
> Этот документ заменяет прежнюю схему, в которой зарубежный сервер считался самим Wesi AI Gateway с оркестрацией. Теперь **вся логика Wesi AI выполняется на основном сервере Wesi**, а зарубежный сервер является только транспортным посредником между основным сервером и внешними AI-провайдерами.

## 1. Главное правило

Вся вычислительная и продуктовая логика Wesi AI находится на основном сервере Wesi:

- аутентификация сотрудника;
- права;
- Organization scope;
- Persona Engine;
- профили Зейна и Нирваны;
- PromptComposer;
- ContextBuilder;
- rolling summaries и память;
- выбор capability;
- Model Router;
- Budget/Quota Manager;
- Lobby orchestration;
- handoff Зейн ↔ Нирвана;
- WesiOS Capability Registry;
- permission-aware read tools;
- Action Broker;
- risk/confirmation policy;
- audit действий;
- media job state;
- обработка результата модели;
- Persona Output Guard;
- связь с локальными и cloud-saved диалогами.

Зарубежный сервер **не принимает продуктовых решений** и не является источником истины для Wesi AI.

## 2. Целевая схема

```text
WesiOS на устройстве сотрудника
        |
        | HTTPS + Wesi session
        v
ОСНОВНОЙ СЕРВЕР WESI
        |
        |  auth / permissions / organizations
        |  Persona Engine
        |  Context Builder / memory
        |  Model Router / budgets
        |  WesiOS tools / Action Broker
        |  audit / media jobs
        |
        | сформированный provider request
        v
ЗАРУБЕЖНЫЙ WESI AI RELAY
        |
        | только transport/adaptation
        v
Gemini / Claude / image / Veo / другие модели
        |
        v
ЗАРУБЕЖНЫЙ WESI AI RELAY
        |
        | provider response / stream
        v
ОСНОВНОЙ СЕРВЕР WESI
        |
        | validation / persona / tool continuation
        v
WesiOS
```

Приложение не обращается к зарубежному Relay напрямую для AI-диалога. Клиент разговаривает с основным сервером Wesi.

## 3. Зачем нужен зарубежный Relay

Relay нужен как сетевой мост до внешних AI-провайдеров, в том числе когда прямой доступ основного сервера к нужному provider невозможен или нежелателен по сетевым/географическим причинам.

Его обязанности ограничены:

1. принять подписанный запрос от основного сервера;
2. проверить, что запрос пришёл от доверенного основного сервера;
3. преобразовать внутренний нейтральный transport contract в API конкретного provider;
4. отправить запрос provider;
5. вернуть stream/ответ/ошибку основному серверу;
6. поддержать cancel/status для долгих media jobs;
7. применять только инфраструктурные лимиты защиты Relay от перегрузки.

Relay **не должен**:

- решать, Зейн сейчас отвечает или Нирвана;
- строить долгосрочную память;
- решать права сотрудника;
- видеть или вычислять Organization grants как источник истины;
- выбирать, разрешено ли создать задачу;
- самостоятельно обращаться к Treasury/CRM/Tasks/PocketBase;
- принимать бизнес-решения;
- хранить пользовательские чаты как продуктовую БД;
- быть владельцем Lobby state;
- решать, какую модель выгоднее выбрать, кроме аварийного transport fallback, явно разрешённого основным сервером.

## 4. Основной сервер — единственный оркестратор

Основной сервер получает запрос пользователя и заново определяет:

```text
employeeId
session/device
active organization
current grants
available capabilities
conversation state
persona
model mode
budget/quota state
```

После этого он:

1. получает только разрешённые данные WesiOS;
2. формирует context package;
3. применяет Persona Bible;
4. выбирает provider/model;
5. формирует tool schema, если нужны инструменты;
6. отправляет provider request через Relay;
7. принимает model response;
8. выполняет tool calls только через WesiOS Action Broker;
9. при необходимости делает следующий model turn;
10. проверяет итоговый ответ;
11. возвращает stream/result клиенту.

Никакая логика прав не переносится на Relay или underlying-модель.

## 5. Клиентский API

WesiOS должен общаться только с основным сервером Wesi, например:

```text
GET    /api/wesi-ai/capabilities
GET    /api/wesi-ai/models
POST   /api/wesi-ai/chat
POST   /api/wesi-ai/conversations/{id}/cloud-save
DELETE /api/wesi-ai/conversations/{id}/cloud-save
POST   /api/wesi-ai/media/jobs
GET    /api/wesi-ai/media/jobs/{id}
DELETE /api/wesi-ai/media/jobs/{id}
```

Конкретные URL могут меняться, но граница ответственности — нет.

Клиент не должен знать адрес зарубежного Relay для обычной работы.

## 6. Внутренний контракт Main Server → Relay

Relay получает уже готовый provider request. Пример внутренней формы:

```json
{
  "request_id": "wai_req_123",
  "provider": "google",
  "model": "selected-model-id",
  "operation": "chat.stream",
  "payload": {
    "messages": [],
    "tools": [],
    "generation_config": {}
  },
  "deadline_ms": 60000
}
```

Для media:

```json
{
  "request_id": "wai_media_123",
  "provider": "google",
  "model": "selected-video-model",
  "operation": "video.generate",
  "payload": {},
  "deadline_ms": 120000
}
```

Relay не должен требовать `employeeId`, `organizationId`, роль или grant list, если это не требуется исключительно для технической трассировки безопасности. Предпочтительно передавать непрозрачный `request_id`.

## 7. Provider credentials

Provider API keys не находятся в Flutter-приложении и не выдаются сотрудникам.

Поскольку именно зарубежный Relay устанавливает соединение с Gemini/Claude/Veo и другими provider API, provider credentials допустимо хранить **только в защищённом secret storage зарубежного Relay** либо использовать эквивалентный серверный механизм выдачи краткоживущих provider credentials.

Основной сервер хранит только те секреты, которые нужны для доверенного канала Main ↔ Relay, если конкретный provider contract не требует иного.

Секреты запрещено:

- возвращать клиенту;
- писать в обычные логи;
- вставлять в conversation history;
- передавать underlying-модели как часть prompt.

## 8. Доверенный канал Main ↔ Relay

Relay принимает AI-трафик только от основного сервера Wesi.

Минимальные требования:

- TLS;
- server-to-server authentication;
- короткоживущая подпись/HMAC/JWT или mTLS;
- request id;
- timestamp/expiry;
- replay protection;
- ограничение размера body;
- rate limits;
- audit технических ошибок без сохранения полного prompt по умолчанию.

Публичный unauthenticated relay endpoint запрещён.

## 9. Persona и контекст

Persona Engine находится на основном сервере.

Relay получает уже сформированный model payload и не должен иметь собственной версии характера Зейна/Нирваны. Иначе два сервера могут начать расходиться по правилам.

Authoritative Persona Bible:

```text
docs/wesi_ai/personas/ZANE_PERSONA.md
docs/wesi_ai/personas/NIRVANA_PERSONA.md
```

Основной сервер формирует system/developer context из этих правил и текущего состояния Wesi AI.

## 10. Модели и самоидентификация

Технический интерфейс WesiOS может показывать пользователю selector моделей/режимов (Auto/Fast/Pro/Claude и актуальные варианты).

При этом Зейн и Нирвана в своей **самоидентификации** являются Wesi AI от Wesi Inc., а не underlying-моделью. Они не должны менять имя/характер при смене provider.

Это не запрещает:

- model selector в UI;
- админскую диагностику provider;
- отображение технического model execution metadata, если продукт это решит показывать.

## 11. Tool calls и WesiOS

Underlying-модель может предложить только structured tool intent.

Пример:

```json
{
  "tool": "tasks.assign",
  "arguments": {
    "assignee_id": "employee_ivan",
    "title": "Проверить рекламные кампании",
    "due_date": "2026-08-14"
  }
}
```

После возврата через Relay этот intent приходит **на основной сервер**, где выполняются:

```text
identity check
→ organization scope
→ permission check
→ validation
→ risk/confirmation gate
→ штатный WesiOS service
→ sync/backend
→ ActionResult
```

Relay ничего из этого не выполняет.

## 12. Read tools

Реальные данные Treasury/Horizon/CRM/Tasks/Knowledge/Team и других модулей выбирает основной сервер строго по текущим правам сотрудника.

Запрещённые данные не должны попадать в provider payload вообще.

## 13. Streaming

Для text streaming:

```text
Provider
→ Relay (stream passthrough/adaptation)
→ Main Server
→ validation/state
→ WesiOS
```

Relay может преобразовать формат stream конкретного provider во внутренний transport stream, но не должен менять смысл ответа или persona.

## 14. Media jobs

Состояние media job как продуктовая сущность принадлежит основному серверу.

Relay хранит только provider-side technical state, необходимый для продолжения запроса, например provider job id.

Основной сервер связывает результат с:

- employee;
- conversation;
- persona;
- source artifact;
- cloud/local policy;
- audit state.

## 15. Ошибки

Relay нормализует provider/network ошибки в транспортные коды, например:

```text
WAI_RELAY_AUTH_FAILED
WAI_PROVIDER_UNAVAILABLE
WAI_PROVIDER_TIMEOUT
WAI_PROVIDER_RATE_LIMIT
WAI_PROVIDER_REJECTED
WAI_MEDIA_JOB_FAILED
WAI_RELAY_BAD_RESPONSE
```

Основной сервер решает:

- повторять ли запрос;
- переключать ли provider;
- как учитывать quota;
- что показать пользователю;
- должен ли persona сформулировать ответ об ошибке.

## 16. Privacy / минимизация данных

Основной сервер должен отправлять provider только минимально необходимый контекст.

Relay не хранит полный prompt/response постоянно. По умолчанию допустимы только технические метаданные:

```text
request_id
provider/model
operation
start/end time
status
latency
bytes
token/cost metadata where available
error code
```

Полные prompts/responses могут попадать в диагностический режим только при явно контролируемой процедуре с ограниченным сроком хранения и без секретов.

## 17. Отказоустойчивость

Если Relay недоступен:

- основной сервер возвращает контролируемую ошибку;
- локальные чаты не повреждаются;
- pending message можно повторить;
- media job сохраняет известное состояние;
- никакие WesiOS actions не считаются выполненными без подтверждённого ActionResult.

Если provider недоступен, основной сервер может выбрать разрешённый fallback provider через тот же Relay.

## 18. Критерии готовности

Архитектура считается реализованной, когда:

- WesiOS не вызывает Gemini/Claude/Veo напрямую;
- WesiOS не вызывает зарубежный Relay напрямую для AI-чата;
- вся product logic находится на основном сервере;
- Relay не имеет доступа к WesiOS business services;
- permissions и organization scope проверяются на основном сервере при каждом tool call;
- provider keys отсутствуют в клиенте;
- Persona Bible существует только в authoritative Wesi AI logic, а не расходится копиями между серверами;
- model selection выполняет основной сервер;
- Relay только отправляет запрос выбранному provider и возвращает ответ;
- streaming проходит Provider → Relay → Main → Client;
- media job ownership/state находится на основном сервере;
- revoke прав немедленно влияет на следующий AI tool call;
- при отказе Relay/Provider не возникает ложного «готово»;
- audit WesiOS actions ведётся на основном сервере.

## 19. Итог

**Основной сервер Wesi — мозг Wesi AI. Зарубежный сервер — провод до внешних моделей.**

Нельзя снова переносить Persona Engine, память, model routing, права, WesiOS actions или Lobby orchestration на зарубежный Relay без отдельного решения владельца.
