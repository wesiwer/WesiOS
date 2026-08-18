# Wesi AI — Go-Live Checklist

This document is the handoff from repository-ready state to live testing. The application and Wesi AI client do **not** need provider secrets: the Flutter client talks only to the authenticated WesiOS Main Server at `https://api.wesi-inc.ru`. Provider credentials stay on the server side.

## 1. GitHub Secrets to add

### Required

| Secret | Purpose |
| --- | --- |
| `GEMINI_API_KEY` | Google Gemini provider access used by the foreign Wesi AI Relay. |
| `WESI_RELAY_SSH_USER` | SSH user on the foreign Relay server. Must be able to use the deployment scripts' required `sudo` commands non-interactively. |
| `WESI_RELAY_SSH_KEY` | Private SSH key for the foreign Relay server. Store the complete multiline key. |
| `WESI_SERVER_HOST` | SSH hostname or IP of the existing Main WesiOS/PocketBase server. |
| `WESI_SERVER_USER` | SSH user on the Main WesiOS server. |
| `WESI_SERVER_SSH_KEY` | Private SSH key for the Main WesiOS server. Store the complete multiline key. |

### Strongly recommended

| Secret | Purpose |
| --- | --- |
| `WESI_MAIN_SHARED_SECRET` | Stable HMAC secret shared only by Main Server and Relay. Use at least 32 random characters. If omitted, deployment generates a new secret and installs it atomically on both servers. |
| `WESI_RELAY_SSH_HOST` | SSH host for the Relay when it differs from the public DNS name. If omitted, deploy uses the `public_host` workflow input. |
| `WESI_RELAY_SSH_KNOWN_HOSTS` | Pinned SSH host key for the Relay. Without it the deploy workflow uses `ssh-keyscan` at deployment time. |
| `WESI_SERVER_KNOWN_HOSTS` | Pinned SSH host key for the Main server. Without it the deploy workflow uses `ssh-keyscan` at deployment time. |

### Optional voice overrides

| Secret | Purpose |
| --- | --- |
| `WESI_ZANE_TTS_VOICE` | Explicit provider voice for Zane. |
| `WESI_NIRVANA_TTS_VOICE` | Explicit provider voice for Nirvana. |

No Gemini key, Relay HMAC secret or SSH credential should be added to Flutter source code, app assets, `dart-define`, Firebase config, or any client-visible file.

## 2. Before either server is available

After adding the Secrets, run the GitHub Actions workflow **Wesi AI Preflight**.

It intentionally makes no SSH, DNS, HTTPS, Gemini, or production-server connection. It checks:

- presence of every required GitHub Secret;
- basic non-disclosing shape checks for provider and SSH credentials;
- Wesi AI persona generation;
- JavaScript syntax of the Main Server hooks and Relay modules;
- Relay unit tests;
- shell syntax of Relay deployment scripts;
- presence of the production deployment workflow.

A green preflight means the repository and GitHub secret set are ready. It does **not** claim the unavailable servers or DNS are healthy.

## 3. Server/DNS prerequisites

Before production deployment:

1. The foreign Relay Linux server must be reachable over SSH using `WESI_RELAY_SSH_USER` + `WESI_RELAY_SSH_KEY` and support the `sudo` operations used by `server/wesi-ai-relay/deploy-relay.sh` and `configure-relay-https.sh`.
2. A public DNS hostname must point to the foreign Relay server. Pass this hostname, without `https://` or a path, as `public_host` to the production workflow.
3. Ports required for HTTPS certificate issuance and serving (normally TCP 80/443) must be reachable on the Relay.
4. The Main WesiOS server must be reachable using `WESI_SERVER_HOST`, `WESI_SERVER_USER`, and `WESI_SERVER_SSH_KEY`.
5. The Main server must have the existing PocketBase installation expected at `/opt/pocketbase`, with a systemd service named `pocketbase`.
6. The Main server must be able to reach the public Relay hostname over HTTPS.

## 4. One production action

Run GitHub Actions → **Deploy Wesi AI End-to-End** (`.github/workflows/deploy-wesi-ai.yml`) and enter the Relay DNS hostname into `public_host`.

The workflow performs the complete sequence:

1. validates required configuration and the source bundle;
2. resolves one Main↔Relay HMAC secret;
3. installs the Relay and HTTPS configuration;
4. checks Relay `/health` readiness;
5. makes a real Gemini text request;
6. verifies replay protection by intentionally replaying a signed request and requiring rejection;
7. makes a real natural-TTS request;
8. installs Wesi AI hooks, personas and Relay configuration on the Main server;
9. restarts PocketBase;
10. confirms Main→Relay connectivity and that protected Wesi AI routes are loaded.

If this workflow is green, server-side Wesi AI is ready for application testing.

## 5. First application smoke test

Use a normal authenticated WesiOS account. The client already routes Wesi AI through the Main server and uses the existing WesiOS token plus revocable session id; it does not contact Gemini directly.

Test in this order:

1. Open Wesi AI and send one message to Zane in **Fast** mode.
2. Repeat with **Pro** and **Maximum** modes.
3. Open Nirvana and verify persona separation.
4. Open Lobby and verify multi-persona responses.
5. Start a voice session: listen → detect end-of-phrase → send → persona TTS → listen again.
6. Verify Zane and Nirvana use their own voice selections.
7. Generate/poll one supported media job and verify the client accepts only Main Server media-status URLs.
8. Close/reopen the app and verify local conversation continuity and employee-scoped memory behavior.
9. Exercise the explicit Zane↔Nirvana handoff flow and verify it occurs only with consent.
10. Sign out/revoke the session and verify Wesi AI cannot continue using the old session.

## 6. Expected failure messages before go-live

Before the server side is deployed, the application may correctly show one of these states instead of crashing:

- Wesi AI is not connected to the model server (`WAI_RELAY_NOT_CONFIGURED`);
- persona engine is not ready (`WAI_PERSONA_ENGINE_NOT_READY`);
- Wesi AI service is temporarily unavailable (`WAI_RELAY_UNAVAILABLE`);
- user must sign in (`NOT_SIGNED_IN`);
- no network connection (`NETWORK`).

These are readiness states, not reasons to put provider secrets into the client.

## 7. Security invariants

- Provider keys remain only in GitHub Secrets and the Relay server's protected runtime configuration.
- Main↔Relay requests are HMAC-signed over request id + timestamp + body.
- Replay protection remains enabled in production.
- Main WesiOS authentication remains the only client entry point to Wesi AI.
- Media polling accepts only same-origin Main Server status URLs produced by verified tools.
- SSH known-host values should be pinned before final production use rather than relying indefinitely on first-seen `ssh-keyscan` output.
