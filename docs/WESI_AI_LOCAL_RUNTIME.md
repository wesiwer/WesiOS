# Wesi AI — Controlled Local Runtime

**Stage:** 6/16  
**Source of truth:** `WESI_AI_MASTER_SPEC.md` + `WESI_AI_STAGE_TRACKER.md`.

## Purpose

Wesi Local Runtime is the desktop-side controlled executor for typed Wesi AI tool calls. It does not expose a raw host shell to the model and does not install or discover dependencies; environment scanning and Runtime Packs belong to Stage 7.

## Security boundary

- desktop only (Windows/Linux/macOS);
- fail-closed capability registry with `READ`, `WRITE`, `DESTRUCTIVE` risk;
- destructive actions require trusted confirmation state outside model arguments;
- workspace-relative filesystem only; absolute paths, `..`, symlink traversal and `.wesi` internal state are blocked;
- process execution uses `runInShell: false` and does not inherit the parent process environment;
- only trusted executable bindings may be invoked; arbitrary project code requires the versioned `workspaceV1` sandbox contract plus explicit code-execution permission;
- terminal is an allowlist of logical bindings, not an arbitrary command string;
- stdout/stderr, request/response and filesystem operations are bounded by runtime limits;
- Git operations are typed and disable hooks/ext-diff/signing pathways used for uncontrolled execution;
- HTTP is HTTPS-first, strips/blocks secret-bearing headers, rejects URL credentials/private/local/metadata/reserved destinations, revalidates redirects and pins each connection to a DNS-validated public address;
- local audit records metadata only and does not persist tool arguments, paths, stdout or stderr.

## Workspace isolation

Each employee/workspace pair is mapped to SHA-256 path segments under the WesiOS application-support directory. Caller-provided names therefore never become filesystem path components.

Every model-visible filesystem path is relative to the selected workspace. The runtime rejects:

- absolute paths;
- `..` traversal;
- NUL/oversized paths;
- direct or ancestor symlink crossings;
- canonical paths resolving outside the workspace;
- the reserved `.wesi` runtime namespace.

`.wesi` stores runtime HOME/temp state, disabled Git hooks and metadata-only audit. Root directory listing hides it, and typed filesystem calls cannot address it.

## Process execution and `workspaceV1`

Processes are spawned with `runInShell: false` and `includeParentEnvironment: false`. The environment is rebuilt from a small trusted allowlist and forces HOME/USERPROFILE/TMP/TEMP into runtime-local state. Host credentials and arbitrary environment variables are not inherited.

Arbitrary project code or mutating toolchains require `WesiLocalSandboxProfile.workspaceV1`. `none` is insufficient even if the binding otherwise allows code execution.

`workspaceV1` is an attestation issued only by trusted Runtime Pack provisioning. It means the bound executable is an **OS sandbox wrapper**, not the host Python/Node/Flutter binary directly. The wrapper must enforce:

- filesystem isolation to the selected workspace;
- denial/masking of `.wesi`, host secrets and privileged paths;
- CPU, RAM, workspace-disk and wall-time limits;
- network denied by default or constrained by explicit policy;
- no Docker socket or host-session credentials.

The Stage 6 Dart executor exposes default RAM/disk/CPU limit values for that contract but does not pretend Dart alone can securely resource-cap arbitrary child processes. Stage 7 Runtime Packs are responsible for provisioning and attesting the real sandbox wrapper.

## Stage 6 tools

- filesystem: list/read/write/delete;
- terminal: allowlisted trusted bindings;
- Git: status/diff/add/commit;
- HTTP: GET/POST;
- Python and Node script execution through `workspaceV1` bindings;
- Flutter analyze/test/build through `workspaceV1` bindings;
- document/media toolchain bindings through `workspaceV1`.

There is intentionally no raw shell, arbitrary executable tool, Git push/remote credential tool, Docker socket access or production deployment action in Stage 6.

## Destructive actions

Destructive capability metadata is fixed in the local registry. The model cannot pass `confirmed=true` in tool arguments to bypass policy.

`WesiLocalRuntimeContext.destructiveConfirmed` is a trusted orchestration field only. It must be set by a higher-level confirmation flow after explicit user approval. Stage 6 applies this boundary to destructive filesystem deletion; future destructive local tools must use the same mechanism.

## HTTP / SSRF

Local HTTP defaults to HTTPS. Plain HTTP is available only through a trusted context override, never through model arguments.

Before connection the runtime:

1. rejects credentials embedded in the URL;
2. rejects localhost, `.local`, cloud metadata and special local hostnames;
3. resolves DNS;
4. rejects the destination if any resolved address is private, loopback, link-local, multicast or otherwise special, including IPv4-mapped IPv6;
5. disables proxies;
6. pins the socket to the already validated IP while requiring the same scheme, hostname and port;
7. keeps the original HTTPS URI for normal TLS hostname/certificate validation;
8. revalidates every redirect as a new destination;
9. never automatically follows a redirect after POST.

Authorization, cookies and API-key-like headers are rejected at this generic boundary. Connector credentials must later be injected by a trusted connector broker, not authored by the LLM.

## Git

Stage 6 Git is intentionally local-only:

- `status` and `diff` are read operations;
- `add` and `commit` are write operations and require the sandbox contract;
- repository hooks are disabled;
- filesystem monitor and commit signing are disabled for automated local execution;
- no push, credential, remote mutation or GitHub API action exists here.

Production GitHub integration belongs to Stage 11 connectors.

## Audit

Each local runtime session appends metadata-only JSONL audit containing call id, tool, derived risk, result code, success flag, duration and timestamp.

Arguments, paths, source text, documents, stdout/stderr and secrets are deliberately not persisted in this audit. The file is bounded/rotated.

## Stage split

- **Stage 6:** typed controlled executor and security boundary.
- **Stage 7:** Environment Scanner + Core/Developer/Browser/Documents/Media Runtime Packs; dependency reuse/install/upgrade and real `workspaceV1` sandbox provisioning.
- **Stage 8:** resource scheduler, job lifecycle, pause/resume/checkpoints.
- **Stage 9:** autonomous self-debug and validated artifact/build delivery.
- **Stage 10:** remote worker/pairing.
- **Stage 11:** authenticated external connectors such as GitHub.

Until Stage 7 supplies an attested `workspaceV1` binding, arbitrary Python/Node/Flutter/build/document/media execution remains fail-closed by design.
