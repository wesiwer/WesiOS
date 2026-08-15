# Wesi AI — Stage Tracker 6/16

**Статус документа:** живой фактический трекер реализации.  
**Источник требований:** `WESI_AI_MASTER_SPEC.md` и обязательные Wesi AI addendum/specs.  
**Правило:** `DONE` ставится только после merge в `main` и зелёных обязательных gates. Код только в рабочей ветке/PR не считается завершённым этапом.

| Этап | Статус | Содержание |
|---|---|---|
| 1/16 | **DONE** | Smart Queue: CONTROL > STEER > DEFERRED, Stop/Steer, restart-safe durable outbox, superseded follow-ups, lifecycle hardening. PR #163, main `0d138773c4692fbb55b504cd3e635a7c01492540`. |
| 2/16 | **DONE** | True network streaming: provider SSE → Relay → Main Stream Gateway → WesiOS NDJSON, tool shielding, transport cancel, single persisted final answer. PR #164, main `b58a73bb59b60297f1fb44df20b66a1c1426483c`. Full PR test gate, Android debug build and Windows release build passed. Production streaming deploy not triggered. |
| 3/16 | **DONE** | Local-first Memory Engine: schema v3 + safe legacy migration, structured shared/persona/project memory, per-chat rolling summary and task state, relevant retrieval, background extraction, secret filtering/dedup/caps, user memory controls and separated summary/project/task transport. PR #165, main `fddc5e52d27cb931f5cbdc22f42742c9d96a2524`. Full PR analyze/test, Android debug build and Windows release build passed. |
| 4/16 | **DONE** | Explicit important-chat backup + encrypted LAN/Wi-Fi D2D: important-chat opt-in, authenticated encrypted `.wbackup`, bounded ZIP preflight, employee-isolated idempotent restore/merge, artifact restore, one-time HMAC/AES-GCM raw-TCP LAN transfer with private-address policy and TTL. PR #166, main `6d929fbe9eb018e310de0479d42ed4e4e9e876ba`. Full PR analyze/test, Android debug build and Windows release build passed. No production deploy/release triggered. |
| 5/16 | **DONE** | Unified Capability Registry / Action Broker / Risk Policy / Audit + WesiOS read/write tools. Fail-closed tool registry, READ/WRITE/DESTRUCTIVE classes, session-bound one-time destructive confirmation tickets, verified-only confirmation UI, unified server audit, and brokered Tasks/Calendar/Treasury/CRM/Knowledge/Roadmap/Audio Vault/Team context. PR #167, main `93a8b23c97a9913b505d1db3b8df5ced56c86373`. Full PR analyze/test, Android debug build and Windows release build passed. No production deploy/release triggered. |
| 6/16 | **IN PROGRESS** | Controlled Wesi Local Runtime: filesystem, terminal, Git, HTTP, Python/Node/Flutter/build/document/media tools. |
| 7/16 | TODO | Environment Scanner + Core/Developer/Browser/Documents/Media Runtime Packs and dependency reuse/install/upgrade. |
| 8/16 | TODO | Resource Scheduler, L0–L4 classification, foreground/background policy, jobs/checkpoints/pause/resume. |
| 9/16 | TODO | Self-debug loop + validated artifact creation/build delivery. |
| 10/16 | TODO | Remote Worker: QR pairing, device credentials, heartbeat/capabilities, remote jobs/progress/reconnect. |
| 11/16 | TODO | Connectors: production GitHub first, then Drive/Gmail/Calendar/Slack/Telegram/etc. |
| 12/16 | TODO | Real Persona Lead/Co-Agent runtime: typed internal handoff, review/revision/joint integration. |
| 13/16 | TODO | Dynamic specialized subagents + scoped context/tools/budgets + conflict-safe multi-agent workspace. |
| 14/16 | TODO | Full Media Engines/workflows: image edit/reference, music stems, video composition/FFmpeg/voice/SFX/subtitles. |
| 15/16 | TODO | Proactive AI, Budget/Quota Manager, security/prompt-injection/permission/revoke hardening. |
| 16/16 | TODO | Final autonomous E2E acceptance scenarios, production activation and release gates. |

## Текущий порядок

Этапы выполняются последовательно. Следующий тяжёлый слой не считается начатым вместо предыдущего, пока предыдущий не прошёл обязательные tests/build gates и не попал в `main`.

Внешняя серверная/DNS активация ведётся как параллельный инфраструктурный blocker и не заставляет переносить тяжёлые вычисления на основной VPS.
