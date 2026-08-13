# WesiOS / Wesi AI — журнал фактически выполненных работ

> Зафиксировано: 14 августа 2026, около 01:07 MSK.
>
> Назначение файла: сохранить точный технический handoff по уже выполненным изменениям, проверкам, merge/release-контексту и незавершённым пунктам. Этот документ не заменяет `docs/WESI_AI_SPEC.md`; он фиксирует фактическое состояние реализации на момент записи.

---

## 1. Предшествующая интеграция Team Skills / Workload

Перед текущим этапом Wesi AI была завершена безопасная интеграция навыков сотрудников и контроля нагрузки из старой сильно разошедшейся org-ветки в актуальный `main`.

Что было сделано:

- не выполнялся слепой merge старой `agent/org-hierarchy-v1`, потому что она сильно разошлась с актуальным `main` и содержала старые версии большого числа подсистем;
- из проверенной feature-ветки были перенесены только актуальные части employee skills/workload;
- интегрированы изменения в:
  - `lib/features/team/models/employee_model.dart`;
  - `lib/features/team/models/employee_model.g.dart`;
  - `lib/features/team/employee_editor_screen.dart`;
  - `lib/features/team/services/team_service.dart`;
  - `lib/features/team/services/team_skill_service.dart`;
  - `lib/features/team/services/team_workload_service.dart`;
  - `test/team_skills_workload_test.dart`;
- старая Wesi AI/org-обвязка из той ветки намеренно не переносилась целиком, чтобы не затереть более новый production-код.

Исправлена несовместимость старого `TeamWorkloadService` с текущим `TaskModel`:

- убраны обращения к устаревшим `responsibleEmployeeId`, `isCompleted`, `completedAt`;
- назначение теперь сопоставляется через текущий `task.assignee` и id/login/displayName сотрудника;
- завершение определяется через `task.status == TaskStatus.completed`;
- логика перегрузки сохранена через `maxConcurrentTasks` и `workloadAlertThreshold`;
- маршрут уведомления остаётся: прямой руководитель, а при его отсутствии/неактивности/самоссылке — CEO.

PR #128 был интегрирован в `main` как `feat: employee skills and workload`.

Версия приложения была поднята до `0.20.0+73`, чтобы не нарушить монотонность Android `versionCode` после предыдущих production-релизов.

### Релизный контекст той интеграции

Был запущен production release pipeline.

- Windows release build прошёл успешно и был опубликован в `app-latest`.
- Android release APK был успешно собран и подписан постоянным release-keystore.
- Первый Android publish упал не на сборке/подписи, а на `gh release upload --clobber` с HTTP 404 из-за race condition: Windows и Android jobs одновременно публиковали assets в один постоянный GitHub Release `app-latest`.
- Android job был перезапущен отдельно после завершения Windows, чтобы убрать конкурирующую публикацию.
- Причина race condition зафиксирована: оба platform jobs зависят только от `version` и параллельно выполняют `gh release upload ... --clobber` в один release.
- Предпочтительное постоянное решение: build jobs только создают Actions artifacts, а отдельный publish job после обеих сборок последовательно загружает release assets. Упрощённый вариант — сериализовать Android после Windows.

---

# 2. Wesi AI — клиентская основа

Был создан и проверен новый production-контур Wesi AI вместо исторической заглушки.

Реализовано:

- доменная модель чатов Wesi AI;
- `WesiAiPersona`: `zane`, `nirvana`, `lobby`;
- фирменные уровни `WesiAiTier`: `fast`, `pro`, `maximum`;
- отдельные авторы сообщений: `user`, `zane`, `nirvana`, `system`, `tool`;
- типы timeline: text/image/video/audio/file/action/status/error;
- локальные conversation metadata и messages;
- shared memory + отдельная память Зейна + отдельная память Нирваны;
- local-first chat store с привязкой к `employeeId`;
- несколько отдельных чатов;
- выбор Зейна / Нирваны / Lobby;
- уровни в UI показываются только как `Wesi AI Быстрый / Pro / Максимальный`;
- клиент не получает provider credentials и не выбирает внешний provider/model;
- клиентский API работает через существующую WesiOS session (`Authorization` + `X-WesiOS-Session`) к основному серверу Wesi;
- в AI request передаётся `conversationId` и выбранная активная организация как UX-context.

Клиентский этап был проверен CI и интегрирован в `main` до следующих security/tool этапов.

---

# 3. Main Server → Foreign Relay архитектура

В production-коде закреплена архитектурная граница:

```text
WesiOS client
  -> Main Wesi Server
  -> Foreign Wesi AI Relay
  -> provider
  -> Foreign Relay
  -> Main Wesi Server
  -> WesiOS client
```

Основной сервер остаётся местом, где выполняются:

- WesiOS auth/session validation;
- employee identity resolution;
- module access;
- organization scope;
- persona/context composition;
- WesiOS tools;
- Action Broker;
- permission checks;
- verified tool results;
- audit.

Foreign Relay остаётся transport/provider слоем и не получает права решать WesiOS permissions или читать Treasury/Tasks напрямую.

Relay-запросы Main → Relay подписываются HMAC и содержат request id + timestamp. Relay валидирует свежесть и подпись.

---

# 4. Persona Engine / память

На сервере подключён runtime Persona Bundle для Зейна и Нирваны.

Важный security/correctness инвариант:

- Зейн получает `shared memory + zane memory`;
- Нирвана получает `shared memory + nirvana memory`;
- память одной persona не должна автоматически попадать другой;
- Lobby может использовать обе памяти, но отдельные persona turns должны получать только свою persona-memory плюс shared memory.

Persona Bible остаётся product/prompt layer, а не security boundary. Права всегда задаются кодом WesiOS.

---

# 5. Permission-aware Action Broker — Tasks

PR #135: `feat: add permission-aware Wesi AI task tools`.

Merge commit в `main`: `04ed4c70fe9e920b780996d0df370dd9d60fc127`.

Реализованы первые реальные WesiOS tools:

- `tasks_list` — чтение задач только в разрешённом scope;
- `tasks_create` — создание реальной WesiOS task через серверный слой.

Принципы:

- модель не пишет в БД напрямую;
- модель только просит вызвать tool;
- сервер заново вычисляет identity, permissions и organization scope;
- результат действия считается выполненным только после verified server result;
- при `FORBIDDEN` persona должна объяснить отказ и предложить разрешённую альтернативу.

### Исправленный permission boundary

Была обнаружена потенциально слишком широкая AI-политика чтения задач.

`canSeeOthersStats` не является правом читать чужие задачи в серверной sync-политике. Поэтому Wesi AI приведён к той же границе:

- `canSeeOthersStats` сам по себе **не** открывает чужие tasks;
- owner / `canManageTeam` / `canAssignTasks` следуют серверной task-policy;
- `canAssignTasks` позволяет командный task scope и создание задачи другому сотруднику;
- без `canAssignTasks` назначение задачи другому физически блокируется сервером.

Добавлены policy-тесты на эти случаи.

---

# 6. AI Action Audit

Добавлен server-side audit-модуль для AI действий.

Для write-попыток фиксируются успешные и запрещённые вызовы. Audit активен в PocketBase runtime и не требует эмуляции PocketBase storage в чистом Node unit runtime.

Цель audit: сохранять фактическую попытку/результат действия, а не доверять тексту модели.

---

# 7. Active Organization Context

PR #136: `fix: pass active organization to Wesi AI`.

Merge commit/head: `31fd6c6b19298e37c3f5b7a23bd46c43ad4de5f9`.

Клиент теперь передаёт в AI-request:

- `conversationId`;
- текущую выбранную организацию.

Важно: active organization — только UX-context. Она **не является правом**.

Main Server всё равно повторно проверяет, разрешена ли эта организация текущему сотруднику и какие grants действуют.

Это закрывает проблему owner/multi-org сценария, где сервер раньше мог временно выбирать root/первую разрешённую организацию вместо реально выбранной пользователем.

---

# 8. Capability Registry — разделение адаптеров

Общий Wesi AI tools registry был разделён на адаптеры, чтобы не превращать один файл в монолит:

- Task adapter;
- Finance adapter;
- общий Capability Registry, который агрегирует определения/context/execute.

Во время рефакторинга обнаружен Node test-runtime дефект: registry ожидал PocketBase `__hooks` в изолированном Node test process.

Исправлено тестовым bootstrap/loader-подходом без изменения business/security logic.

---

# 9. Permission-aware Finance Read Tools

PR #137: `feat: add permission-aware Wesi AI finance analysis`.

PR полностью проверен и интегрирован в `main`.

Текущий `main` после этого этапа: `af147087c7883da0db33456cf214d8ce8ec578c7`.

Реализован серверный read-only финансовый контур:

- обязательное право `view_finance`;
- organization grants;
- subtree-grants работают только вниз по иерархии;
- финансовые строки сначала фильтруются Main Server по разрешённой организации;
- затем Main Server сам вычисляет агрегаты;
- только verified структурированный результат передаётся модели;
- модель не получает чужие финансовые записи «на всякий случай».

Проверены расчёты и policy:

- `view_finance` обязателен даже если UI-модуль финансов видим;
- чужая организация не попадает в расчёт;
- subtree grant разрешает child organization, но не parent;
- summary считается на Main Server только из уже авторизованных rows.

Finance milestone прошёл:

- server JS syntax check;
- Wesi AI Relay tests;
- persona bundle validation;
- `flutter analyze`;
- полный `flutter test`;
- Windows build;
- Android debug build.

---

# 10. Настоящий Lobby — текущая незавершённая ветка

PR #138: `feat: Wesi AI Lobby orchestrator`.

Ветка: `chatgpt/wesi-ai-lobby-v1`.

Head на момент записи: `daff7e62033606c96c559402760311e3c9098260`.

Статус PR на момент записи:

- open;
- draft;
- mergeable;
- **ещё не merged**.

### Что уже реализовано в PR #138

До этого Lobby фактически был одним смешанным prompt с `[ZANE] + [NIRVANA]`, то есть не двумя реальными агентными репликами.

Сейчас сделан настоящий server-side Lobby orchestrator:

- Зейн и Нирвана вызываются как отдельные persona turns;
- каждая persona получает свою Persona Bible;
- shared memory доступна обеим;
- Зейн получает только zane persona-memory;
- Нирвана получает только nirvana persona-memory;
- реплики сохраняют отдельного автора;
- участники могут видеть предыдущую реплику второго участника в текущем Lobby turn;
- есть режимы:
  - `both` — отвечают оба;
  - `smart` — Main Server сначала выбирает, кто реально нужен и в каком порядке;
- добавлены ограничения на допустимые режимы/размеры контекста;
- клиентскому transport не добавлялся второй auth-механизм: Lobby маршрутизируется через существующий WesiOS AI chat/session контур;
- добавлены Lobby response codec и отдельный Lobby controller;
- локальный timeline умеет сохранять Зейна и Нирвану отдельными сообщениями;
- старые Lobby conversations без поля режима мигрируют в `smart`;
- UI показывает автора сообщения и позволяет переключать `Умное Lobby / Оба отвечают`.

### Что проверено по Lobby

На момент записи успешно прошли:

- server JavaScript validation;
- Wesi AI Relay tests;
- Persona Bundle validation;
- `flutter analyze`;
- полный `flutter test`;
- отдельные тесты Lobby codec/migration;
- Windows release build.

Android debug build PR #138 **ещё выполняется** на момент этой записи, поэтому Lobby нельзя считать полностью завершённым или merged.

GitHub также сформировал merge-tree `57b0cb2e053047d608f869542c2b5ffc668ad596` с родителями текущего Finance `main` и Lobby head. Code/test gate на этом PR прошёл, но финальный merge должен выполняться только после успешного Android platform gate.

После зелёного Android предпочтительно перенести/влить Lobby поверх актуального `main` без потери Finance/Action Broker истории и только затем считать Phase E Lobby milestone завершённым.

---

# 11. Важные security-инварианты, которые уже соблюдаются

1. AI не получает больше прав, чем текущий сотрудник.
2. Permission check выполняется на сервере, а не в prompt.
3. Каждый tool call должен использовать свежие permissions.
4. Active organization — context, а не authorization.
5. AI не должен утверждать «готово», пока сервер не вернул verified success.
6. Provider/model names не являются пользовательской идентичностью Wesi AI.
7. Provider credentials не передаются клиенту.
8. Foreign Relay не является WesiOS authorization layer.
9. `canSeeOthersStats` не расширяет task read scope.
10. `view_finance` обязателен для финансовых AI tools.
11. Organization subtree-grant не должен расширяться вверх к parent.
12. Persona memories изолированы: Зейн не получает память Нирваны и наоборот.
13. Audit записывает реальные AI write actions/denials, а не текстовые заявления модели.

---

# 12. Что сознательно НЕ делалось

Чтобы не повредить актуальный production-код:

- не был выполнен полный merge старой `agent/org-hierarchy-v1`;
- не переносился целиком старый Wesi AI stack из исторической org-ветки;
- не добавлялись provider secrets/API keys в репозиторий или клиент;
- не делался отдельный Lobby bearer/auth-клиент; сохранена единая WesiOS session boundary;
- не объявлялся готовым Lobby до прохождения Android platform gate;
- не объявлялись готовыми streaming/media/transfer/handoff/Horizon tools, если они ещё не реализованы полностью.

---

# 13. Что осталось сделать дальше

Приоритетный порядок продолжения:

1. Дождаться зелёного Android build PR #138.
2. Влить Lobby в актуальный `main` без потери Finance/Tasks изменений.
3. Обновить authoritative `docs/WESI_AI_SPEC.md`: фактически Phase A, значительная часть B, часть D и Lobby из Phase E уже реализованы, а текущий статус-файл там устарел.
4. Доделать полноценный Horizon read-tool с `view_forecast + view_finance`, используя реальные серверные данные/результаты Horizon, а не сырой prompt dump.
5. Добавить остальные permission-aware read/write adapters: CRM, Calendar, Knowledge, Organizations и т.д.
6. Сделать handoff между Зейном и Нирваной с передачей цель/summary/ограничения/context package после согласия пользователя.
7. Реализовать streaming + stop/retry/regenerate.
8. Доделать ContextBuilder, rolling summaries и пользовательское управление memories.
9. Explicit important-chat backup.
10. Защищённый device-to-device Wi-Fi/LAN transfer.
11. Inline image generation/editing и artifact ownership.
12. Video jobs с `jobId`, progress/status/cancel/retry/restart recovery.
13. Risk Policy / confirmation policy для значимых multi-step write-пакетов.
14. Prompt-injection hardening и revoke/permission end-to-end tests.
15. Proactive Wesi AI.
16. Production deployment/release только после полного CI/security gate соответствующего milestone.

---

# 14. Ключевые PR / commits текущего этапа

- PR #128 — employee skills/workload integration в актуальный main.
- PR #135 — permission-aware Wesi AI Task tools; merge commit `04ed4c70fe9e920b780996d0df370dd9d60fc127`.
- PR #136 — active organization + conversation context; commit `31fd6c6b19298e37c3f5b7a23bd46c43ad4de5f9`.
- PR #137 — permission-aware Finance analysis; merged; main на момент фиксации `af147087c7883da0db33456cf214d8ce8ec578c7`.
- PR #138 — настоящий Lobby orchestrator; draft/open, head `daff7e62033606c96c559402760311e3c9098260`; не считать завершённым до Android green + merge.

---

# 15. Состояние на момент записи

**В `main` уже есть:**

- employee skills/workload;
- Wesi AI client foundation/local-first chat shell;
- Persona Bundle/runtime;
- Main Server → Foreign Relay контур;
- фирменные tiers;
- permission-aware Task read/create tools;
- AI action audit для task writes/denials;
- server-equivalent task scope;
- active organization context;
- modular Capability Registry;
- permission-aware Finance read/calculation tools;
- Finance policy/security tests.

**Ещё не в `main`:**

- настоящий multi-author Lobby из PR #138 на момент записи.

**CI PR #138 на момент записи:**

- JS/Relay/Persona: GREEN;
- `flutter analyze`: GREEN;
- full `flutter test`: GREEN;
- Windows: GREEN;
- Android: IN PROGRESS.

Этот файл должен использоваться как handoff вместе с `docs/WESI_AI_SPEC.md`, пока authoritative status-раздел в основном ТЗ не будет синхронизирован с фактической реализацией.