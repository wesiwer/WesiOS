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
- only trusted executable bindings may be invoked; arbitrary project code requires a binding marked sandboxed and allowed for arbitrary code;
- terminal is an allowlist of logical bindings, not an arbitrary command string;
- stdout/stderr, request/response and filesystem operations are bounded by runtime limits;
- Git operations are typed and disable hooks/ext-diff/signing pathways used for uncontrolled execution;
- HTTP is HTTPS-first, strips/blocks secret-bearing headers, rejects URL credentials/private/local/metadata/reserved destinations, revalidates redirects and pins each connection to a DNS-validated public address;
- local audit records metadata only and does not persist tool arguments, stdout or stderr.

## Stage 6 tools

- filesystem: list/read/write/delete;
- terminal: allowlisted trusted bindings;
- Git: status/diff/add/commit;
- HTTP: GET/POST;
- Python and Node script execution through sandboxed bindings;
- Flutter analyze/test/build through sandboxed bindings;
- document/media toolchain bindings.

## Deliberately deferred

Stage 6 does **not** claim that Python, Node, Flutter, JDK, Android SDK, CMake, Visual Studio Build Tools, browser/document/media packages are installed. Stage 7 scans the environment, reuses compatible installations and manages Runtime Packs. Stage 8 owns resource scheduling/job lifecycle; Stage 10 owns remote workers.
