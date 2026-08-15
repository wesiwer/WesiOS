# Wesi AI — Implementation Status / Agent Handoff

**Дата актуализации:** 2026-08-15  
**Функциональная база:** `main` после Stage 8 merge `4fca3101927d4686e365aaf33530786ea7345b82` + последующие docs-only updates.  
**Источник требований:** `docs/WESI_AI_MASTER_SPEC.md` и связанные обязательные Wesi AI specs/addenda.  
**Правило:** этот файл фиксирует только фактически реализованное и проверенное состояние. Целевые возможности остаются в Master Spec.

## Читать следующему агенту в таком порядке

1. `WESI_AI_AGENT_HANDOFF.md` — краткая точка продолжения и запреты.
2. `WESI_AI_STAGE_TRACKER.md` — фактические DONE/NEXT/TODO этапы.
3. Этот файл — подробная инвентаризация реализованного.
4. `WESI_AI_MASTER_SPEC.md` + профильный spec текущего этапа.

**Ключевой статус:** этапы **1–8/16 уже DONE и находятся в `main`**. Следующая работа — **Stage 9/16: Self-debug loop + validated artifact creation/build delivery**.

---

# 1. Базовый Wesi AI, существовавший до Stage 1

До нового 16-этапного агентного плана в `main` уже были реализованы и используются:

- отдельные persona-чаты Зейна и Нирваны;
- Lobby;
- несколько локальных AI-чатов с employee isolation;
- Hive persistence/recovery локального AI state;
- AI Projects: несколько чатов в проекте, «Без проекта», создание/переименование/закрепление/удаление, описание и инструкции проекта, перенос чата;
- сохранение `projectId` при explicit handoff Зейн ↔ Нирвана;
- conversation-first AI UI/sidebar/projects/composer;
- классический/думающий UI-режим без раскрытия скрытого chain-of-thought;
- embedded camera внутри WesiOS;
- Universal Attachments до 4 файлов;
- inline transport до 15 MiB на файл / 18 MiB суммарно;
- staged upload до 256 MiB на файл / 512 MiB на сообщение, chunks по 1 MiB;
- path-backed picker для больших файлов без обязательного чтения всего файла в RAM;
- Relay staged storage с owner-scoped metadata, bounded assembly/cleanup/capacity protection;
- bounded text/archive extraction;
- большие image/audio/video/PDF через provider file path;
- attachment retry и cleanup временных/provider files;
- voice dictation/hands-free conversation foundation и TTS integrations;
- rich response blocks для структурированных ответов/таблиц/графиков/media metadata;
- explicit persona handoff между отдельными чатами;
- media-engine framework/manifest/downloader/verification foundation.

Крупный baseline `Projects + Camera + AI client hardening + Large Attachments` был влит через PR #153, main `3c126b156a5a36b3d5a609fb22334879e91d4855`.

---

# 2. Stage 1/16 — Smart Queue — DONE

**PR:** #163  
**Main:** `0d138773c4692fbb55b504cd3e635a7c01492540`

Реализовано:

- intent-aware очередь вместо тупого FIFO;
- приоритет `CONTROL > STEER > DEFERRED`;
- текстовые команды «стой/стоп/отмени» немедленно прерывают текущий turn;
- кнопочный Stop использует тот же механизм;
- correction/steer применяется к текущей работе немедленно;
- отложенные follow-up остаются в очереди;
- queued turns после correction переоцениваются;
- устаревшие запросы помечаются `superseded`, а не исполняются вслепую;
- restart-safe durable outbox;
- безопасный inflight recovery без повторения потенциальных side effects;
- reattach semantics для файлов после process restart;
- закрытие AI-экрана само по себе не эквивалентно Stop;
- принятая лёгкая работа может завершиться после ухода с экрана;
- lifecycle/dispose regressions закрыты.

Проверено: full analyze/test, Android debug, Windows release — green.

---

# 3. Stage 2/16 — True Network Streaming — DONE

**PR:** #164  
**Main:** `b58a73bb59b60297f1fb44df20b66a1c1426483c`

Реализовано:

- настоящий streaming provider → Relay → Main Stream Gateway → WesiOS;
- NDJSON stream contract для клиента;
- Main остаётся policy/tool boundary, клиент не ходит напрямую к Relay/provider;
- tool-loop защищён на Main side;
- Stop/Steer отменяет transport;
- partial response обновляет один assistant-message;
- partial tokens не пишутся по одному в Hive;
- финальный ответ persist-ится один раз целиком;
- stale late deltas после Stop/Steer игнорируются;
- nginx buffering отключён для stream endpoint;
- старый JSON chat path сохранён как rollback/fallback;
- streaming gateway/server regressions добавлены.

Проверено: server/Relay/Main tests, full Flutter analyze/test, Android debug, Windows release — green.

**Важно:** production streaming deploy автоматически не запускался.

---

# 4. Stage 3/16 — Local-first Memory Engine — DONE

**PR:** #165  
**Main:** `fddc5e52d27cb931f5cbdc22f42742c9d96a2524`

Реализовано:

- memory schema v3;
- безопасная миграция legacy `shared/zane/nirvana` памяти;
- отдельные scopes: shared, Zane, Nirvana, project;
- rolling conversation summaries;
- per-chat `taskState`;
- relevance retrieval вместо безусловной передачи всей памяти;
- background memory extraction;
- secret filtering;
- deduplication/caps;
- failure isolation memory processor-а от основного чата;
- user memory controls;
- project context, conversation summary и task state передаются раздельно;
- уже суммаризированная старая история не продолжает бесконечно отправляться как raw context.

Проверено: full analyze/test, Android debug, Windows release — green.

---

# 5. Stage 4/16 — Important Backup + encrypted LAN/Wi-Fi D2D — DONE

**PR:** #166  
**Main:** `6d929fbe9eb018e310de0479d42ed4e4e9e876ba`

Реализовано:

- explicit «важный разговор» backup;
- versioned `.wbackup` container;
- AES-256-GCM encryption;
- PBKDF2 для password-derived key;
- encrypted D2D session с отдельным случайным 256-bit key;
- HMAC/session authentication, TTL/fingerprint/one-shot semantics;
- raw TCP D2D вместо Android cleartext HTTP exception;
- private-address LAN policy;
- единый package format для backup и D2D;
- employee isolation при restore;
- idempotent merge;
- memory/chat/project/artifact restore;
- managed artifact paths;
- bounded ZIP preflight до распаковки;
- duplicate-entry, declared-size, suspicious compression, unsupported encryption/ZIP64 hardening;
- artifact integrity checks;
- UI управления backup/D2D.

Проверено: focused crypto/package/D2D + memory/queue regressions, full PR analyze/test, Android debug, Windows release — green.

---

# 6. Stage 5/16 — Capability Registry / Action Broker / Risk / Audit + WesiOS tools — DONE

**PR:** #167  
**Main:** `93a8b23c97a9913b505d1db3b8df5ced56c86373`

Реализовано:

- единый fail-closed Capability Registry;
- единый Action Broker перед server-side tool execution;
- risk classes: READ / WRITE / DESTRUCTIVE;
- destructive action нельзя подтвердить model-generated `confirmed=true`;
- одноразовый destructive confirmation ticket;
- ticket привязан к employee + конкретной auth-session + args + TTL;
- повторное подтверждение/replay отклоняется;
- permission/risk re-check при фактическом подтверждении;
- verified client confirmation UI;
- unified metadata audit без утечки секретных args;
- одинаковый broker path для обычного JSON и streaming tool execution;
- Horizon/Workspace/tool registry приведены к единому runtime;
- реальные brokered read/write actions для Tasks, Calendar, Treasury, CRM, Knowledge, Roadmap, Audio Vault и Team context;
- серверные capabilities не выдумываются для device-local Notifications.

Проверено: server policy/action broker tests, streaming path, full Flutter analyze/test, Android debug, Windows release — green.

---

# 7. Stage 6/16 — Controlled Wesi Local Runtime — DONE

**PR:** #168  
**Main:** `e626469de2164bbd68e1c7c5db11e10536eca93d`

Реализовано:

- typed Local Runtime API вместо передачи модели произвольной raw shell-строки;
- filesystem tools;
- terminal/process bindings;
- Git;
- HTTP;
- Python;
- Node;
- Flutter/analyze/test/build bindings;
- document/media bindings foundation;
- isolated workspace root;
- traversal/symlink escape protection;
- internal `.wesi` state закрыт от AI file tools;
- sanitized process environment, без автоматического наследования host secrets;
- HTTP SSRF protection;
- DNS/IP verification/pinning, включая private/loopback/mapped-address hardening;
- destructive local file operations требуют external confirmation boundary;
- metadata-only audit;
- versioned `workspaceV1` sandbox contract;
- executable binding нельзя считать sandboxed только из-за boolean-флага;
- `workspaceV1` означает обязательный OS-level isolation contract: workspace isolation + CPU/RAM/disk/time limits + controlled network + отсутствие host secrets.

Проверено: focused security regressions, full PR analyze/test, Android debug, Windows release — green.

---

# 8. Stage 7/16 — Environment Scanner + Runtime Packs — DONE

**PR:** #169  
**Main:** `538f5cd092de6538a42a9aa84938c4e255d46a3b`

Реализовано:

- verified Environment Scanner;
- Runtime Packs: Core, Developer, Browser, Documents, Media;
- reuse системных инструментов только по absolute PATH;
- relative PATH components не считаются доверенным runtime;
- версии/пути/capabilities проверяются scanner-ом;
- signed runtime artifact descriptor;
- Ed25519 verification через поддерживаемый crypto API;
- signed payload включает URL/size/SHA и trust-critical metadata;
- tampered descriptor отклоняется;
- bounded download/extraction;
- managed install roots;
- atomic install/swap;
- rollback сохраняет предыдущий рабочий pack при failure;
- post-install rescan обязателен;
- pack не активируется только потому, что файлы были скачаны;
- `workspaceV1` activation требует verified `wesi-sandbox` prerequisite;
- model не может объявить pack доверенным сама.

Проверено: focused Stage 6/7 security suite, включая Ed25519 tamper, PATH и rollback regressions; full PR analyze/test, Android debug, Windows release — green.

---

# 9. Stage 8/16 — Adaptive Resource Scheduler + Durable Jobs — DONE

**PR:** #170  
**Validated PR head:** `f9bd4e28dc8b88363a4025c8ea0d4231f48432bb`  
**Main:** `4fca3101927d4686e365aaf33530786ea7345b82`

Реализовано:

## Adaptive L0–L4

- L0 Chat — без Local Runtime;
- L1 Simple Action;
- L2 Assisted Task;
- L3 Complex Agent Task;
- L4 Heavy Runtime;
- trusted workload registry для известных Stage-6 tools;
- trusted caller может только ужесточать требования, но не понижать их;
- build классифицируется как L4;
- длительность/RAM/VRAM/build/browser/media/large-file/self-debug complexity могут эскалировать уровень.

## Worker/resource facts

Scheduler учитывает:

- platform;
- worker role: local / future remote / Control Plane;
- trust/policy state;
- online/busy/paused;
- verified Stage-6 capabilities;
- verified Stage-7 Runtime Packs;
- CPU cores + current CPU load;
- total/available RAM;
- GPU + total/free VRAM;
- free disk;
- thermal state;
- power mode;
- foreground/background availability;
- active light/CPU/heavy/GPU job counters.

Invalid telemetry fail-closed.

## Heavy-task / server policy

- L3/L4 требуют фактический execution worker в foreground/available состоянии;
- `backgroundExecutionAllowed=true` не отменяет foreground requirement для L3/L4;
- основной VPS/Control Plane не используется как fallback heavy-compute worker;
- если heavy worker недоступен, задача не уезжает на VPS;
- будущий remote worker может быть кандидатом только после Stage 10 authenticated live-state integration.

## Resource/concurrency

- решения по RAM используют **available RAM**, а не просто установленный объём;
- GPU решения используют **free VRAM**;
- reserve headroom для RAM/VRAM/disk;
- CPU load участвует в фильтрации/оценке;
- thermal/power policy;
- отдельные light/CPU/heavy/GPU concurrency slots;
- heavy/GPU jobs не конкурируют бесконтрольно с CPU-heavy jobs.

## Durable jobs/checkpoints

- `WesiDurableJobQueue` с schema-versioned bounded journal;
- strict state transitions;
- `queued -> running -> succeeded/failed`;
- pauseRequested/paused/resume;
- `waitingForWorker`;
- cancelling/cancelled;
- blocked → queued после снятия blocker;
- checkpoint перед безопасным pause/worker-loss там, где workload checkpointable;
- progress monotonic;
- unknown persisted enums/capabilities fail-closed;
- persisted requirements повторно валидируются против trusted workload registry;
- persisted job не может downgrade L-level/capabilities/packs/resources/foreground requirement;
- restore failure не уничтожает предыдущий valid in-memory snapshot;
- enqueue/state mutation rollback при persistence failure;
- journal size/event/job caps;
- same-directory temp + rollback backup;
- backup recovery после interrupted swap.

## Coordinator integration

- фактический `WesiJobCoordinator` переведён на `WesiDurableJobQueue`;
- нет второй параллельной in-memory очереди как источника истины;
- path `queue → scheduler → dispatch → checkpoint → waitingForWorker → resume` покрыт integration regression.

Проверено: focused Stage 6/7/8 tests, scheduler/job/coordinator integration, full PR analyze/test, Android debug, Windows release — green.

**Production deploy/release не запускался.**

---

# 10. Что НЕ сделано и является следующим планом

## Stage 9/16 — NEXT — Self-debug + validated artifacts

Это следующая задача. Нужно построить агентный execution loop поверх уже готовых Stage 6–8, а не создавать новый обходной runtime.

Минимальный обязательный цикл:

`plan -> execute typed tools -> capture bounded result -> diagnose -> repair -> validate -> retry -> build/test -> artifact validation -> deliver`

Нужно реализовать:

- durable self-debug job type;
- plan/step state внутри Stage-8 job/checkpoint lifecycle;
- bounded iteration budget;
- timeout/cancel/pause/resume;
- objective success criteria вместо model-declared success;
- analyze/test/build gates;
- capture stdout/stderr в bounded/redacted форме;
- failure classification;
- repair iteration;
- запрет бесконечного цикла;
- explicit blocker when progress objectively impossible;
- artifact registry/result model;
- validated export/delivery для документов/архивов/source/build outputs, которые реально поддерживает текущий runtime;
- APK/Windows build artifact validation;
- не объявлять artifact готовым, пока файл не существует и не прошёл соответствующую проверку;
- использовать Scheduler для выбора execution target и Stage-7 verified bindings/packs;
- L3/L4 foreground/worker-loss policy сохраняется.

**Не надо в Stage 9:** QR Remote Worker transport, connectors, Co-Agent/subagents — это следующие этапы.

## Stage 10/16 — Remote Worker

Ещё не сделано:

- QR pairing;
- device credentials/revoke;
- heartbeat;
- authenticated capabilities/resources;
- online/offline/busy state;
- remote job transport;
- reconnect/resume;
- progress/log/result transport;
- ownership/replay protection;
- реальное подключение authenticated remote worker facts к Stage-8 Scheduler.

## Stage 11/16 — Connectors

Ещё не сделано как production agent layer:

- GitHub production connector/runtime integration;
- затем Drive/Gmail/Google Calendar/Slack/Telegram/GitLab/Notion/Jira/OneDrive/Dropbox по фактически доступным API;
- connector secrets должны оставаться вне model context;
- connector actions должны проходить capability/risk/audit boundary.

Старый PR #147/#149 можно использовать только как historical reference, не как готовую merge-базу.

## Stage 12/16 — Persona Lead/Co-Agent

Сейчас есть explicit handoff между отдельными persona chats, но ещё нет целевого internal Co-Agent runtime.

Нужно:

- Lead Persona;
- автоматическое решение о привлечении второй persona;
- typed internal handoff;
- ограниченный context/tool scope;
- structured result;
- accept/reject/revision;
- mutual review;
- Joint Integration;
- пользователь остаётся в исходном чате.

## Stage 13/16 — Dynamic Subagents + multi-agent workspace

Не сделано:

- временные специалисты;
- scoped context/tools;
- subagent budgets;
- max parallel subagents;
- cleanup;
- file ownership/locks;
- branch-like staging;
- provenance/diff;
- conflict detection;
- integration/validation после объединения.

## Stage 14/16 — Full Media Engines/workflows

Framework уже существует, но production media workflows не закрыты.

Нужно:

- реальные production model packs;
- image editing/reference workflows;
- music generation + stems;
- regenerate отдельного stem;
- mix/master/export;
- video generation/composition;
- voice/music/SFX/subtitles;
- FFmpeg validation;
- progress/cancel/retry;
- resource scheduling через Stage 8.

## Stage 15/16 — Proactive / Budget / Security hardening

Нужно:

- proactive insights;
- per-employee enable/categories/threshold/quiet hours/channels;
- anti-spam;
- token/API/media/heavy-job/subagent budgets;
- quota manager;
- prompt-injection tests через attachments/Knowledge/CRM/web/connectors;
- cross-org/cross-employee security;
- permission revoke during old conversations/jobs;
- secret exfiltration tests;
- destructive/mass-action safety expansion.

## Stage 16/16 — Final autonomous E2E + production activation

Нужно доказать реальные сценарии, например:

- GitHub → найти build failure → исправить → analyze/test → Android/Windows build → PR → APK;
- «сделай приложение» → plan → tools → self-debug → build → artifact;
- документы/таблицы → настоящий validated PDF/DOCX/XLSX/PPTX;
- heavy task с телефона без worker → не грузить VPS, а перейти `waitingForWorker`;
- media workflow с частичной перегенерацией;
- production server/Relay/DNS/TLS E2E;
- final signed release gates.

---

# 11. Внешний production/server blocker

Серверная/DNS активация ведётся отдельно от agent-runtime разработки.

Исторически `ai.wesi-wf.su` не считался production-ready из-за внешней DNS/TLS доступности. Последний фактический ответ от внешней стороны/production verification в этой работе не получен, поэтому **не считать blocker автоматически снятым**.

Когда инфраструктура будет доступна, отдельно выполнить:

1. authoritative/public DNS verification;
2. TLS certificate verification;
3. `https://ai.wesi-wf.su/health`;
4. Main → Relay signed path;
5. реальные Fast/Pro/Maximum text smoke-tests;
6. attachment smoke-tests;
7. streaming smoke-test;
8. retry/error UX;
9. load/resource checks.

**Главное правило:** проблемы production Relay/DNS не дают права переносить L3/L4 heavy workloads на основной VPS.

---

# 12. Жёсткие правила для следующего агента

1. **Не переделывать Stage 1–8**, если нет конкретного воспроизводимого regression.
2. Работать от актуального `main`.
3. Следующая рабочая ветка должна быть Stage 9, а не старый PR #149.
4. Старые PR #147/#149 использовать только как reference; не мержить их stacked history поверх новой архитектуры.
5. Все execution действия Stage 9 должны проходить через Stage-6 typed Local Runtime.
6. Runtime binding должен быть verified Stage-7 Environment Scanner/Runtime Pack layer; model-provided executable paths не доверять.
7. Worker/ресурсный выбор — только Stage-8 Scheduler.
8. L3/L4 не исполнять на Control Plane/VPS fallback.
9. Worker loss для heavy work: checkpoint → `waitingForWorker` → resume; не скрытая миграция на сервер.
10. Не запускать production release/deploy без отдельного явного запроса.
11. `DONE` ставить только после focused tests + full repository gate + Android debug + Windows release + merge в `main`.
12. После каждого merge обновлять `WESI_AI_STAGE_TRACKER.md`, этот status-файл и `WESI_AI_AGENT_HANDOFF.md`.
