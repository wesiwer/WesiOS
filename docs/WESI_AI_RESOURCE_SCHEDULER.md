# Wesi AI — Resource Scheduler & Durable Jobs

**Stage:** 8/16  
**Source of truth:** `WESI_AI_MASTER_SPEC.md`, `WESI_AI_ADAPTIVE_EXECUTION_SPEC.md`, `WESI_AI_LOCAL_RUNTIME.md`, `WESI_AI_RUNTIME_PACKS.md`, `WESI_AI_STAGE_TRACKER.md`.

## Goal

Stage 8 decides the minimum sufficient execution level, selects a safe execution worker from trusted resource/capability facts, and gives long-running work a bounded durable lifecycle.

The scheduler is trusted application/orchestration code. The model does **not** choose worker trust, executable capabilities, installed Runtime Packs, resource telemetry, foreground policy, concurrency limits or checkpoint validity.

## Adaptive execution L0-L4

- **L0 — Chat:** ordinary dialogue only; no Local Runtime.
- **L1 — Simple Action:** one small read/write/tool action with minimal validation.
- **L2 — Assisted Task:** limited Local Runtime/tooling, targeted validation and at most one narrow helper budget.
- **L3 — Complex Agent Task:** complex multi-step/self-debug work; execution worker must remain foreground/available.
- **L4 — Heavy Runtime:** builds, browser integration work, GPU/media pipelines, large-file or otherwise heavy runtime; desktop worker + Resource Scheduler are mandatory.

Classification is based on trusted execution facts and actual estimated cost, not only on a request label. Duration, RAM/VRAM, build/browser/media/large-file requirements and self-debug complexity can escalate the level. Progressive escalation moves upward only when needed.

## Trusted workload registry

Known Stage-6 Local Runtime tools have trusted base requirements:

- filesystem/Git/simple HTTP actions start at L1;
- terminal/Python/Node/Flutter analyze/documents start at L2;
- Flutter tests and significant media work are L3;
- Flutter build is L4.

Trusted callers may only **tighten** resource requirements. Negative resource deltas are rejected. Long estimated duration or GPU requirements escalate the execution level and foreground requirement. Stage-6 Local Runtime target platforms cannot be widened outside the trusted desktop set.

## Worker facts and hard filters

A worker profile carries:

- platform and explicit role: local device, paired remote worker or Control Plane;
- trust and policy state;
- online/busy/paused state;
- verified `WesiLocalCapability` set;
- verified Stage-7 `WesiRuntimePackId` set;
- CPU cores and current CPU load;
- total/available RAM;
- GPU identity, total/free VRAM;
- free disk;
- thermal and power mode;
- foreground/background availability;
- active light/CPU/heavy/GPU job counters.

Invalid resource telemetry fails closed.

A candidate is rejected when any hard requirement is not satisfied: trust/policy, platform, capability, Runtime Pack, CPU headroom, available RAM, free VRAM, free disk, thermal safety, foreground requirement or concurrency limit.

## Control Plane boundary

The main WesiOS server/Control Plane is not a heavy compute worker.

L3/L4 work cannot fall back to the Control Plane. Local Runtime workloads also do not become server workloads merely because a desktop worker is offline. A future explicitly paired remote worker may execute heavy work only after Stage-10 trust/heartbeat/capability integration.

If a required remote worker is offline, the scheduler returns a user-visible blocker instructing the user to open WesiOS on the paired computer and keep it available.

## Foreground/background policy

L0/L1 and a bounded light subset of L2 may run in the background when the execution environment explicitly supports it.

L3/L4 always require the actual execution worker to remain foreground/available. `backgroundExecutionAllowed=true` does not override this rule.

If a heavy worker becomes unavailable, the job is checkpointed where supported and moves to `waitingForWorker`; it is not silently moved to the Control Plane.

## Resource/concurrency policy

The scheduler keeps reserve headroom for RAM, VRAM and disk and enforces separate light/CPU/heavy/GPU concurrency slots.

- heavy/GPU work is exclusive against competing CPU/heavy work;
- L2 CPU work is queued while heavy/GPU work is active;
- L0/L1 remain bounded so a heavy operation does not make the device unresponsive;
- serious/critical thermal states block workloads according to severity;
- low-power mode reduces worker preference for heavy work.

A GPU requirement is checked against **free** VRAM, not nominal GPU capacity. RAM decisions use **available** RAM, not total installed RAM.

## Durable job lifecycle

`WesiDurableJobQueue` uses a bounded schema-versioned journal and strict state transitions:

`queued -> running -> succeeded/failed`

with controlled branches for:

- `pauseRequested -> paused -> queued`;
- `running -> waitingForWorker -> queued`;
- `running -> cancelling -> cancelled`;
- `queued -> blocked -> queued` after the blocker is resolved.

Checkpointable running work must create a validated checkpoint before a safe pause or worker-loss transition. Progress is monotonic.

The journal:

- caps job/event counts and total encoded size;
- rejects unknown persisted enums/capabilities instead of dropping them;
- revalidates persisted job requirements against the trusted workload registry and rejects any downgrade of L-level, capabilities, Runtime Packs, resources or foreground policy;
- preserves the previous valid in-memory snapshot when restore fails;
- rolls back an in-memory enqueue/state mutation if durable journal persistence fails;
- stores bounded status metadata rather than arbitrary process output;
- serializes mutations;
- writes through a same-directory temporary file and rollback backup;
- restores the backup if an interrupted swap left the primary journal missing.

## Stage boundary

Stage 8 provides scheduling policy and durable local job state. It does **not** implement:

- the Stage-9 autonomous self-debug/artifact delivery loop;
- Stage-10 Remote Worker pairing, credentials, heartbeat or network job transport;
- Stage-11 external connectors;
- Stage-12/13 Persona Co-Agent or dynamic subagent runtime.

Worker records for `remoteWorker` are therefore scheduling-domain inputs only until Stage 10 supplies authenticated live worker state.

## Merge gates

Stage 8 is complete only after:

1. focused adaptive scheduler/job lifecycle tests pass;
2. full repository analyze/test gate passes;
3. Android debug APK build passes;
4. Windows release build passes;
5. the implementation is merged to `main` and the stage tracker is updated to `DONE`.

No production release/deploy is implied by Stage 8 validation.
