# Wesi AI — Stage Tracker

**Статус документа:** живой фактический трекер реализации.  
**Источник требований:** `WESI_AI_MASTER_SPEC.md` и обязательные Wesi AI addendum/specs.  
**Правило:** `DONE` ставится только после merge в `main` и зелёных обязательных gates.

## Текущее состояние

- **Этапы 1–10/16: DONE.**
- **Stage 11/16:** GitHub connector production foundation слит через PR #178 (`0f817169913281d5efa4f5ac9b328f8af753e0dd`), но полный multi-provider Connectors stage остаётся расширяемым milestone и не объявляется завершённым целиком.
- **Stage 12/16:** реализация Persona Lead/Co-Agent завершена в `agent/wesi-ai-finish-unfinished-20260816`, exact-head focused CI зелёный; production Main hooks и отдельный streaming gateway уже развернуты. До `DONE` нужны PR merge и обязательные full gates.
- **Следующий новый функциональный этап после закрытия Stage 12: 13/16 — Dynamic subagents.**
- Stage 10 влит через PR #177, main `93d021aea914969a02f5951db5f78096d8732c11`; полный PR check, Android debug APK и Windows release — green.
- Stage 9 влит через PR #174, main `cfe172d123b25f8631cf510d520e1d6e389389d7`; полный PR check, Android debug APK и Windows release — green.
- Stage 8 дополнительно усилен PR #172, main `1d92a484c017bf3cf6996e6b6171726f88a90928`.
- После Stage 9 отдельно влит production-safe multi-provider AI routing/deploy hardening через PR #176, main `14ee3f835ca3057a137eca28bad689a9317167b2`; это не отдельный номерной этап.
- После Stage 10 отдельно влит contextual chat/persona UX hardening через stable PR #181, main `95cdbb9c6a4f50b22636ea6eabaed093bbb1dec0`: тематические follow-up подсказки, интерактивный `question` block с 2–5 вариантами и `Свой ответ`, контекстные упоминания создателя/Wesi Inc./Wesi AI/WesiOS и transient/lazy new-chat lifecycle. Рабочий PR #180 закрыт как superseded.
- Visual/persona PR #182, main `fbc2fc2beca6581d090845d8e7542dd7c063b612`, сохранил эту механику поверх Markdown-таблиц, bounded `wesi-chart` и творческого исключения Нирваны; persona validation, analyze/full Flutter test, Android debug и Windows release — green.
- Production streaming remediation 2026-08-16: `wesi-ai-stream` перенесён на Foreign Relay sidecar, потому что Main deploy user не имеет root/Node/nginx write. Main остаётся защищённой `prepare/tool` boundary через HTTPS и hot-reload hooks без sudo.
- Production deploy run **31949953310 — SUCCESS**: Relay `ready:true`, Relay streaming `true`, `wesi-ai-stream-gateway` healthy, Main hooks hot-deployed, публичные `/api/wesi/ai/chat/stream` и `/v1/wesi-ai-stream` доступны и fail-closed возвращают 401 без auth.
- В production sealed configuration подтверждены **5 Gemini credential slots** (`GEMINI_API_KEY` + `_2…_5`); Relay installer теперь сохраняет их в provider environment и systemd загружает этот env.
- Штатный `.github/workflows/deploy-wesi-ai-streaming.yml` переведён на проверенную rootless-Main / Relay-sidecar схему; временные диагностические workflows удалены.
- Тяжёлые L3/L4 задачи не переносить на основной VPS/Control Plane: при потере worker использовать checkpoint → `waitingForWorker` → resume либо fail-closed для небезопасного повтора.

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
| 10/16 | **DONE** | Remote Worker: QR/device pairing, one-time credential delivery, HMAC/replay-safe transport, bounded Control Plane mailbox/heartbeat, durable leases/execution payloads/receipts, Stage-8 scheduler integration, reconnect/pause/resume/cancel, same-worker affinity, ACK-gated lease renewal and fail-closed unsafe worker-loss handling. PR #177, main `93d021aea914969a02f5951db5f78096d8732c11`. Full PR check + Android debug + Windows release green. |
| 11/16 | **MILESTONE** | Secure Connectors foundation: production GitHub connector, server-side encrypted vault, OAuth token isolation, READ/WRITE/DESTRUCTIVE Capability Broker policy and Connector Manager. Foundation merged via PR #178; remaining providers use the same broker contract as credentials/integrations become available. |
| 12/16 | **READY FOR FULL GATES** | Real Persona Lead/Co-Agent runtime: typed bounded handoff, complementary Zane/Nirvana review, one revision round, Lead final ownership, read-only scoped tools, no recursion/destructive delegation, safe observable Thinking timeline. Production Main hooks + Relay-hosted streaming gateway are live; focused server/analyze/UI tests green. Await PR/full Android+Windows gates and merge before `DONE`. |
| 13/16 | **NEXT AFTER STAGE 12 MERGE** | Dynamic subagents + scoped tools/context/budgets + conflict-safe multi-agent workspace. |
| 14/16 | TODO | Full Media Engines/workflows: image edit/reference, music stems, video composition/FFmpeg/voice/SFX/subtitles. |
| 15/16 | TODO | Proactive AI, Budget/Quota, prompt-injection/security/permission-revoke hardening. |
| 16/16 | TODO | Final autonomous E2E acceptance, production activation and release gates. |

## Stage 12 acceptance evidence

- Persona Co-Agent protocol/orchestrator/policy and Main stream integration: implemented on current finish branch.
- Co-Agent tool scope: READ-only intersection; WRITE/DESTRUCTIVE and recursive delegation fail closed.
- Final response ownership: Lead Persona only; Co-Agent raw reasoning is never exposed.
- Thinking UI: observable status/work timeline only; Classic hides the work log completely.
- Exact focused CI run **31949953306 — SUCCESS**: stream-gateway syntax/tests, `flutter analyze --no-fatal-infos`, Co-Agent Thinking timeline tests.
- Production streaming deployment run **31949953310 — SUCCESS**: Relay + gateway healthy, Main hooks exact-copy verified, external unauthenticated protection smoke 401/401.
- Client has a dedicated `WESI_AI_STREAM_BASE_URL` edge with safe network fallback to authenticated Main chat. A client release is still required before already-installed builds use this new edge automatically.

## Обязательный порядок продолжения

1. Не переделывать Stage 1–10 и post-Stage-10 UX/persona baseline без воспроизводимого regression.
2. Закрыть Stage 12 через focused tests → полный PR gate → Android debug → Windows release → merge; только после этого поставить `DONE`.
3. Затем начинать Stage 13 на отдельной ветке от нового актуального `main`.
4. Dynamic subagents обязаны наследовать Stage-5 Capability Broker, Stage-8 durable scheduling и Stage-12 bounded/safe handoff semantics; никаких скрытых бесконтрольных recursive agents.
5. Каждый этап: focused tests → полный PR gate → Android debug → Windows release → merge → только затем `DONE`.
6. Не использовать основной VPS как fallback для тяжёлых L3/L4 вычислений.
7. Старые PR #149, #175 и superseded #180 — только historical reference; не мержить их как готовый stack.
8. Force-kill-safe remote push остаётся отдельным незакрытым инфраструктурным пунктом: durable server AI job + device registration + FCM/APNs; текущие local/background notifications не считать эквивалентом.
