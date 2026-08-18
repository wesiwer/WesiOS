# Wesi AI — Agent Handoff

**Назначение:** первая точка входа для следующего AI-агента, продолжающего Wesi AI.  
**Актуально на:** 2026-08-15.  
**Источник истины:** актуальный `main`, `WESI_AI_MASTER_SPEC.md`, профильные Wesi AI specs, `WESI_AI_STAGE_TRACKER.md` и этот handoff.

## 1. Где мы остановились

**Stage 1–10/16 полностью завершены, проверены и влиты в `main`.**

Последний завершённый номерной этап:
- **Stage 10/16 — Remote Worker**;
- PR #177;
- validated PR head `93d385c736b70f24fa101f2fe7ede82eb00cd92d`;
- main merge `93d021aea914969a02f5951db5f78096d8732c11`;
- полный PR check, Android debug APK и Windows release build — green;
- production deploy/release не запускался.

Перед Stage 10 отдельно влит production-safe multi-provider AI routing/deploy hardening через PR #176, main `14ee3f835ca3057a137eca28bad689a9317167b2`. Это текущая baseline-интеграция, но не отдельный номерной этап.

Старый Stage-10 PR #175 закрыт как stale/superseded и не должен мержиться.

## 2. Что уже есть и НЕ надо переделывать без regression

### Stage 1 — Smart Queue
- `CONTROL > STEER > DEFERRED`;
- Stop/Steer прерывают/корректируют текущую работу;
- deferred follow-ups ждут;
- superseded items не исполняются;
- restart-safe queue/inflight recovery.

### Stage 2 — True Streaming
- provider SSE → Relay → Main Stream Gateway → WesiOS NDJSON;
- Main остаётся policy/tool boundary;
- Stop/Steer отменяет stream transport;
- один partial assistant message + одна финальная persisted запись.

### Stage 3 — Memory Engine
- schema v3;
- shared/Zane/Nirvana/project scopes;
- rolling summaries/task state/relevance retrieval;
- background extraction, secret filtering, dedup/caps, controls.

### Stage 4 — Backup + LAN D2D
- encrypted `.wbackup`, AES-256-GCM/PBKDF2;
- bounded ZIP preflight;
- employee-isolated idempotent restore;
- encrypted one-shot raw-TCP LAN/Wi-Fi transfer;
- artifact restore.

### Stage 5 — Capability Broker / Risk / Audit / WesiOS actions
- fail-closed Capability Registry + Action Broker;
- READ/WRITE/DESTRUCTIVE;
- session-bound one-time destructive confirmation ticket;
- verified confirmation UI and unified audit;
- brokered Tasks/Calendar/Treasury/CRM/Knowledge/Roadmap/Audio Vault/Team context.

### Stage 6 — Controlled Local Runtime
- typed filesystem/terminal/Git/HTTP/Python/Node/Flutter/build/document/media tools;
- workspace isolation and `.wesi` protection;
- SSRF/DNS pinning and sanitized environment;
- `workspaceV1` OS-level sandbox contract.

### Stage 7 — Environment Scanner + Runtime Packs
- Core/Developer/Browser/Documents/Media packs;
- trusted absolute-PATH reuse only;
- Ed25519 signed descriptors, URL/size/SHA verification;
- bounded extraction, rescan, atomic rollback;
- sandbox activation only after verified prerequisite.

### Stage 8 — Scheduler + Durable Jobs
- L0–L4 classification;
- trusted workload registry;
- CPU/RAM/VRAM/disk/thermal/power/concurrency policy;
- L3/L4 require foreground worker and never fall back to Control Plane;
- durable queue/journal, checkpoints, pause/resume, `waitingForWorker`.

### Stage 9 — Self-debug + validated artifacts
- bounded objective plan/repair/re-test loop;
- tool/process result is authoritative, not model claims;
- Stage-6 typed runtime only;
- restart/pause/cancel/worker-loss via Stage-8 durable jobs;
- artifact path/existence/type/size/integrity validation;
- SHA-256 re-check immediately before delivery;
- failed/missing artifact cannot be marked successful.

### Stage 10 — Remote Worker
- QR pairing with short-lived one-time ticket; permanent secret never in QR;
- desktop derives its credential secret from high-entropy poll secret; server stores only derived request key;
- owner-scoped worker credentials with revoke/expiry;
- HMAC-authenticated requests + timestamp/body hash/nonce replay protection;
- bounded Control Plane pairing/heartbeat/mailbox metadata only; no heavy execution on VPS;
- Stage-8 scheduler uses paired remote worker capabilities/resources;
- durable execution payload sidecar, lease generation and desktop receipt journal;
- at-most-once automatic execution across desktop restart;
- assignment ACK gates lease renewal;
- same-worker affinity for paused/waiting workspace jobs;
- checkpoint/pause/resume/cancel/reconnect lifecycle;
- stale lease/generation/sequence rejected;
- uncheckpointed state-changing worker loss fails closed;
- safe non-checkpointable READ may wait/retry;
- dispatch refuses jobs without durable execution payload;
- actual execution remains Stage-6 typed Local Runtime on worker.

## 3. Текущая AI provider baseline после PR #176

- Fast остаётся минимальным маршрутом;
- Pro/Maximum поддерживают multi-provider advisor orchestration;
- вспомогательные provider calls анализируют, но не исполняют WesiOS tools;
- финальный persona/tool protocol остаётся на финальном Gemini path, поэтому side effect выполняется один раз через Main/Action Broker;
- Relay deployment включает необходимые runtime modules и совместимый nginx contract;
- provider credentials остаются sealed на Relay и не передаются Flutter/Main как модельный контекст.

Не путать это с Stage 12/13: настоящий Persona Co-Agent и dynamic subagents ещё TODO.

## 4. Следующая работа — Stage 11/16 Connectors

**Начать с production GitHub connector end-to-end**, затем расширять общий SDK/Broker contract на фактически доступные интеграции: Google Drive, Gmail, Google Calendar, Slack, Telegram, затем GitLab/Notion/Jira/OneDrive/Dropbox.

Создать новую ветку от актуального `main`, например:
`agent/wesi-ai-stage11-connectors`

### Обязательные архитектурные правила Stage 11

1. Connector Manager/SDK + Connector Broker находится ниже модели.
2. OAuth/access/refresh tokens и provider secrets **никогда не передаются LLM как текст**.
3. Модель видит только logical connector/credential id и разрешённые typed capabilities.
4. Реальные connector actions проходят Stage-5 Action Broker/Risk/Audit.
5. READ / WRITE / DESTRUCTIVE разделены; destructive path использует существующий external confirmation contract.
6. Direct push в protected/main/master запрещён по умолчанию policy; нормальный GitHub write path: branch → commit → PR.
7. Connector scopes/permissions перепроверяются при каждом фактическом вызове, а не только при connect-time.
8. Prompt/content из внешнего сервиса считается untrusted data и не может расширять permissions/tools.
9. Tokens/secrets не попадают в model context, logs, audit args, durable job output или artifacts.
10. Network/connector execution не обходит Stage-6/Policy SSRF и production-access rules там, где используется generic HTTP.
11. Revocation/expired credential должны fail closed и немедленно убирать capability из доступного runtime.
12. Idempotency/retry обязателен для writes, где provider API это допускает; неизвестный результат state-changing операции нельзя бездумно повторять.

### GitHub connector minimum production scope

READ:
- list/get repositories;
- branches/commits;
- files/content/tree;
- Actions runs/jobs/artifacts metadata;
- issues/PRs/comments/status/checks as permitted.

WRITE:
- create branch from trusted base ref;
- create/update files/commits on non-protected working branch;
- create/update PR;
- create/comment/update issues within granted scopes;
- trigger/retry allowed Actions only if policy permits.

DESTRUCTIVE / elevated:
- deleting branches/files, force updates, merge, workflow/production-sensitive operations, secret/permission changes must be separately classified and confirmed/blocked according to policy.

### Stage-11 regressions minimum

- token never appears in serialized/model-visible request;
- missing/expired/revoked credential fails closed;
- scope mismatch blocks call before provider request;
- READ succeeds without destructive confirmation;
- protected-main direct write rejected;
- normal branch → commit → PR flow succeeds;
- destructive action cannot self-confirm from model args;
- external content cannot inject a new capability/scope;
- provider 401/403 maps to typed connector failure and capability refresh/revoke handling;
- rate limit/retry is bounded;
- ambiguous write result is not blindly replayed;
- audit stores metadata, not token/raw sensitive payload;
- Stage 5–10 regressions remain green.

## 5. Что НЕ делать в Stage 11

Не объявлять готовыми вместе с connectors:
- Stage 12 Persona Lead/Co-Agent runtime;
- Stage 13 Dynamic Subagents/conflict-safe workspace;
- Stage 14 full Media workflows;
- Stage 15 Proactive AI/Budget/global security campaign;
- Stage 16 production activation/release.

## 6. Сервер / production

- Control Plane остаётся auth/policy/queue/connector-broker/device metadata слоем, не heavy worker.
- Production deploy/release не подразумевается merge/tests и запускается только по явному запросу пользователя.
- Если требуется текущая production server/DNS проверка — сначала проверить реальное состояние заново, не полагаться на старый blocker/status.

## 7. Старые PR

- PR #149 — historical reference only; не мержить.
- PR #175 — stale Stage-10 stack, закрыт и superseded PR #177; не мержить.

## 8. Definition of DONE для следующего этапа

Stage 11 можно отметить DONE только после:
1. focused connector/security tests;
2. полного repository PR check;
3. Android debug APK;
4. Windows release build;
5. merge в `main`;
6. обновления tracker/handoff/status.
