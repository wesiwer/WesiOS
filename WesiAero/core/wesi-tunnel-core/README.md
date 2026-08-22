# Wesi Tunnel Core

`wesi-tunnel-core` is the lifecycle/policy core for Wesi Aero. It is intentionally **not** a new VPN protocol or cryptographic implementation.

## Trust boundary

The Rust core owns:

- one monotonic connection epoch so stale asynchronous callbacks cannot resurrect an old tunnel;
- exclusive TUN handoff ordering (`StopAll -> TUN released -> Start`);
- mandatory outbound verification before `Connected`;
- deterministic protocol/backend fallback;
- fail-closed state when every route fails;
- network-change invalidation and reconnect policy.

Existing audited/upstream engines continue to own protocol crypto and packet transport:

- Xray for VLESS/REALITY and VMess where selected;
- sing-box for supported proxy/QUIC transports;
- the native WireGuard/AmneziaWG backend for the WireGuard family.

## Integration phases

1. **Core state machine (current):** pure Rust, no third-party crates, unit-tested deterministic transitions.
2. **Android adapter:** JNI/Kotlin maps core `Action` values to existing `VpnService` backends. Kotlin must no longer independently decide that a tunnel is connected.
3. **Platform kill switch:** `BlockTraffic` maps to platform fail-closed routing / Android lockdown semantics.
4. **Policy telemetry:** network capabilities and health scores select routes without exposing user traffic metadata to the control plane.

Until phase 2 is completed and device-tested, this crate is a security foundation rather than a claim that the Android runtime has already migrated to Rust.
