# Wesi Aero restrictive-network architecture

## Goal

Keep the VPN data plane usable on networks that allow only ordinary web traffic or a small set of destinations/ports, without lying about ownership of domains or silently depending on third-party fronting infrastructure.

The client-facing route is modeled as:

`Protocol + Backend + Transport + Topology`

The Rust tunnel supervisor remains the lifecycle authority: `StopAll -> Start -> Verify -> Connected`. A transport that merely opens a socket is not considered healthy.

## Live TCP/443 facade

The Wesi Aero hostname terminates normal TLS on Nginx. The certificate and SNI belong to Wesi Aero itself. Three long-lived transports are routed only inside this vhost:

- WebSocket over TLS/443 -> loopback `127.0.0.1:18080`.
- gRPC over TLS/443 -> loopback `127.0.0.1:18081`.
- HTTP transport over externally negotiated HTTP/2 TLS/443 -> loopback `127.0.0.1:18082`.

The loopback ports are not opened in the host firewall. Nginx strips source-IP forwarding headers and access logging remains disabled for the Wesi Aero vhost.

The current first verified Android-compatible restrictive profile is VMess + WebSocket + TLS/443. The current Android sing-box profile converter also supports VMess + gRPC. HTTP/2 exists server-side as a candidate but must not be promoted into automatic client fallback until the client representation and device E2E test are added.

## Verification

Relay deployment runs a real public-path check: a temporary sing-box client connects to the public Wesi Aero hostname on 443 using the generated VMess/WebSocket credentials and then performs an HTTPS request through the tunnel. This verifies the path:

`client -> public TLS/443 -> Nginx -> loopback transport -> sing-box -> Internet`

The security workflow additionally rejects public binds on the internal transport ports, floating supply-chain references, loss of TLS verification, source-IP proxy headers, and accidental promotion of unverified transports.

## HTTP/3 / MASQUE

Hysteria2 and TUIC use QUIC/TLS, but they are not represented as standard HTTP/3/MASQUE web proxy traffic. They remain separate QUIC-family protocols.

`MasqueH3On443` exists only as a capability marker in the core. It must remain out of the live fallback list until all of the following exist:

1. a pinned and hash/commit-verifiable MASQUE implementation;
2. Android integration using CONNECT-UDP/CONNECT-IP as appropriate;
3. a Wesi-owned TLS/HTTP3 endpoint on UDP/443;
4. public-path E2E verification;
5. leak, reconnect, roaming, and kill-switch tests.

## Trusted multi-hop

The core supports the topology marker `TrustedEdgeExit`, but a two-hop route is not advertised until a second authorized node exists.

Target topology:

`Android -> Wesi Edge :443 -> authenticated private edge-to-exit link -> Wesi Exit -> Internet`

Requirements:

- Edge nodes must be Wesi-owned or explicitly authorized by the infrastructure operator.
- The edge-to-exit link uses separate per-node credentials and authenticated encryption.
- The edge must not become an open proxy.
- Client credentials are not reused as edge-to-exit credentials.
- Exit health and edge-to-exit health are verified independently.
- Failure of either hop keeps the supervisor fail-closed.
- Control-plane metadata identifies the authorized edge/exit pair and its revision.

A CDN may be used only through a provider feature that explicitly supports the required proxy/tunnel behavior for domains and accounts controlled by Wesi. Generic domain-fronting through unrelated domains is not part of the design.

## Filtering policy

Normal networks may prefer VLESS/REALITY, QUIC protocols, or native WireGuard according to measured health. A restrictive-network policy prefers already verified Wesi TLS/443 transports and changes transport only through the supervisor lifecycle. No protocol or transport is considered connected until data-plane verification succeeds.

## Non-goals

- impersonating unrelated websites;
- presenting a third-party SNI while connecting to Wesi infrastructure without an authorized provider feature;
- depending on a public CDN as an undeclared relay;
- treating an open port, successful TLS handshake, or started `VpnService` as proof that the tunnel carries traffic.
