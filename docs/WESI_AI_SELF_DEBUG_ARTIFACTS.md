# Wesi AI — Self-Debug & Validated Artifacts

**Stage:** 9/16  
**Source of truth:** `WESI_AI_MASTER_SPEC.md`, `WESI_AI_AGENT_HANDOFF.md`, `WESI_AI_LOCAL_RUNTIME.md`, `WESI_AI_RESOURCE_SCHEDULER.md`, `WESI_AI_STAGE_TRACKER.md`.

## Goal

Stage 9 turns a scheduled Local Runtime job into a bounded autonomous execution cycle:

`plan -> execute -> verify -> diagnose -> repair -> re-test -> validate artifacts -> deliver`.

A model response is never proof of success. Completion requires objective tool/process evidence, validated output and successful artifact delivery.

## Self-debug policy

`WesiSelfDebugEngine`:

- accepts only typed Stage-6 `WesiLocalToolCall` steps from the fail-closed capability registry;
- caps initial plan steps, verification steps, repair steps, total tool calls, repair iterations, evidence size, wall time and delivery attempts;
- requires at least one objective verification step before execution can be reported successful;
- re-runs the verification plan after every repair;
- validates repair-step ids and Local Runtime tool names before any repair execution;
- converts repeated identical objective failures into `WSD_REPEATED_FAILURE` instead of looping forever;
- allows the planner to report an objective blocker;
- never marks a run successful before all declared artifacts validate and delivery succeeds;
- exposes bounded progress to Stage-8 durable jobs through `WesiSelfDebugJobObserver`.

The planner/LLM cannot widen Local Runtime policy, sandbox bindings, filesystem boundaries, network permissions, executable paths or destructive-confirmation state.

## Durable execution and restart safety

Stage 9 keeps its own bounded **execution checkpoint**, but it does not create a second scheduler/job state machine. Stage-8 `WesiDurableJobQueue` remains the source of truth for `running / pauseRequested / paused / waitingForWorker / cancelling / cancelled / succeeded / failed`.

`WesiSelfDebugCheckpointManager` persists only bounded orchestration state:

- request id and deterministic SHA-256 plan fingerprint;
- repair-plan fingerprints by iteration;
- current phase/step/iteration and tool-call budget;
- bounded redacted outcomes;
- the in-flight step key and trusted `WesiLocalRisk`;
- schema version/revision/timestamp.

Raw planner tool arguments are not copied into the durable checkpoint journal.

Recovery rules are fail-closed:

- completed steps are restored from persisted outcomes and are not executed twice;
- an interrupted `READ` step may be retried because it has no write side effect;
- an interrupted `WRITE`/`DESTRUCTIVE` step becomes `WSD_UNCERTAIN_SIDE_EFFECT` and is **not** repeated automatically;
- a changed plan after restart becomes `WSD_PLAN_CHANGED_AFTER_RESTART`;
- a changed repair plan for an already checkpointed iteration is rejected;
- malformed, oversized or unknown checkpoint state is rejected rather than partially accepted.

The file checkpoint journal is bounded and uses a same-directory temporary file plus previous-file recovery so an interrupted swap cannot silently create a fabricated clean state.

## Stage-8 pause/cancel/worker-loss integration

`WesiSelfDebugJobControl` bridges Stage 9 to the existing Stage-8 coordinator:

- `pauseRequested` -> persist a current Stage-8 checkpoint -> `paused` -> return `WSD_PAUSED`;
- `cancelling` -> `cancelled` -> stop before another tool call;
- `waitingForWorker` -> return `WSD_WAITING_FOR_WORKER` without server fallback;
- explicit worker loss first persists a current Stage-8 checkpoint and then enters `waitingForWorker`;
- queued/blocked/terminal jobs cannot masquerade as active self-debug execution.

Stage-9 progress uses checkpoint-safe Stage-8 stage tokens such as `self_debug.verifying.i1`; arbitrary human messages are not written into the Stage-8 checkpoint `stage` field.

Heavy L3/L4 work still requires the actual foreground execution worker. Stage 9 never moves a build/render/runtime job to the Control Plane merely because the worker disappeared.

## Verification and evidence handling

Development tasks use real analyze/lint/test/build/smoke tools where applicable. A failed process result becomes bounded diagnostic evidence for the next repair iteration.

Evidence is bounded before planner/review exposure and passes through `WesiSelfDebugRedactor`. Common credential forms (Authorization Bearer/Basic, token/password/API-key/secret fields, GitHub PAT-like tokens, `sk-` keys, AWS access-key ids and JWT-like values) are redacted rather than persisted or echoed as diagnostic text.

The same objective-verification principle applies to non-code artifacts: the output is checked by a corresponding validator before delivery.

## Build proof

Deliverable build artifacts cannot be accepted from a model assertion or from file existence alone.

`WesiArtifactDescriptor.requiredSuccessfulStepId` binds an artifact to an objective verification step. APK and Windows executable artifacts **must** reference a successful `local.flutter.build` verification step. If that build step is missing, has the wrong tool, or failed, artifact validation/delivery does not run and the task cannot report success.

## Artifact gate

Every artifact has a typed descriptor and must resolve to a regular file inside the selected workspace.

The validator rejects:

- absolute paths and path traversal;
- protected `.wesi` state;
- symlink escape outside the workspace;
- missing, empty or oversized artifacts;
- mismatched simple-format signatures;
- complex formats without a trusted external validator.

Built-in prechecks cover bounded UTF-8 text, JSON, PDF/ZIP/PE/image/audio signatures. Only UTF-8 text, JSON, PNG and JPEG may pass without a second validator.

PDF/ZIP/source archives, DOCX/XLSX/PPTX/APK, Windows executables, WAV/MP3, video and unknown formats require a trusted external validator after the built-in precheck. File extension, magic bytes or model assertion alone are insufficient.

### TOCTOU protection

Before external validation, the validator records the canonical path, regular-file status, size and SHA-256. After external validation it resolves/stat/hashes the artifact again. If path identity, type, size or digest changed, validation fails with `ARTIFACT_CHANGED_DURING_VALIDATION`.

This prevents an external validator from approving one file while another file is subsequently registered as the validated result.

## Delivery

After validation, SHA-256 and size are recorded. Delivery:

1. re-hashes the workspace source and rejects a post-validation mutation;
2. copies through a temporary file;
3. verifies the copied hash;
4. atomically publishes the result.

Delivery is restart-idempotent: if the final delivery target already exists with the **same validated SHA-256**, it is returned as the same successful delivery instead of producing a duplicate. An existing target with different contents remains a collision failure.

## Acceptance regressions

Stage-9 focused validation covers, among other cases:

- failure -> repair -> re-test -> success;
- repeated objective failure -> bounded blocker;
- missing objective verification -> no success;
- unknown execution/repair tool -> no executor bypass;
- crash after a completed WRITE -> restart skips that WRITE and safely retries interrupted READ;
- crash while WRITE/DESTRUCTIVE is in flight -> `WSD_UNCERTAIN_SIDE_EFFECT`, no duplicate side effect;
- Stage-8 cancel stops future tool calls;
- pause -> durable checkpoint -> resume;
- L4 worker loss -> current checkpoint -> `waitingForWorker`;
- changed plan after restart -> blocker;
- secret redaction in failure evidence;
- APK without build proof -> rejected;
- failed build proof -> no artifact delivery;
- path/symlink/size/type validation;
- artifact mutation during external validation -> rejected;
- repeated delivery of the same validated hash -> idempotent success;
- Stage 6/7/8 security and scheduler regressions remain green.

## Stage boundary

Stage 9 implements local self-debug orchestration and validated artifact delivery. It does **not** implement Stage-10 authenticated Remote Worker pairing/heartbeat/transport, Stage-11 external connectors, Stage-12 Persona Co-Agent runtime or Stage-13 dynamic subagents.

## Merge gates

Stage 9 is complete only when:

1. focused Stage 6-9 security/durability tests pass;
2. full repository analyze/test gate passes;
3. Android debug APK build passes;
4. Windows release build passes;
5. the final exact PR head is unchanged between those gates and merge;
6. the PR is merged to `main` and the stage tracker is updated to `DONE`.

No production deploy/release is implied by Stage 9 validation.
