# Wesi AI — Stage Tracker

**Статус документа:** живой фактический трекер реализации.  
**Источник требований:** `WESI_AI_MASTER_SPEC.md` и обязательные Wesi AI addendum/specs.  
**Правило:** `DONE` ставится только после merge в `main` и зелёных обязательных gates. Код только в рабочей ветке/PR не считается завершённым этапом.

## Текущее состояние

- **Этапы 1–8/16: DONE.**
- **Этап 9/16 — IN PROGRESS:** Self-debug loop + validated artifact creation/build delivery.
- Stage-9 implementation ведётся в PR #173 поверх актуального `main`; focused Stage 6–9 security/durability gate уже зелёный, но этап не станет `DONE` до полного repository gate, Android debug, Windows release и merge.
- Внешняя серверная/DNS production-активация остаётся отдельным инфраструктурным треком и не является причиной переносить тяжёлые вычисления на основной VPS.

| Этап | Статус | Содержание |
|---|---|---|
| 1/16 | **DONE** | Smart Queue: `CONTROL > STEER > DEFERRED`, текстовый/кнопочный Stop, немедленный Steer/Correction, superseded follow-ups, restart-safe durable outbox, безопасный inflight recovery и lifecycle hardening. PR #163, main `0d138773c4692fbb55b504cd3e635a7c01492540`. Full analyze/test, Android debug и Windows release прошли. |
| 2/16 | **DONE** | True network streaming: provider SSE → Relay → Main Stream Gateway → WesiOS NDJSON, tool shielding, transport cancel по Stop/Steer, один live partial-message и одна финальная запись в историю, unbuffered nginx contract и JSON fallback. PR #164, main `b58a73bb59b60297f1fb44df20b66a1c1426483c`. Full PR gate, Android debug и Windows release прошли. Production streaming deploy не запускался. |
| 3/16 | **DONE** | Local-first Memory Engine: schema v3 + безопасная legacy migration, structured shared/persona/project memory, rolling summary, per-chat task state, relevance retrieval, background extraction, secret filtering/dedup/caps, user memory controls и раздельные summary/project/task контексты. PR #165, main `fddc5e52d27cb931f5cbdc22f42742c9d96a2524`. Full analyze/test, Android debug и Windows release прошли. |
| 4/16 | **DONE** | Explicit important-chat backup + encrypted LAN/Wi-Fi D2D: important-chat opt-in, AES-256-GCM `.wbackup`, PBKDF2, bounded ZIP preflight, employee-isolated idempotent restore/merge, artifact restore, одноразовый HMAC/AES-GCM raw-TCP LAN transfer, private-address policy, TTL/fingerprint. PR #166, main `6d929fbe9eb018e310de0479d42ed4e4e9e876ba`. Full analyze/test, Android debug и Windows release прошли. No production deploy/release. |
| 5/16 | **DONE** | Unified Capability Registry / Action Broker / Risk Policy / Audit + WesiOS read/write tools. Fail-closed registry, READ/WRITE/DESTRUCTIVE classes, session-bound one-time destructive confirmation tickets, verified confirmation UI, unified audit и brokered Tasks/Calendar/Treasury/CRM/Knowledge/Roadmap/Audio Vault/Team context. PR #167, main `93a8b23c97a9913b505d1db3b8df5ced56c86373`. Full analyze/test, Android debug и Windows release прошли. No production deploy/release. |
| 6/16 | **DONE** | Controlled Wesi Local Runtime: typed fail-closed filesystem/terminal/Git/HTTP/Python/Node/Flutter/build/document/media executor, isolated workspace, `.wesi` isolation, SSRF + DNS/IP pinning, sanitized process environment, metadata-only audit и versioned `workspaceV1` sandbox contract. PR #168, main `e626469de2164bbd68e1c7c5db11e10536eca93d`. Full analyze/test, Android debug и Windows release прошли. No production deploy/release. |
| 7/16 | **DONE** | Verified Environment Scanner + Core/Developer/Browser/Documents/Media Runtime Packs: absolute-PATH reuse, signed Ed25519 artifacts, URL/size/SHA trust chain, bounded extraction, post-install rescan, atomic rollback, fail-closed `workspaceV1` activation, relative-PATH rejection. PR #169, main `538f5cd092de6538a42a9aa84938c4e255d46a3b`. Full analyze/test, Android debug и Windows release прошли. No production deploy/release. |
| 8/16 | **DONE** | Adaptive Resource Scheduler + durable jobs: L0–L4 classification, trusted workload registry, verified capability/pack/resource filters, CPU/RAM/VRAM/disk/thermal/power/concurrency policy, heavy foreground requirement, Control Plane heavy-compute prohibition, bounded durable journal, checkpoint/pause/resume, `waitingForWorker`, restart-safe coordinator integration. PR #170, validated head `f9bd4e28dc8b88363a4025c8ea0d4231f48432bb`, main `4fca3101927d4686e365aaf33530786ea7345b82`; recovery hardening PR #172, main `1d92a484c017bf3cf6996e6b6171726f88a90928`. Full PR check, Android debug и Windows release прошли. No production deploy/release. |
| 9/16 | **IN PROGRESS** | Bounded self-debug loop, objective verify/diagnose/repair/re-test, durable plan/step/iteration checkpointing, safe restart without duplicate uncertain WRITE/DESTRUCTIVE side effects, Stage-8 pause/cancel/`waitingForWorker`, redacted bounded evidence, validated artifacts, build-proof binding for APK/EXE, TOCTOU-safe validation and idempotent delivery. PR #173. Focused Stage 6–9 security/durability gate green; full PR/Android/Windows gates pending final exact head. |
| 10/16 | TODO | Remote Worker: QR pairing, device credentials, heartbeat/capabilities, authenticated remote jobs/progress/reconnect/resume. |
| 11/16 | TODO | Connectors: production GitHub first, затем Drive/Gmail/Calendar/Slack/Telegram/GitLab/Notion/Jira/OneDrive/Dropbox по фактическим доступным интеграциям. |
| 12/16 | TODO | Real Persona Lead/Co-Agent runtime: typed internal handoff, structured result, review/revision/joint integration без переключения пользователя между чатами. |
| 13/16 | TODO | Dynamic specialized subagents + scoped context/tools/budgets + conflict-safe multi-agent workspace. |
| 14/16 | TODO | Full Media Engines/workflows: image edit/reference, music stems/regeneration/mix/master, video composition/FFmpeg/voice/SFX/subtitles. |
| 15/16 | TODO | Proactive AI, Budget/Quota Manager, prompt-injection/security/permission-revoke hardening и антиспам/quiet-hours policy. |
| 16/16 | TODO | Финальные autonomous E2E acceptance scenarios, production activation, release gates и доказательство end-to-end автономности. |

## Обязательный порядок продолжения

1. Не переделывать Stage 1–8, если не найден воспроизводимый regression; Stage-8 follow-up #172 уже включён в `main`.
2. Завершить **Stage 9/16** в PR #173: чистый diff → full repository gate → Android debug → Windows release → merge в `main`.
3. `DONE` для Stage 9 ставить только после merge и зелёных обязательных gates на одном exact head.
4. Не начинать Stage 10 вместо незавершённого Stage 9.
5. Не запускать production release/deploy автоматически. Это отдельное явное действие.
6. Не переносить тяжёлые L3/L4 задачи на основной VPS/Control Plane. Если worker недоступен: checkpoint → `waitingForWorker` → resume после возвращения worker.
7. Старый PR #149 использовать только как исторический reference. Не мержить его как готовый stack: Stage 6–8 уже реализованы заново поверх актуального `main`.
