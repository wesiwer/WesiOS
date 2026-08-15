# Wesi AI — Stage Tracker

**Статус документа:** живой фактический трекер реализации.  
**Источник требований:** `WESI_AI_MASTER_SPEC.md` и обязательные Wesi AI addendum/specs.  
**Правило:** `DONE` ставится только после merge в `main` и зелёных обязательных gates.

## Текущее состояние

- **Этапы 1–9/16: DONE.**
- **Следующий этап: 10/16 — Remote Worker.**
- Stage 9 влит через PR #174, main `cfe172d123b25f8631cf510d520e1d6e389389d7`; полный PR check, Android debug APK и Windows release — green.
- Stage 8 дополнительно усилен PR #172, main `1d92a484c017bf3cf6996e6b6171726f88a90928`; Stage 9 был повторно focused-проверен поверх этого hardening до финального PR.
- Production deploy/release автоматически не запускать.
- Тяжёлые L3/L4 задачи не переносить на основной VPS/Control Plane: при потере worker использовать checkpoint → `waitingForWorker` → resume.

| Этап | Статус | Содержание |
|---|---|---|
| 1/16 | **DONE** | Smart Queue: `CONTROL > STEER > DEFERRED`, Stop/Steer, restart-safe durable outbox, inflight recovery, superseded follow-ups. PR #163, main `0d138773c4692fbb55b504cd3e635a7c01492540`. |
| 2/16 | **DONE** | True network streaming provider → Relay → Main → WesiOS, Stop/Steer transport cancel, one partial + one persisted final. PR #164, main `b58a73bb59b60297f1fb44df20b66a1c1426483c`. |
| 3/16 | **DONE** | Local-first Memory Engine: structured shared/persona/project memory, summaries, task state, retrieval, controls. PR #165, main `fddc5e52d27cb931f5cbdc22f42742c9d96a2524`. |
| 4/16 | **DONE** | Encrypted important-chat backup + LAN/Wi-Fi D2D, bounded restore and artifacts. PR #166, main `6d929fbe9eb018e310de0479d42ed4e4e9e876ba`. |
| 5/16 | **DONE** | Capability Registry / Action Broker / Risk / Audit + brokered WesiOS actions and destructive confirmations. PR #167, main `93a8b23c97a9913b505d1db3b8df5ced56c86373`. |
| 6/16 | **DONE** | Controlled Local Runtime: typed tools, isolated workspace, SSRF/DNS pinning, sanitized env, `workspaceV1`. PR #168, main `e626469de2164bbd68e1c7c5db11e10536eca93d`. |
| 7/16 | **DONE** | Verified Environment Scanner + signed Runtime Packs, atomic install/rollback/rescan and sandbox activation. PR #169, main `538f5cd092de6538a42a9aa84938c4e255d46a3b`. |
| 8/16 | **DONE** | Adaptive L0–L4 scheduler + durable jobs/checkpoints/pause/resume/`waitingForWorker`; hardening PR #172. PR #170 main `4fca3101927d4686e365aaf33530786ea7345b82`, hardening `1d92a484c017bf3cf6996e6b6171726f88a90928`. |
| 9/16 | **DONE** | Bounded objective self-debug loop, mandatory verification, bounded repair/re-test, Local Capability validation, fail-closed artifact validation, SHA-256 re-check and validated delivery. PR #174, main `cfe172d123b25f8631cf510d520e1d6e389389d7`. Full PR check + Android debug + Windows release green. |
| 10/16 | **NEXT** | Remote Worker: QR pairing, device credentials, heartbeat/capabilities, authenticated job transport, progress, reconnect, pause/resume/cancel/retry and result return. Обязательно использовать Stage 5–9 trust/policy/runtime/job contracts. |
| 11/16 | TODO | Connectors: production GitHub first, затем Drive/Gmail/Calendar/Slack/Telegram/GitLab/Notion/Jira/OneDrive/Dropbox по фактическим интеграциям. |
| 12/16 | TODO | Persona Lead/Co-Agent runtime: typed internal handoff, review/revision/joint integration. |
| 13/16 | TODO | Dynamic subagents + scoped tools/context/budgets + conflict-safe multi-agent workspace. |
| 14/16 | TODO | Full Media Engines/workflows: image edit/reference, music stems, video composition/FFmpeg/voice/SFX/subtitles. |
| 15/16 | TODO | Proactive AI, Budget/Quota, prompt-injection/security/permission-revoke hardening. |
| 16/16 | TODO | Final autonomous E2E acceptance, production activation and release gates. |

## Обязательный порядок продолжения

1. Не переделывать Stage 1–9 без воспроизводимого regression.
2. Начинать Stage 10 на отдельной ветке от актуального `main`.
3. Каждый этап: focused tests → полный PR gate → Android debug → Windows release → merge → только затем `DONE`.
4. Не запускать production deploy/release автоматически.
5. Не использовать основной VPS как fallback для тяжёлых L3/L4 вычислений.
6. Старый PR #149 — только historical reference; не мержить его как готовый stack.
