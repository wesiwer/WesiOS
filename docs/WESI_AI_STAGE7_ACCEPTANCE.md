# Wesi AI — Stage 7 Acceptance

**Stage:** 7/16 — Environment Scanner + Runtime Packs  
**Branch:** `agent/wesi-ai-stage7-runtime-packs`

## Acceptance boundary

Stage 7 provides the trusted desktop provisioning layer required by the Stage-6 controlled local runtime. It does not expose package URLs, signing keys, executable paths, installer arguments, sandbox profiles, or environment variables to the model.

Implemented lifecycle:

`scan -> plan -> preview -> explicit confirmation -> verified download/install -> atomic switch -> post-install rescan -> activation`

## Security properties verified before PR

- fixed trusted probes only; no LLM shell input;
- system reuse only from absolute PATH directories;
- managed dependencies can disallow system reuse;
- deterministic `reuse/install/upgrade/unsupported` planning;
- credential-free HTTPS artifact descriptors;
- signed artifact metadata includes artifact id, platform, URL, version, SHA-256, exact sizes, install kind and paths;
- real Ed25519 verification with pinned key id;
- DNS/private/special address rejection and validated-IP pinning;
- redirects blocked for signed artifact URLs;
- exact signed download size and SHA-256 enforced;
- bounded ZIP extraction with traversal/special-entry/expansion protections;
- explicit user confirmation before mutation;
- staging + atomic verification switch;
- mandatory post-install Environment Scanner pass;
- failed post-install verification restores the previously active pack;
- `workspaceV1` execution activates only through the verified Wesi sandbox wrapper;
- Stage-6 local runtime regressions remain green.

Focused pre-PR gate: `flutter analyze --no-fatal-infos` + 22 Stage-6/7 security tests — success.

## Deliberately outside Stage 7

- resource scheduling/jobs/checkpoints: Stage 8;
- autonomous self-debug/artifact delivery: Stage 9;
- remote worker pairing/execution: Stage 10;
- connector provisioning: Stage 11;
- production release/deploy: separate explicit owner request.

Runtime artifact descriptors and public verification keys are trusted provisioning configuration. This stage does not commit live package credentials or secrets and does not fabricate production artifacts that do not yet exist.
