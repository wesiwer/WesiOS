# Wesi AI — Self-Debug & Validated Artifacts

**Stage:** 9/16  
**Source of truth:** `WESI_AI_MASTER_SPEC.md`, `WESI_AI_LOCAL_RUNTIME.md`, `WESI_AI_RESOURCE_SCHEDULER.md`, `WESI_AI_STAGE_TRACKER.md`.

## Goal

Stage 9 turns a scheduled Local Runtime job into a bounded autonomous execution cycle:

`plan -> execute -> verify -> diagnose -> repair -> re-test -> validate artifacts -> deliver`.

A model response is never proof of success. Completion requires objective tool results and artifact validation.

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

The planner/LLM cannot widen Local Runtime policy, sandbox bindings, filesystem boundaries, network permissions or destructive confirmation state.

## Verification

Development tasks use real analyze/lint/test/build/smoke tools where applicable. A failed process result becomes bounded diagnostic evidence for the next repair iteration.

The same principle applies to non-code artifacts: the output is checked by a corresponding validator before delivery.

## Artifact Gate

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

After validation, SHA-256 and size are recorded. Delivery re-hashes the source before copying, copies through a temporary file, verifies the copied hash and atomically publishes the result. A file changed after validation is rejected.

## Stage-8 integration

Self-debug progress can be mapped into the Stage-8 durable job timeline. Terminal job success/failure remains owned by trusted orchestration so an observer cannot mark a job complete before artifact delivery.

Stage 9 does not introduce Remote Worker transport. Heavy jobs still require an available foreground worker under Stage-8 scheduling policy; remote execution is Stage 10.

## Acceptance gates

Stage 9 is complete only when:

1. artifact path/symlink/checksum/delivery regressions pass;
2. repair/re-test/repeated-failure/delivery-failure regressions pass;
3. Stage 6-8 runtime/scheduler regressions remain green;
4. full repository analyze/test passes;
5. Android debug APK and Windows release builds pass;
6. the PR is merged to `main` and the stage tracker is updated to `DONE`.

No production deploy/release is implied by Stage 9 validation.
