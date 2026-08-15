# Wesi AI — Implementation Status / Agent Handoff

**Дата актуализации:** 2026-08-15  
**Функциональная база:** актуальный `main` после Stage 10 merge `93d021aea914969a02f5951db5f78096d8732c11` + последующие docs-only updates.  
**Источник требований:** `docs/WESI_AI_MASTER_SPEC.md` и связанные обязательные Wesi AI specs/addenda.  
**Правило:** этот файл фиксирует только фактически реализованное и проверенное состояние. Целевые возможности остаются в Master Spec.

## Читать следующему агенту в таком порядке

1. `WESI_AI_AGENT_HANDOFF.md` — точка продолжения и запреты.
2. `WESI_AI_STAGE_TRACKER.md` — фактические DONE/NEXT/TODO этапы.
3. Этот файл — инвентаризация реализованного.
4. `WESI_AI_MASTER_SPEC.md` + профильный spec текущего этапа.

**Ключевой статус:** этапы **1–10/16 DONE и находятся в `main`**. Следующая работа — **Stage 11/16: Connectors**, начиная с production GitHub connector.

---

# 1. Baseline Wesi AI до Stage 1

В `main` уже существовали и сохраняются:
- отдельные persona-чаты Зейна и Нирваны + Lobby;
- несколько AI-чатов с employee isolation;
- Hive persistence/recovery;
- AI Projects, «Без проекта», project instructions/context, перенос чатов;
- conversation-first AI UI/sidebar/projects/composer;
- embedded camera;
- Universal Attachments, staged upload и bounded extraction;
- большие image/audio/video/PDF provider file paths;
- attachment retry/cleanup;
- voice dictation/hands-free/TTS foundation;
- rich structured response blocks;
- explicit Zane↔Nirvana handoff foundation;
- media-engine manifest/downloader/verification foundation.

Крупный baseline `Projects + Camera + AI client hardening + Large Attachments` был влит через PR #153, main `3c126b156a5a36b3d5a609fb22334879e91d4855`.

---

# 2. Stage 1/16 — Smart Queue — DONE

**PR:** #163  
**Main:** `0d138773c4692fbb55b504cd3e635a7c01492540`

Реализовано:
- intent-aware очередь `CONTROL > STEER > DEFERRED`;
- Stop/Steer preemption/correction;
- stale follow-up supersession;
- restart-safe durable outbox;
- inflight recovery;
- lifecycle/background completion hardening;
- file reattach/manual retry semantics.

Gates: full analyze/test, Android debug, Windows release — green.

# 3. Stage 2/16 — True Network Streaming — DONE

**PR:** #164  
**Main:** `b58a73bb59b60297f1fb44df20b66a1c1426483c`

Реализовано:
- provider SSE → Relay → Main Stream Gateway → WesiOS NDJSON;
- Main сохраняет policy/tool boundary;
- Stop/Steer отменяет transport;
- one live partial assistant message + one persisted final;
- nginx no-buffering contract;
- JSON fallback.

Gates: server/Relay/Main tests, full Flutter analyze/test, Android/Windows — green.

# 4. Stage 3/16 — Local-first Memory Engine — DONE

**PR:** #165  
**Main:** `fddc5e52d27cb931f5cbdc22f42742c9d96a2524`

Реализовано:
- memory schema v3 + safe migration;
- shared/Zane/Nirvana/project scopes;
- rolling summaries and task state;
- relevance retrieval;
- background extraction;
- secret filtering/dedup/caps;
- memory controls;
- separated summary/project/task-state transport.

Gates green.

# 5. Stage 4/16 — Important Backup + encrypted LAN/Wi-Fi D2D — DONE

**PR:** #166  
**Main:** `6d929fbe9eb018e310de0479d42ed4e4e9e876ba`

Реализовано:
- important-chat opt-in backup;
- `.wbackup` AES-256-GCM + PBKDF2;
- bounded ZIP preflight, duplicate/ZIP64/encryption/compression protections;
- employee-isolated idempotent restore;
- artifact restore/checksums;
- encrypted one-shot raw TCP LAN/Wi-Fi D2D;
- private-address policy; без global Android cleartext exception.

Gates green.

# 6. Stage 5/16 — Capability Registry / Action Broker / Risk / Audit — DONE

**PR:** #167  
**Main:** `93a8b23c97a9913b505d1db3b8df5ced56c86373`

Реализовано:
- fail-closed Capability Registry;
- Action Broker;
- READ/WRITE/DESTRUCTIVE risk;
- session-bound one-time destructive tickets с TTL/args binding/replay protection;
- verified-only confirmation UI;
- unified server audit;
- одинаковый broker path для JSON/streaming;
- real WesiOS tools: Tasks, Calendar, Treasury, CRM, Knowledge, Roadmap, Audio Vault, Team context.

Device-local Notifications намеренно не выдуманы как server collection.

Gates green.

# 7. Stage 6/16 — Controlled Local Runtime — DONE

**PR:** #168  
**Main:** `e626469de2164bbd68e1c7c5db11e10536eca93d`

Реализовано:
- typed filesystem/terminal/Git/HTTP/Python/Node/Flutter/build/document/media executor;
- no raw shell-string contract;
- workspace isolation and no traversal/symlink escape;
- `.wesi` protected;
- sanitized env/no host secrets;
- SSRF/DNS pinning;
- versioned `workspaceV1` real OS-level sandbox contract;
- dangerous actions confirm externally;
- metadata-only audit.

Gates green.

# 8. Stage 7/16 — Environment Scanner + Runtime Packs — DONE

**PR:** #169  
**Main:** `538f5cd092de6538a42a9aa84938c4e255d46a3b`

Реализовано:
- trusted absolute-PATH Environment Scanner;
- Core/Developer/Browser/Documents/Media packs;
- Ed25519 signed descriptor/artifact trust;
- URL/hash/size verification;
- bounded extraction;
- DNS pinning/redirect protections;
- managed install root;
- explicit install confirmation;
- post-install rescan;
- atomic swap + rollback;
- `workspaceV1` only after verified `wesi-sandbox` prerequisite.

Gates green.

# 9. Stage 8/16 — Adaptive Scheduler + Durable Jobs — DONE

**PR:** #170, hardening #172  
**Main:** `4fca3101927d4686e365aaf33530786ea7345b82`, hardening `1d92a484c017bf3cf6996e6b6171726f88a90928`

Реализовано:
- adaptive L0–L4 scheduler;
- trusted workload registry;
- platform/role/trust/policy/capability/pack/resource/foreground filtering;
- available RAM/free VRAM/free disk/thermal/power/concurrency policy;
- L3/L4 never execute on Control Plane/main VPS;
- durable bounded `WesiDurableJobQueue`;
- queued/running/paused/waitingForWorker/cancelling/terminal lifecycle;
- checkpoints and restart recovery;
- unknown persisted capabilities/enums fail closed;
- persistence rollback and temp/backup recovery;
- coordinator uses durable queue as single source of truth.

Gates green.

# 10. Stage 9/16 — Self-debug + Validated Artifact Delivery — DONE

**PR:** #174  
**Main:** `cfe172d123b25f8631cf510d520e1d6e389389d7`

Реализовано:
- bounded objective plan/iteration model;
- execute → validate → diagnose → repair → retest loop;
- mandatory tool/process verification rather than model claim;
- bounded/redacted logs;
- integration with Stage-8 durable jobs/pause/resume/cancel/worker-loss;
- Local Capability validation;
- fail-closed artifact path/existence/type/size/integrity checks;
- build result must actually succeed before delivery;
- SHA-256 artifact re-check immediately before delivery;
- missing/changed artifact cannot be delivered as success.

Full PR check, Android debug, Windows release — green.

# 11. Multi-provider AI baseline after Stage 9 — MERGED, non-numbered

**PR:** #176  
**Main:** `14ee3f835ca3057a137eca28bad689a9317167b2`

Реализовано:
- Pro/Maximum multi-provider advisor orchestration;
- advisors analyze only; they do not execute WesiOS tools;
- final Gemini path retains persona/tool protocol, preserving single brokered side effect;
- Relay deployment runtime bundle fixes;
- nginx compatibility fix;
- optional advisor provider credentials remain sealed on Relay;
- both normal and streaming routing aligned.

Focused Relay suite and repository/platform gates green before merge. Production deploy не является следствием merge.

# 12. Stage 10/16 — Remote Worker — DONE

**PR:** #177  
**Validated head:** `93d385c736b70f24fa101f2fe7ede82eb00cd92d`  
**Main:** `93d021aea914969a02f5951db5f78096d8732c11`

Реализовано:
- secure QR pairing;
- short-lived one-time ticket/nonce/device fingerprint;
- high-entropy poll secret отсутствует в QR;
- server хранит derived request key, desktop использует исходный poll secret как credential secret;
- owner-scoped 90-day worker credential with revoke/expiry;
- HMAC request authentication: credential/worker identity, timestamp, nonce, method/path, body SHA-256;
- bounded durable nonce replay window;
- Control Plane хранит только pairing/credentials/heartbeat/mailbox metadata;
- bounded mailbox capacity and message size;
- никаких heavy build/media executions на VPS;
- Stage-8 worker profiles and scheduler integration;
- durable execution payload sidecar;
- durable per-job lease/generation/inbound sequence;
- desktop durable receipt journal for at-most-once automatic execution;
- assignment ACK-gated lease renewal;
- stale worker/lease/generation/sequence rejection;
- checkpoint/pause/resume/cancel/reconnect lifecycle;
- same-worker affinity for workspace-bound resume;
- checkpointable worker loss → waiting/resume only with current durable checkpoint;
- uncheckpointed state-changing non-checkpointable worker loss fails closed;
- safe non-checkpointable READ may wait/retry;
- dispatch requires durable execution payload;
- actual execution uses Stage-6 typed Local Runtime on desktop worker;
- old conflicting PR #175 closed and superseded.

Validation:
- server protocol tests green;
- rebased focused Stage 8–10 regressions: 63/63 green after fixing an obsolete HMAC test fixture to current secret-length contract;
- full Flutter test green;
- final PR check green;
- Android debug APK green;
- Windows release green.

Production deploy/release не запускался.

---

# 13. Следующий этап — Stage 11/16 Connectors

Master Spec требует Wesi Connector Manager/SDK. Приоритет:
1. GitHub — production end-to-end first;
2. Google Drive;
3. Gmail;
4. Google Calendar;
5. Slack;
6. Telegram;
7. GitLab/Notion/Jira/OneDrive/Dropbox по фактическим интеграциям.

Обязательные свойства:
- OAuth/access/refresh tokens не видны LLM;
- model-visible contract содержит logical credential/capability only;
- Connector Broker подставляет secret ниже модели;
- Stage-5 READ/WRITE/DESTRUCTIVE policy + audit применяется к connector actions;
- direct push в protected/main/master запрещён по умолчанию;
- normal GitHub write path: branch → commit → PR;
- scopes/permissions re-check per call;
- revocation/expiry fail closed;
- external content is untrusted and cannot expand tools/scopes;
- bounded rate-limit/retry handling;
- ambiguous state-changing result is not blindly replayed;
- secrets/tokens excluded from logs/audit/durable output/artifacts.

Stage 11 нельзя объявить DONE без focused connector/security tests + full PR check + Android debug + Windows release + merge в `main`.

---

# 14. Remaining stages

- **11/16 NEXT:** Connectors.
- **12/16 TODO:** Persona Lead/Co-Agent runtime.
- **13/16 TODO:** Dynamic Subagents + conflict-safe multi-agent workspace.
- **14/16 TODO:** Full Media Engines/workflows.
- **15/16 TODO:** Proactive AI + Budget/Quota + security hardening.
- **16/16 TODO:** Final autonomous E2E + production activation/release gates.

---

# 15. Постоянные архитектурные запреты

- Не выполнять heavy L3/L4 на Main/Control Plane VPS.
- Не ослаблять `workspaceV1` до boolean sandbox flag.
- Не давать модели raw shell или model-controlled executable paths.
- Не позволять модели self-confirm destructive actions.
- Не хранить connector/provider secrets в model context/logs/audit/artifacts.
- Не выдумывать server collections/capabilities для device-local модулей.
- Не считать production deploy/release выполненным только потому, что tests/merge green.
- PR #149 и #175 — historical reference only, не мержить.
