# Wesi Aero Security

This document describes security properties that the implementation must preserve. It is not an external audit or certification.

## Security invariants

1. **Fail closed.** The client must never report `Connected` until traffic through the selected backend has been independently verified. A failed/expired handoff keeps traffic blocked.
2. **One TUN owner.** Xray, sing-box and the native WireGuard-family backend may not own competing Android VPN interfaces during a transition.
3. **Reject stale callbacks.** Every asynchronous lifecycle event belongs to a connection epoch. Events from an older epoch are ignored.
4. **Exact protocol profiles.** WireGuard and AmneziaWG credentials are never substituted for one another. VMess filename compatibility is allowed only because `vmess` and `vmess-xray` describe the same wire protocol in this project.
5. **Privacy by default.** Public control-plane access logs and technical request logs are disabled unless explicitly enabled for a bounded diagnostic session.
6. **Secrets stay server-side.** Relay private keys, payment secrets, admin credentials and master encryption keys must never be committed or printed by CI.
7. **Authenticated encryption.** Secrets at rest and secure control-plane envelopes use authenticated encryption; replayed secure requests are rejected.
8. **No implicit development security.** Production-like startup requires a real master key. Mock payments and technical logging are opt-in.
9. **Pinned supply chain.** Security-critical build inputs must be pinned to a version/commit or cryptographic digest and checked by CI.
10. **Release identity.** Android releases are signed with the permanent release key and accompanied by SHA-256 build evidence.

## Current cryptographic boundaries

Wesi Aero does not invent transport cryptography. Protocol crypto remains in upstream Xray, sing-box and WireGuard/AmneziaWG implementations. The Wesi Tunnel Core coordinates lifecycle, policy, verification and fail-closed behavior only.

The control plane uses AES-256-GCM for encrypted secret storage and HKDF-SHA256 + AES-256-GCM for application-level secure envelopes. License/access secrets are stored using salted scrypt-derived hashes where verification rather than recovery is required.

## Known prototype limitations

These items block any claim of production-grade anonymity/security until resolved:

- default relay tunnel profiles are currently static/shared instead of per-device credentials;
- the prototype APK receives a shared prototype license at build time;
- the current relay is a conventional single VPS, not an immutable RAM-only/diskless fleet;
- there is no independent third-party security audit yet;
- Android migration to `wesi-tunnel-core` is staged: the Rust state machine exists before the JNI/Kotlin adapter replaces lifecycle decisions in Kotlin;
- provider-side UDP/51821 must be opened before AmneziaWG can pass an external handshake/egress test.

## Production gates

Before production billing/access is enabled, all of the following are required:

- per-device/per-session tunnel credentials with revocation and rotation;
- no shared prototype license embedded in release APKs;
- platform kill-switch/lockdown tests across Wi-Fi/LTE changes, sleep/wake and process death;
- DNS, IPv4 and IPv6 leak tests on physical devices;
- at least two independently operated relay locations before any feature is described as multi-hop;
- immutable or reproducibly rebuilt relay images with ephemeral runtime secrets where feasible;
- SBOM/build manifest and reproducibility instructions for every release;
- external security review of Android client, control plane and relay image.

## Logging policy

Normal operation must not record browsing destinations, DNS queries, packet payloads or per-user traffic history. Diagnostic logging must be explicit, time-bounded and redact credentials. Public Nginx access logging for the control plane is disabled by default.
