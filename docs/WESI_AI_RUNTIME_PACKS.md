# Wesi AI — Environment Scanner & Runtime Packs

**Stage:** 7/16  
**Source of truth:** `WESI_AI_MASTER_SPEC.md`, `WESI_AI_LOCAL_RUNTIME.md`, `WESI_AI_STAGE_TRACKER.md`.

## Goal

Stage 7 turns the Stage-6 fail-closed Local Runtime into a capability system that can safely reuse compatible desktop dependencies or install only what is missing/incompatible.

The model does not choose executable paths, package URLs, checksums, signing keys, installer arguments, sandbox profiles or environment variables. Those values belong to trusted WesiOS runtime provisioning.

## Packs

- **Core Runtime** — Git, archive tools and the Wesi `workspaceV1` sandbox provider.
- **Developer Pack** — Python, Node.js, JDK, Flutter/Dart, Android SDK/platform tools, CMake and Windows C++ Build Tools.
- **Browser Pack** — Wesi-managed Chromium foundation; system Chrome is not silently reused for automation.
- **Documents Pack** — Wesi-managed document creation/validation toolchain.
- **Media Pack** — FFmpeg/media processing foundation.

Full Visual Studio IDE is not a requirement. Windows native builds target Visual Studio Build Tools with the required C++ workload/components.

## Environment Scanner

The scanner is trusted application code, not a model tool. It:

1. resolves only fixed dependency executable names from trusted managed paths or absolute directories in the system `PATH`;
2. runs only fixed version/probe arguments declared in the Runtime Pack catalog;
3. does not accept shell commands from the LLM;
4. bounds probe runtime and captured output;
5. extracts the real version/path;
6. compares versions numerically;
7. returns compatibility state.

Relative `PATH` entries are ignored so an executable in the application working directory cannot impersonate a system runtime. A managed dependency with `allowSystemReuse=false` is never satisfied by an arbitrary executable found on `PATH`.

## Planning

Every dependency becomes exactly one action:

- `reuse` — detected and compatible;
- `install` — missing and a managed artifact exists;
- `upgrade` — detected but incompatible and a managed artifact exists;
- `unsupported` — platform unsupported or no controlled installation path exists.

Compatible system Python/Node/Flutter/JDK/etc. are reused instead of downloaded again.

## Signed artifact boundary

A managed artifact descriptor is trusted only when all of the following hold:

- credential-free HTTPS URL;
- exact platform/artifact id match;
- signed metadata with pinned Ed25519 public key id;
- signed payload binds the artifact URL, version, SHA-256, exact sizes, install kind and paths;
- exact declared download size;
- SHA-256 of downloaded bytes matches the signed descriptor;
- install paths are relative and remain under the WesiOS managed runtime root.

Generic runtime downloads do not receive cookies, API keys or connector secrets. DNS/private-address checks and validated-address pinning are applied before download. Redirects are rejected for signed artifact URLs.

ZIP extraction is bounded by entry count, signed installed-size limit and an in-process archive size ceiling. Absolute paths, traversal and special/symlink-like entries are rejected. Archive entries are materialized only as regular files/directories under the managed runtime directory.

## Install and post-install verification

Installation is explicit: WesiOS first creates an install preview containing download size, disk footprint and permissions, and requires trusted user confirmation.

After installation the Environment Scanner runs again. A Runtime Pack is not activated merely because files were copied: all non-optional dependencies must be detected and compatible in the post-install scan.

Installation uses a staging directory and atomic verification switch. If post-install verification fails, WesiOS removes the failed candidate and restores the previously active pack.

## `workspaceV1` activation

Stage 6 intentionally rejects arbitrary Python/Node/Flutter/build/document/media execution unless a binding carries `WesiLocalSandboxProfile.workspaceV1`.

Stage 7 makes that profile concrete:

- `executablePath` is the trusted Wesi sandbox wrapper;
- `sandboxTargetPath` is the verified real Python/Node/Flutter/etc. executable;
- the Stage-6 executor prepends trusted workspace/CPU/RAM/disk/time/network limits before the model-derived arguments;
- model arguments appear only after the wrapper separator and cannot change the wrapper target or limits.

The `wesi-sandbox` provider itself is Wesi-managed and must pass its fixed `--contract-version` probe. A Developer/Documents/Media binding cannot activate without a verified Core sandbox provider.

## Provisioning configuration

Live runtime artifact descriptors and pinned Ed25519 public verification keys are trusted provisioning configuration. Stage 7 supplies the verified catalog/manager interfaces and does not commit package credentials, private signing material, or fabricated production artifacts. A missing signed artifact remains fail-closed as `WRP_ARTIFACT_UNAVAILABLE` rather than falling back to an arbitrary download.

## Stage boundary

Stage 7 owns dependency discovery, reuse/install/upgrade, artifact integrity and Runtime Pack activation.

It does **not** own job scheduling, L0–L4 resource classification, checkpoints/pause/resume (Stage 8), autonomous repair/delivery (Stage 9), Remote Worker pairing (Stage 10) or external connectors (Stage 11).
