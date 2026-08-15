# Wesi AI — Agent Handoff

**Назначение:** этот файл — первая точка входа для следующего AI-агента, продолжающего Wesi AI.  
**Актуально на:** 2026-08-15.  
**Источник истины:** актуальный `main`, `WESI_AI_MASTER_SPEC.md`, профильные Wesi AI specs и этот handoff/status/tracker.

## 1. Где мы остановились

**Stage 1–8/16 полностью завершены, проверены и влиты в `main`.**

Последний завершённый функциональный этап:

- **Stage 8/16 — Adaptive Resource Scheduler + Durable Jobs**;
- PR #170;
- validated PR head `f9bd4e28dc8b88363a4025c8ea0d4231f48432bb`;
- main merge `4fca3101927d4686e365aaf33530786ea7345b82`;
- полный PR check, Android debug APK и Windows release build — green;
- production deploy/release не запускался.

После merge были только документационные синхронизации статуса.

## 2. Что уже есть и НЕ надо переделывать без regression

### Stage 1 — Smart Queue

- `CONTROL > STEER > DEFERRED`;
- Stop/Steer прерывают или корректируют текущую работу;
- deferred follow-ups ждут;
- superseded queue items не исполняются;
- restart-safe queue/inflight recovery.

### Stage 2 — True Streaming

- provider SSE → Relay → Main Stream Gateway → WesiOS NDJSON;
- Main остаётся policy/tool boundary;
- Stop/Steer отменяет stream transport;
- один partial assistant message + одна финальная persisted запись.

### Stage 3 — Memory Engine

- schema v3;
- shared/Zane/Nirvana/project scopes;
- rolling summaries;
- task state;
- relevance retrieval;
- background extraction;
- secret filtering/dedup/caps;
- user memory controls.

### Stage 4 — Backup + LAN D2D

- encrypted `.wbackup`;
- AES-256-GCM/PBKDF2;
- bounded ZIP preflight;
- employee-isolated idempotent restore;
- encrypted one-shot raw-TCP LAN/Wi-Fi transfer;
- artifact restore.

### Stage 5 — Capability Broker / Risk / Audit / WesiOS actions

- fail-closed Capability Registry;
- Action Broker;
- READ/WRITE/DESTRUCTIVE;
- session-bound one-time destructive confirmation ticket;
- verified confirmation UI;
- unified audit;
- brokered Tasks/Calendar/Treasury/CRM/Knowledge/Roadmap/Audio Vault/Team context.

### Stage 6 — Controlled Local Runtime

- typed filesystem/terminal/Git/HTTP/Python/Node/Flutter/build/document/media tools;
- workspace isolation;
- `.wesi` hidden from AI file calls;
- SSRF/DNS pinning;
- sanitized environment;
- versioned `workspaceV1` sandbox contract.

### Stage 7 — Environment Scanner + Runtime Packs

- verified scanner;
- Core/Developer/Browser/Documents/Media packs;
- absolute-PATH reuse only;
- Ed25519 signed descriptors;
- URL/size/SHA verification;
- bounded extraction;
- post-install rescan;
- atomic rollback;
- `workspaceV1` activation only after verified sandbox prerequisite.

### Stage 8 — Scheduler + Durable Jobs

- L0–L4 adaptive classification;
- trusted workload registry;
- CPU/RAM/VRAM/disk/thermal/power/concurrency policy;
- verified capability/Runtime Pack worker filtering;
- L3/L4 require foreground worker;
- heavy work cannot fall back to Control Plane/VPS;
- bounded durable journal;
- checkpoint/pause/resume;
- `waitingForWorker`;
- restart-safe job coordinator;
- coordinator uses durable queue as the single source of truth.

Подробности и commit/PR IDs находятся в `WESI_AI_IMPLEMENTATION_STATUS.md` и `WESI_AI_STAGE_TRACKER.md`.

## 3. Следующая работа — Stage 9/16

**Название:** Self-debug loop + validated artifact creation/build delivery.

Начинать с новой ветки от актуального `main`, например:

`agent/wesi-ai-stage9-self-debug-artifacts`

### Что Stage 9 обязан использовать

- execution только через Stage-6 typed Local Runtime;
- executable/runtime trust только через Stage-7 verified Environment Scanner / Runtime Packs;
- worker/resource routing только через Stage-8 Resource Scheduler;
- long-running lifecycle только через Stage-8 durable jobs/checkpoints;
- L3/L4 foreground requirement сохраняется;
- worker loss: checkpoint → `waitingForWorker` → resume.

### Что реализовать

1. **Self-debug job/plan model**
   - plan;
   - ordered steps;
   - current step;
   - bounded iteration count;
   - objective validation state;
   - blockers;
   - artifact outputs.

2. **Execution loop**
   - execute typed tool;
   - capture bounded/redacted stdout/stderr/result;
   - classify failure;
   - diagnose;
   - generate repair action;
   - re-run validation;
   - stop on success, hard blocker, cancellation or iteration budget.

3. **Validation**
   - `flutter analyze` / tests / build where required;
   - success determined by tool/process result and artifact verification, not model text;
   - do not report DONE while required gate is still failing.

4. **Artifact registry/delivery**
   - path must stay inside controlled workspace/artifact root;
   - file must actually exist;
   - size/type/basic integrity validation;
   - build artifacts such as APK/Windows output must be tied to successful build result;
   - documents/archives/source outputs returned as real artifacts, not descriptions.

5. **Durability**
   - checkpoint current plan/step/iteration;
   - pause/resume/cancel;
   - safe restart;
   - no duplicate irreversible step after recovery;
   - worker-loss path uses Stage-8 `waitingForWorker`.

6. **Limits/security**
   - max iterations;
   - max captured output;
   - timeout;
   - no arbitrary raw host shell path;
   - no model-provided trusted executable path;
   - no Control Plane fallback for L3/L4;
   - metadata/audit redaction preserved.

### Минимальные Stage-9 regressions

- successful analyze/test/build path;
- failure → repair → success;
- repeated failure stops at iteration budget;
- cancel stops future steps;
- pause/resume preserves checkpoint;
- worker disappears during L3/L4 → `waitingForWorker`;
- restart restores job without duplicate side effect;
- artifact missing despite model claim → job is not successful;
- build process fails → APK/EXE cannot be marked delivered;
- artifact path escape is rejected;
- oversized stdout/stderr is bounded;
- Stage 6/7/8 security regressions remain green.

## 4. Что НЕ делать в Stage 9

Не смешивать в Stage 9 следующие будущие этапы:

- QR/remote worker network transport — Stage 10;
- GitHub/Drive/Gmail/etc connectors — Stage 11;
- internal Zane/Nirvana Co-Agent runtime — Stage 12;
- dynamic subagents/multi-agent workspace — Stage 13;
- production media workflows — Stage 14;
- proactive/budget/global security campaign — Stage 15.

Можно проектировать Stage 9 так, чтобы эти слои потом подключились, но не объявлять их готовыми.

## 5. Дальнейшие этапы после Stage 9

- **10/16:** Remote Worker — QR pairing, device credentials, heartbeat/capabilities, authenticated remote jobs, progress/reconnect/resume.
- **11/16:** Connectors — production GitHub first, затем остальные разрешённые интеграции.
- **12/16:** Persona Lead/Co-Agent runtime.
- **13/16:** Dynamic Subagents + conflict-safe multi-agent workspace.
- **14/16:** Full Media Engines/workflows.
- **15/16:** Proactive AI + Budget/Quota + security hardening.
- **16/16:** Final autonomous E2E + production activation/release.

## 6. Сервер / VPS

Production DNS/Relay/TLS blocker ведётся отдельно. Не считать его автоматически решённым без новой проверки.

Главное архитектурное правило уже нормативно закреплено и реализовано в Scheduler:

- лёгкие задачи могут идти в фоне, если platform policy это допускает;
- тяжёлые L3/L4 требуют доступного foreground worker;
- основной VPS/Control Plane не является heavy-compute fallback;
- при закрытии/потере worker тяжёлая задача должна checkpoint-нуться и перейти в `waitingForWorker`, а не «уехать на сервер».

## 7. Старые PR

- PR #149 — только historical reference. Не мержить старый stacked runtime/worker foundation поверх текущего `main`; Stage 6–8 уже заменили его значительную часть новой проверенной архитектурой.
- Старые connector/agent PR также сначала сравнивать с актуальными contracts Stage 5–8 и переносить только совместимые идеи.

## 8. Gate каждого следующего этапа

Этап считается DONE только если:

1. focused tests текущего этапа green;
2. предыдущие security/regression suites green;
3. full repository analyze/test green;
4. Android debug APK build green;
5. Windows release build green;
6. exact validated head merged в `main`;
7. `WESI_AI_STAGE_TRACKER.md`, `WESI_AI_IMPLEMENTATION_STATUS.md` и этот handoff обновлены.

**Не запускать production deploy/release автоматически.**
