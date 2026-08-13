# Wesi AI — единое ТЗ и живой статус разработки

> **Статус:** AUTHORITATIVE / OWNER-APPROVED SOURCE OF TRUTH
>
> **Дата консолидации:** 13 августа 2026.
>
> Этот файл объединяет исходное ТЗ, PDF-спецификацию характеров, решения владельца, серверную архитектуру и последующие уточнения. При разработке Wesi AI начинать нужно с этого документа. Persona Bible и `docs/WESI_AI_GATEWAY.md` являются специализированными обязательными приложениями.

---

## 0. Правила для разработчиков и AI-агентов

1. Перед изменением Wesi AI прочитать этот файл, `docs/WESI_AI_GATEWAY.md`, `docs/wesi_ai/personas/ZANE_PERSONA.md` и `docs/wesi_ai/personas/NIRVANA_PERSONA.md`.
2. Прямые решения владельца из этого ТЗ нельзя тихо переопределять.
3. После каждого законченного этапа обновлять разделы **Статус реализации** и **Журнал разработки**.
4. UI-заглушка, mock или код только в отдельной ветке не считаются готовой production-функцией.
5. Старые addendum/decision-файлы после консолидации являются историей решений, а не параллельными источниками истины.

---

# 1. Продуктовая идея

Wesi AI — полноценное AI-приложение и интеллектуальный слой управления WesiOS, а не обёртка над одной внешней моделью.

Продуктом являются Зейн и Нирвана, их память и контекст, несколько чатов, Lobby и handoff, мультимодальная работа, генерация изображений/видео, анализ реальных данных WesiOS, выполнение реальных действий WesiOS, права/Organization scope/audit, серверная оркестрация и фирменные уровни Wesi AI.

Underlying AI providers — внутренняя реализация и не являются пользовательской идентичностью продукта.

---

# 2. Изоляция сотрудников

## ОБЯЗАТЕЛЬНО

У каждого сотрудника собственный изолированный Wesi AI. Отдельны по `employeeId`: чаты, сообщения, summaries, общая персональная память, память Зейна, память Нирваны, attachments/artifacts, media generations, настройки, сохранённые важные разговоры и AI action audit.

AI одного сотрудника не получает AI-память другого. Общие корпоративные данные доступны только через обычные permissions и Organization scope WesiOS.

---

# 3. Зейн и Нирвана

Канонические характеры взяты из PDF-спецификации владельца v2.0 и зафиксированы в:

- `docs/wesi_ai/personas/ZANE_PERSONA.md`;
- `docs/wesi_ai/personas/NIRVANA_PERSONA.md`.

## 3.1 Зейн

Зейн — технический аналитик и вычислительный модуль Wesi AI: данные, математика, статистика, код, расчёты, прогнозы, инженерия и системная логика. Харизматичный, резкий, прямолинейный; чёрный юмор, провокационная манера и уместный мат являются частью характера. Он подкалывает Нирвану за мягкость, но относится к ней как к сестре. Характер должен чувствоваться и в коротких репликах.

## 3.2 Нирвана

Нирвана — творческий и гуманитарный модуль Wesi AI: изображения, видео, музыка, философия, душевные разговоры, литература, копирайтинг и арт-дирекшн. Она эмпатичная, утончённая и искренняя, никогда не матерится, любит людей и животных, особенно собак. Не поддерживает грубый юмор Зейна и мягко возражает ему. Зейна любит как брата.

## 3.3 Общие правила личности

- оба воспринимают Wesi AI как свой цифровой дом;
- остаются отдельными личностями при любом внутреннем provider route;
- не называют себя сторонними моделями и не раскрывают, на базе каких сторонних моделей/провайдеров работают;
- не называют друг друга «моделями» или «персонажами» в обычном разговоре;
- смена внутренней модели не меняет характер, память или имя;
- Persona Bible не является security boundary: права всегда задаёт WesiOS.

---

# 4. Persona Engine

Основной сервер Wesi содержит Persona Engine, PromptComposer и Persona Output Guard. В provider request собираются Wesi AI core rules, Persona Bible, security/tool rules, employee+organization context, релевантная shared/persona memory, conversation summary, task state, recent messages, attachments/artifacts и текущий запрос.

Output Guard следит за явным выпадением из характера и prompt injection, но не подменяет факты, tool results или permissions.

---

# 5. Чаты и local-first хранение

Wesi AI поддерживает несколько независимых чатов с Зейном, Нирваной и Lobby: создание, название/автозаголовок, переименование, закрепление, архив, удаление, поиск, сортировка, attachments/artifacts и продолжение после restart.

## ОБЯЗАТЕЛЬНО

Source of truth обычного разговора — устройство сотрудника. Локально хранятся conversation metadata, messages, rolling summaries, task state, memories, attachments/artifacts metadata, action results и настройки.

При каждом AI-запросе устройство отправляет основному серверу только необходимый context package. Основной сервер может держать его в оперативной памяти на время request/stream, но **не хранит обычную историю активного локального чата после завершения запроса**. Исключения: явно сохранённый важный разговор и обязательные audit/action records.

---

# 6. Память

У сотрудника три слоя долговременной памяти:

```text
Employee AI memory
├── shared_personal_memory
├── zane_persona_memory
└── nirvana_persona_memory
```

Shared memory доступна обоим. Дополнительно каждый чат имеет recent context, rolling summary и task state. Память не смешивается между сотрудниками. Пользователь должен иметь возможность видеть/удалять долговременные memories и управлять запоминанием.

---

# 7. Сохранение важных разговоров и перенос устройств

Пользователь может явно сохранить важный разговор на основном сервере как защищённую backup-копию, чтобы не потерять его. Обычные чаты автоматически туда не отправляются.

## Перенос между своими устройствами — ОБЯЗАТЕЛЬНО

Перенос чатов и памяти между двумя доступными устройствами выполняется **напрямую device-to-device по одной локальной сети / Wi-Fi**.

1. сотрудник авторизован на обоих устройствах;
2. оба находятся в одной локальной сети;
3. исходное устройство запускает передачу;
4. принимающее устройство явно подтверждает;
5. устанавливается защищённый локальный канал;
6. выбранные данные передаются напрямую.

Можно передавать отдельный чат, набор/все чаты, shared memory, память Зейна, память Нирваны и связанные локальные вложения/артефакты.

Основной сервер может подтвердить пользователя/устройства и выдать короткоживущий handshake token, но содержимое transfer не маршрутизируется через основной сервер. Foreign AI Relay в переносе не участвует.

---

# 8. Серверная архитектура

## ОБЯЗАТЕЛЬНО

```text
WesiOS
  ↓
ОСНОВНОЙ СЕРВЕР WESI
  ↓
ЗАРУБЕЖНЫЙ WESI AI RELAY
  ↓
ВНЕШНИЕ AI PROVIDERS
  ↓
ЗАРУБЕЖНЫЙ RELAY
  ↓
ОСНОВНОЙ СЕРВЕР WESI
  ↓
WesiOS
```

**Основной сервер Wesi — мозг Wesi AI.** На нём находятся auth, permissions, Organizations, Persona Engine, ContextBuilder, memory processing, Model Router, Budget Manager, handoff, Lobby, WesiOS tools, Action Broker, risk policy, audit, media ownership и validation.

**Зарубежный сервер — только Relay.** Он принимает подписанный server-to-server request, использует provider credentials, вызывает выбранный provider и возвращает stream/result/status. Он не решает права, persona, business logic и не читает Treasury/CRM/Tasks. Подробности: `docs/WESI_AI_GATEWAY.md`.

---

# 9. Фирменные уровни Wesi AI

Сотрудник видит только:

```text
Wesi AI Быстрый
Wesi AI Pro
Wesi AI Максимальный
```

Выбранный уровень — общая настройка Wesi AI и применяется сразу к Зейну и Нирване.

Пользовательский UI, ответы Зейна/Нирваны и Lobby **не показывают и не раскрывают реальные названия сторонних providers/models**. Реальный mapping — внутренняя серверная деталь.

`Wesi AI Максимальный` задаёт максимальную планку качества и вычислительного бюджета, но сервер не обязан использовать самый тяжёлый route для простого сообщения. Для тривиальных запросов допустим лёгкий внутренний route при сохранении качества/persona; для сложных задач Максимальный разрешает сильнейший доступный route, больший reasoning/context budget и дополнительные проверки.

Provider credentials хранятся в защищённом secret storage зарубежного Relay. Клиент их никогда не получает.

---

# 10. Streaming и мультимодальность

Текст стримится постепенно. Нужны stop, retry/regenerate и корректное восстановление ошибок. Timeline поддерживает текст, изображения, видео, аудио, документы, код, таблицы/structured results, WesiOS action cards, errors и ссылки на объекты WesiOS.

---

# 11. Изображения и видео

Изображения создаются/редактируются inline в текущем чате через внутренний image-generation route класса Nano Banana или актуальный эквивалент. Следующая команда может ссылаться на активный artifact без повторной загрузки.

Видео создаётся inline через внутренний video-generation route класса Veo или актуальный эквивалент. Долгие jobs имеют стабильный `jobId`, progress/status/cancel/retry и восстанавливаются после restart. Конкретный внешний provider сотруднику не раскрывается.

---

# 12. Выбор persona, handoff и Lobby

По умолчанию сотрудник **сам выбирает**, кому писать: Зейну или Нирване.

Если запрос лучше соответствует другой persona, текущая persona предлагает переключение в своём характере. Переключение происходит после согласия пользователя. Handoff передаёт цель, запрос, решения, ограничения, summary, релевантные messages/memories, WesiOS object references, attachments/artifacts, pending actions и открытые вопросы. Пользователь не повторяет задачу. Если пользователь не хочет переключаться, текущая persona продолжает помогать.

Если по контексту действительно нужны оба, разговор может перейти в Lobby: пользователь просит позвать второго, задача одновременно техническая и творческая либо текущая persona определяет необходимость обеих сторон.

В Lobby они остаются отдельными авторами и могут отвечать пользователю и друг другу. Режимы:

- **Оба отвечают**;
- **Умное Lobby** — основной сервер строит ограниченный план реплик.

Всегда действуют лимиты turns/cost/latency.

---

# 13. Полное взаимодействие с WesiOS

## ОБЯЗАТЕЛЬНО

Wesi AI — natural-language interface ко всей WesiOS. Он читает и анализирует реальные разрешённые данные Treasury/Horizon/Tasks/CRM/Team/Organizations/Knowledge/Roadmap/Audio Vault и других модулей, а также выполняет реальные разрешённые действия.

Примеры: анализ реальных финансов; объяснение Horizon; реальное создание/назначение задачи; создание события; изменение срока; поиск/изменение CRM-объекта. AI не должен фантазировать данные, которые может получить из WesiOS.

---

# 14. Capability Registry и Action Broker

Underlying-модель не получает произвольный DB/API доступ. Она предлагает structured tool intent. Capability Registry постепенно включает finance, tasks, calendar, CRM, team, organizations, knowledge, roadmap, Audio Vault, notifications и другие WesiOS capabilities.

```text
User request
→ Main Server / Persona / Model
→ structured tool intent
→ Action Broker
→ fresh identity + org scope + permission check
→ validation
→ risk gate
→ existing WesiOS service
→ verified ActionResult
→ persona response
```

AI говорит «готово» только после `ActionResult.success`.

---

# 15. Права: AI = текущий сотрудник

## КРИТИЧЕСКОЕ ПРАВИЛО

Зейн, Нирвана, Lobby, серверная orchestration и underlying-модель **никогда не расширяют права пользователя**.

Если сотрудник не может назначать задачи другим, AI тоже не может. Если сотрудник видит только определённую организацию, запрещённые данные вообще не попадают в model context.

Проверка выполняется кодом/backend, а не просьбой в prompt. Каждый read/write заново учитывает актуальные grants и Organization scope; старый чат не сохраняет отозванные права.

При отказе по правам AI объясняет причину в характере persona и предлагает ближайшую разрешённую альтернативу.

---

# 16. Read, write и multi-step policy

- Обычные разрешённые **read-tools** выполняются автоматически без дополнительного подтверждения.
- Однозначные обычные обратимые **write-actions** выполняются сразу, если права позволяют.
- Массовые, неоднозначные, значимые и критические операции требуют preview/confirmation согласно Risk Policy.
- Wesi AI умеет планировать multi-step работу: анализ → понятный план → после согласия пользователя цепочка разрешённых действий.
- Каждый tool call в цепочке отдельно проходит свежую permission-проверку.

---

# 17. Audit и безопасность

Реальные AI-действия имеют audit record: employee, persona, conversation, action, target, organization, permission decision, confirmation state, result/error и timestamp без секретов.

Provider keys, admin credentials и raw DB access не передаются модели или клиенту. Контент документов, CRM, Knowledge Base, web/file attachments считается недоверенными данными и не может через prompt injection расширить permissions, изменить Persona Bible, открыть tools или отключить audit/risk gate.

---

# 18. Proactive Wesi AI

Proactive insights настраиваются отдельно для каждого сотрудника: enabled, categories, quiet hours, importance threshold, notification channels. Технические/финансовые/аналитические сигналы обычно ведёт Зейн, творческие/media — Нирвана; если нужны оба, может использоваться Lobby. Proactive режим не должен превращаться в спам.

---

# 19. Минимальная модель данных

```text
Conversation:
id, employeeId, mode(zane|nirvana|lobby), title,
createdAt, updatedAt, wesiAiTier(fast|pro|maximum),
summaryVersion, memoryPolicy

Message:
id, conversationId, author(user|zane|nirvana|system|tool),
kind(text|image|video|audio|file|action|error),
createdAt, replyToId?, content, attachments[], toolCallId?, toolResultId?
```

Сохранённый organization id — только UX-context. Реальные permissions вычисляются заново на каждый tool call.

---

# 20. Failure semantics

ActionResult различает минимум: `success`, `forbidden`, `confirmationRequired`, `validationError`, `notFound`, `conflict`, `networkFailure`, `serverFailure`, `rateLimited`, `cancelled`. Persona формирует ответ после фактического результата и не выдумывает успешное выполнение.

---

# 21. Acceptance criteria первой полноценной версии

1. Два сотрудника не видят AI-чаты/память друг друга.
2. Зейн и Нирвана стабильно держат Persona Bible.
3. Ни UI для сотрудника, ни persona не раскрывают underlying provider/model names.
4. Уровни `Быстрый / Pro / Максимальный` общие для обеих persona.
5. Несколько чатов переживают restart.
6. Основной сервер не хранит обычную локальную историю после request.
7. Важный разговор можно явно сохранить как backup.
8. Чаты/память можно безопасно передать device-to-device в одной локальной сети.
9. AI-трафик идёт Client → Main Wesi Server → Foreign Relay → Provider и обратно.
10. Provider keys отсутствуют в клиенте.
11. Streaming работает.
12. AI анализирует реальные разрешённые Treasury/Horizon данные.
13. AI реально выполняет разрешённые WesiOS actions.
14. Запрещённый action физически блокируется Action Broker/backend.
15. Revoke прав действует на следующий tool call даже в старом чате.
16. Organization isolation применяется к reads и writes.
17. AI не говорит «готово» без success.
18. Handoff сохраняет рабочий контекст.
19. Lobby показывает две отдельные личности и ограничивает turns.
20. Inline image generation/editing работает.
21. Video jobs восстанавливаются после restart.
22. Audit фиксирует реальные AI actions.
23. Prompt injection не расширяет права/tools.
24. `flutter analyze` и relevant tests зелёные.

---

# 22. Текущий статус реализации

Обозначения: `[DONE MAIN]`, `[PROTOTYPE]`, `[PARTIAL]`, `[TODO]`, `[BLOCKED]`.

## Уже есть

- `[DONE MAIN]` Persona Bible Зейна и Нирваны.
- `[DONE MAIN]` `docs/WESI_AI_GATEWAY.md` с Main Server → Foreign Relay архитектурой.
- `[DONE MAIN]` Wesi AI smart task subsystem: suggestions, templates, task engine/service, adaptive policy, strategic planner, fact finder, финансовые/Horizon signals, workload/skills integration.
- `[DONE MAIN]` Organization/access infrastructure как будущий security boundary AI tools.
- `[DONE MAIN]` Treasury/Horizon/CRM/Tasks/Knowledge/Audio Vault и другие WesiOS-модули для будущих tool adapters.
- `[DONE MAIN]` Старый `ai_assistant_screen.dart` существует, но это historical stub, не финальный Wesi AI UI.

## Прототипы

В исторической ветке `chatgpt/wesi-ai-foundation` есть ранние domain/persona/provider/router/gateway/inline-generation наработки. Использовать только после сверки с этим ТЗ и актуальным `main`.

## TODO

- `[TODO]` Новый Wesi AI chat shell и local storage с employee isolation.
- `[TODO]` Wi-Fi device-to-device transfer и explicit important-chat backup.
- `[TODO]` Production Main Wesi AI server orchestration и transport-only Foreign Relay.
- `[TODO]` Persona Engine / PromptComposer / Output Guard.
- `[TODO]` Wesi AI tier router: Быстрый / Pro / Максимальный.
- `[TODO]` Streaming, ContextBuilder, summaries, shared + persona memory.
- `[TODO]` Handoff и Lobby orchestrator.
- `[TODO]` Image generation/editing, video jobs, full multimodal timeline.
- `[TODO]` Capability Registry / Read Tools / Action Broker / WesiOS adapters.
- `[TODO]` AI action audit / Risk Policy / Proactive insights.
- `[TODO]` Isolation, revoke, prompt-injection, transfer и end-to-end tests.

---

# 23. Рекомендуемый порядок разработки

**Phase A:** local chat foundation — domain models, local storage, employee isolation, новый UI, multiple chats.

**Phase B:** Main Server + Relay + personas — server orchestration, Persona Engine, Wesi AI tiers, streaming, transport-only Relay.

**Phase C:** context/memory/transfer — ContextBuilder, summaries, shared/persona memory, important-chat backup, Wi-Fi D2D transfer.

**Phase D:** WesiOS tools — Capability Registry, permission-aware reads, Action Broker, Tasks first, затем Treasury/Horizon/CRM/Calendar/Knowledge/Organizations, audit/risk.

**Phase E:** multi-agent — handoff, Lobby, turn/cost limits.

**Phase F:** media — image generation/editing, artifacts, video jobs.

**Phase G:** proactive + hardening — proactive insights, prompt-injection, permission/revoke, provider outage/quota, performance/security/release tests.

---

# 24. Журнал разработки

| Дата | Статус | Изменение |
|---|---|---|
| 2026-08-05 | DONE | Первичная серверная граница Wesi AI |
| 2026-08-12 | DONE | Smart task suggestions v1 |
| 2026-08-13 | DONE | Adaptive learning / strategic signals / skills & workload integration |
| 2026-08-13 | DONE | Persona Bible Зейна и Нирваны из PDF v2.0 |
| 2026-08-13 | SPEC | Main Wesi Server → Foreign AI Relay → providers |
| 2026-08-13 | SPEC | Local-first context, shared+persona memory, permission-aware reads/writes, multi-step actions |
| 2026-08-13 | SPEC | Wesi AI Быстрый / Pro / Максимальный; underlying models скрыты от сотрудников |
| 2026-08-13 | SPEC | Wi-Fi D2D transfer, owner-selected persona, consent handoff, context-driven Lobby |
| 2026-08-13 | SPEC | Все решения консолидированы в единый authoritative документ |

---

# 25. Нельзя потерять

- Зейн и Нирвана — продукт; underlying models скрыты от сотрудников.
- Характеры берутся из Persona Bible и не зависят от внутреннего route.
- Каждый сотрудник имеет отдельные чаты и память.
- Обычная история local-first; сервер получает context package на request и не хранит его постоянно.
- Shared memory доступна обоим, плюс отдельная память каждой persona.
- Важные разговоры можно явно сохранить как backup.
- Перенос между двумя устройствами — прямой защищённый Wi-Fi/LAN transfer.
- Основной сервер — интеллект и WesiOS orchestration; зарубежный сервер — только Relay.
- Пользователь видит только Wesi AI Быстрый / Pro / Максимальный.
- Максимальный не обязан тратить тяжёлый route на тривиальные сообщения.
- Пользователь сначала сам выбирает Зейна или Нирвану.
- Handoff предлагается по специализации и выполняется после согласия.
- Если нужны оба — Lobby; режимы «Оба отвечают» и «Умное Lobby».
- AI автоматически читает разрешённые данные для ответа.
- Обычные разрешённые write-actions выполняются без лишнего повторного подтверждения.
- Multi-step работа поддерживается; значимые пакеты действий сначала показываются пользователю.
- AI имеет ровно права текущего сотрудника; permissions проверяются кодом при каждом tool call.
- При недостатке прав AI предлагает разрешённую альтернативу.
- Изображения и видео создаются inline.
- Proactive AI настраивается для каждого сотрудника.
- Любое реальное действие подтверждается фактическим ActionResult и попадает в audit.
