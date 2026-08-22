# Wesi Aero Threat Model

## Protected assets

- confidentiality/integrity of traffic between device and selected relay;
- protection from clear-net leaks during connect, handoff, failure and network changes;
- tunnel credentials, license/access tokens, server private keys and Android signing keys;
- control-plane integrity: server catalog, protocol selection, leases and payment state;
- privacy metadata such as client IP, connection time and selected relay/protocol;
- software supply-chain integrity.

## Adversaries considered

### Network observer / DPI
Can observe, delay, drop, replay and classify traffic between the device and relay. Cannot break correctly implemented modern cryptography. Countermeasures include REALITY, AmneziaWG, QUIC-based transports, authenticated control messages, replay rejection and protocol fallback.

### Malicious local network
Can manipulate DNS, captive portals and route availability. The client must not treat Android VPN creation alone as proof that protected egress works.

### Compromised relay host
A relay necessarily sees source connection metadata and plaintext of traffic that is not end-to-end encrypted above the VPN layer. The design therefore minimizes logs and plans for isolated, reproducibly rebuilt relay hosts. Multi-hop only reduces this trust when entry and exit are physically/administratively distinct.

### Control-plane attacker
May attempt credential guessing, replay, catalog manipulation, malformed profiles or administrative API access. The public facade is TLS-protected; administrative endpoints require a secret admin credential and the Node service binds to loopback behind Nginx.

### Compromised CI / dependency source
May attempt to replace Android VPN engines or build actions. Critical dependencies/actions are pinned and verification evidence is generated. A future production release process should add independent builders and signed provenance.

### Stolen/unlocked client device
May expose locally stored access credentials while unlocked. Production mode should use Android Keystore-backed wrapping and per-device revocation; a shared prototype credential is not acceptable for production.

## Trust boundaries

1. Flutter UI -> platform gateway API.
2. Kotlin/Android adapter -> Wesi Tunnel Core lifecycle state machine.
3. Wesi Tunnel Core -> Xray / sing-box / native WG-AWG engines.
4. Device -> public HTTPS control-plane facade.
5. Nginx -> loopback-only Node control plane.
6. Control plane -> encrypted credential/profile state.
7. Relay transport daemon -> public Internet.
8. GitHub Actions -> pinned upstream source/artifacts -> signed APK.

## Mandatory failure behavior

- backend start without outbound verification: remain blocked;
- verification failure: stop all backends before fallback;
- previous TUN not released before timeout: fail closed;
- network interface changes: invalidate current epoch and re-verify;
- stale callback: ignore;
- exhausted fallback chain: stop all backends and require kill switch;
- malformed or mismatched profile: reject before starting a backend;
- missing production master key: server does not start;
- missing signing credentials: release build fails;
- dependency pin mismatch: verification build fails.

## Out of scope / impossible guarantees

A VPN cannot make an already compromised endpoint safe, cannot hide traffic from the final destination, and cannot guarantee anonymity against a global passive adversary solely through a single relay. Wesi Aero must not market protocol obfuscation as equivalent to anonymity or multi-hop as effective unless hops are operationally independent.
