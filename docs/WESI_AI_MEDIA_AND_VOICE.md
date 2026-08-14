# Wesi AI — voice, generative media and rich responses

Status date: 2026-08-14.

This document records the implemented production contract for voice, image, video and music in Wesi AI. It complements `WESI_AI_SPEC.md` and `WESI_AI_GATEWAY.md`.

The client never receives provider API keys and never calls Google AI directly.

## 1. Rich response contract

Wesi AI messages can carry validated data-only content blocks in local message metadata:

- `knowledge` — verified Knowledge Base article reference;
- `table` — columns + rows;
- `chart` — line/bar/pie/scatter numerical series;
- `diagram` — nodes + directed edges;
- `media` — image/video/audio/music state and WesiOS-controlled URL.

The client does not execute model-authored HTML, JavaScript or Flutter code. Every block is parsed by `WesiAiContentBlock` with explicit bounds.

Verified Main Server tools include:

- `render_table`;
- `render_chart`;
- `render_diagram`;
- `generate_image`;
- `generate_music`;
- `generate_video` when Relay configuration is ready.

`result.contentBlock` from a verified tool is attached to the assistant message and persisted with local-first chat history.

## 2. Knowledge Base references

`knowledge_search` and `knowledge_article` remain permission-aware Main Server tools.

Knowledge cards are produced from verified server results, not arbitrary model-authored article ids. On click the client resolves the real article, rechecks current employee Knowledge permissions and opens `ArticleScreen` directly.

`knowledge_article` can read a specific permitted article for detailed summary, explanation, comparison and Q&A.

## 3. Full voice conversation — implemented

Voice is no longer only dictation.

Hands-free cycle:

```text
start conversation
→ listen
→ detect end of phrase by silence
→ auto-send exactly once
→ wait for Wesi AI
→ speak Zane/Nirvana reply
→ reopen microphone
→ repeat
```

Implemented safeguards:

- microphone and TTS do not run concurrently;
- one recognized phrase can produce only one send;
- a short breathing pause does not prematurely submit the phrase;
- barge-in/stop interrupts speech before microphone reopens;
- the UI exposes listening/thinking/speaking states;
- Lobby speaks each persona with the matching voice profile;
- if `speech_to_text` silently reaches its continuous-listening limit, the session detects the dead microphone and rearms it without leaving a fake “listening” state.

## 4. Local and natural persona voices

### Local fallback

Android uses the native `wesios/ai_speech` bridge. Windows uses `System.Speech` with base64-transported text to avoid shell interpolation.

A critical Android race is closed: `TextToSpeech.speak()` is not treated as finished when playback starts. The MethodChannel Future completes only after `UtteranceProgressListener.onDone` or an explicit stop/error, so the voice session cannot reopen the microphone while the device speaker is still talking.

### Natural voice

Preferred path when Foreign Relay is ready:

```text
WesiOS → authenticated Main /api/wesi/ai/tts
→ signed Main→Relay request
→ Gemini TTS
→ Main
→ in-memory client playback
```

The client waits until natural audio playback actually completes before returning to listening.

Default Relay voice mapping:

- Zane: `Charon`;
- Nirvana: `Sulafat`.

Both can be changed through Relay environment/secrets without releasing a new app version.

If Relay/provider/network/playback fails, the same conversation automatically falls back to the local system voice instead of becoming silent.

Natural TTS currently uses `gemini-3.1-flash-tts-preview`.

## 5. Main ↔ Relay authentication — implemented

HMAC signs:

```text
requestId + "." + timestamp + "." + rawBody
```

Relay also keeps a bounded replay cache. A valid request id is accepted once; an exact replay or a request-id substitution is rejected.

Shared transport helpers in `wesi_ai_lib.js` are used for text/media transport so different features do not independently reimplement the signing string.

## 6. Generative media architecture — implemented code-side

Production path:

```text
verified Wesi AI tool
→ Main authorization/scope
→ signed Relay provider call
→ Google AI
→ Relay short-lived artifact
→ signed one-time Main artifact fetch
→ WesiOS-controlled storage
→ WesiOS URL
→ validated media block
→ client
```

Provider credentials remain only on Foreign Relay.

### Image

`generate_image` uses `gemini-3.1-flash-image` with allowlisted aspect ratios and output sizes.

The generated image is not embedded into Hive history as provider base64. Relay converts it into a one-time artifact; Main fetches the bytes over a second signed request, checks size/MIME and stores it in WesiOS media storage.

### Music

`generate_music` uses Lyria 3 directly through the Gemini API, so a separate Vertex credential is not required:

- `lyria-3-clip-preview` — quick clip;
- `lyria-3-pro-preview` — longer composition with optional WAV output.

The same `GEMINI_API_KEY` therefore covers Wesi AI text, TTS, image, video and music provider calls.

### Video

`generate_video` starts a Veo long-running operation and immediately returns a verified pending media card. It does not keep the chat HTTP request open for the full generation time.

The client controller polls only an authenticated status URL on the configured Main Server. Arbitrary model-authored hosts/paths are rejected.

When Veo finishes:

1. Relay polls the provider operation;
2. Relay downloads the video itself using `GEMINI_API_KEY`;
3. provider download URLs are allowlisted to Google API HTTPS hosts;
4. MIME and byte limits are checked while streaming;
5. Relay creates a one-time artifact id;
6. Main fetches the binary through a new signed HMAC request;
7. Relay destroys that artifact on first retrieval;
8. Main stores the result under WesiOS ownership;
9. status changes to `ready`;
10. client replaces the pending block in persisted message metadata with the ready block.

Pending video monitoring resumes after app restart because the Main status URL is persisted in local chat history.

## 7. Relay artifact transport

Heavy image/music/video bytes are not sent in the normal Relay JSON response.

Relay media cache limits:

- short TTL;
- max item 128 MiB;
- max total 256 MiB;
- max item count;
- cryptographically random artifact ids;
- one successful read only.

The binary endpoint `/v1/wesi-ai-artifact` requires the same signed Main identity as ordinary Relay calls. nginx exposes only exact allowlisted Relay endpoints and production HTTPS setup verifies that unsigned calls are rejected.

## 8. WesiOS-owned media storage

Main Server media jobs are stored in the existing `wesios_records` backend under `coll='ai_media'`, scoped to owner and employee.

Generated binary files are stored under the PocketBase data directory, not at provider URLs. Ready files receive opaque random WesiOS tokens and an expiry timestamp.

The client sees only a WesiOS URL under `api.wesi-inc.ru`.

Current checks include:

- kind-specific MIME allowlist;
- maximum file size;
- relay-declared size consistency;
- safe filename format;
- random access token;
- expiry validation;
- employee/owner scope for job status.

## 9. Client media UI

`WesiAiMessageContent` already renders:

- image preview;
- inline video player;
- audio/music play/pause;
- pending state;
- failed state.

The chat controller now monitors verified pending media jobs and atomically replaces only the matching message block on completion. The updated metadata is persisted locally.

## 10. Message generation animation

The newest assistant text renders rune-by-rune. Completed historical messages do not reanimate when the list rebuilds or scrolls.

This is presentation-level typewriter output, not true token transport streaming. `streaming` therefore remains false in server capabilities.

## 11. Dynamic capabilities

Main `/api/wesi/ai/capabilities` reports:

- full local voice conversation independently of provider readiness;
- `naturalTts`, image/video/music/media only when `.wesi-ai-relay.json` is ready;
- `streaming: false` until real transport streaming exists.

Thus a build can safely ship before Foreign Relay deployment; provider-backed features become available after server deployment without another client release.

## 12. External activation still required

All provider/media code is prepared, but production provider calls remain inactive until the external infrastructure exists.

Remaining human-owned prerequisites are only:

1. foreign Debian/Ubuntu VPS with Node 20+, SSH/sudo and inbound 22/80/443;
2. DNS hostname pointing to it;
3. Gemini API key;
4. GitHub Secrets `WESI_RELAY_SSH_USER`, `WESI_RELAY_SSH_KEY`, `GEMINI_API_KEY`.

Then run `Deploy Wesi AI End-to-End` once with the Relay hostname. The workflow installs Relay/systemd/nginx/Let's Encrypt, validates provider text + natural TTS + anti-replay, deploys current Main hooks/personas/config to `api.wesi-inc.ru`, restarts PocketBase and verifies protected Wesi AI routes.

No manual shared-secret copying is required; when `WESI_MAIN_SHARED_SECRET` is absent, the workflow generates one and installs the same value on both sides during the atomic deployment.

## 13. Remaining production hardening after activation

Before broad/high-volume paid-media use, Budget/Quota Manager should enforce product-specific per-owner/per-employee cost limits. Current media tools are described as explicit-user-request tools and use strict size/duration/format allowlists, but arbitrary commercial quota numbers are intentionally not invented in code without a product policy.

A retention cleanup policy for expired generated files can also be added once product retention requirements are chosen. Files already carry expiry timestamps and expired links fail closed.
