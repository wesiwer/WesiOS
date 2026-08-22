#![forbid(unsafe_code)]

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Protocol {
    VlessReality,
    Vmess,
    Trojan,
    Shadowsocks,
    Hysteria2,
    Tuic,
    WireGuard,
    AmneziaWg,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Backend {
    Xray,
    SingBox,
    Native,
}

/// Wire shape used between the device and the first Wesi-controlled hop.
///
/// `MasqueH3On443` is a reserved capability marker. It must not be advertised
/// as live until a pinned MASQUE/HTTP3 implementation and its independent
/// end-to-end verification exist in the platform adapter and relay CI.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Transport {
    Direct,
    TlsWebSocket443,
    TlsGrpc443,
    TlsHttp2On443,
    Quic,
    MasqueH3On443,
}

impl Transport {
    pub const fn is_live_tcp_443(self) -> bool {
        matches!(
            self,
            Self::TlsWebSocket443 | Self::TlsGrpc443 | Self::TlsHttp2On443
        )
    }
}

/// Network topology after the client-facing transport is established.
///
/// `TrustedEdgeExit` is intentionally generic: the runtime may only instantiate
/// it with Wesi-owned or explicitly authorized nodes whose edge-to-exit link is
/// authenticated. The core never treats an arbitrary CDN or third-party host as
/// an implicit hop.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Topology {
    SingleHop,
    TrustedEdgeExit,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Route {
    pub protocol: Protocol,
    pub backend: Backend,
    pub transport: Transport,
    pub topology: Topology,
}

impl Route {
    pub const fn new(protocol: Protocol, backend: Backend) -> Self {
        Self {
            protocol,
            backend,
            transport: Transport::Direct,
            topology: Topology::SingleHop,
        }
    }

    pub const fn with_transport(self, transport: Transport) -> Self {
        Self { transport, ..self }
    }

    pub const fn via_trusted_edge(self) -> Self {
        Self {
            topology: Topology::TrustedEdgeExit,
            ..self
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TunnelState {
    Idle,
    Stopping,
    Starting,
    Verifying,
    Connected,
    Faulted,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FailureReason {
    StartFailed,
    VerificationFailed,
    Timeout,
    NetworkChanged,
    BackendDidNotReleaseTun,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    StopAll { epoch: u64 },
    Start { epoch: u64, route: Route },
    Verify { epoch: u64, route: Route },
    BlockTraffic { epoch: u64, reason: FailureReason },
    Connected { epoch: u64, route: Route },
    Idle { epoch: u64 },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Snapshot {
    pub epoch: u64,
    pub state: TunnelState,
    pub route: Option<Route>,
    pub fallback_remaining: usize,
    pub kill_switch_required: bool,
}

/// Owns lifecycle ordering for all VPN backends.
///
/// The supervisor deliberately does not implement protocol cryptography. It
/// serializes ownership of the platform TUN, rejects stale async callbacks, and
/// only reaches Connected after a separate health verification step succeeds.
pub struct TunnelSupervisor {
    epoch: u64,
    state: TunnelState,
    route: Option<Route>,
    fallback: Vec<Route>,
    fallback_index: usize,
    disconnect_requested: bool,
    kill_switch_required: bool,
}

impl Default for TunnelSupervisor {
    fn default() -> Self {
        Self {
            epoch: 0,
            state: TunnelState::Idle,
            route: None,
            fallback: Vec::new(),
            fallback_index: 0,
            disconnect_requested: false,
            kill_switch_required: false,
        }
    }
}

impl TunnelSupervisor {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn snapshot(&self) -> Snapshot {
        Snapshot {
            epoch: self.epoch,
            state: self.state,
            route: self.route,
            fallback_remaining: self.fallback.len().saturating_sub(self.fallback_index),
            kill_switch_required: self.kill_switch_required,
        }
    }

    /// Starts a connection attempt. Traffic must remain blocked until the
    /// emitted Verify action has succeeded and Connected is emitted.
    pub fn connect(&mut self, primary: Route, fallback: impl Into<Vec<Route>>) -> Vec<Action> {
        self.epoch = self.epoch.wrapping_add(1).max(1);
        self.state = TunnelState::Stopping;
        self.route = Some(primary);
        self.fallback = fallback.into();
        self.fallback_index = 0;
        self.disconnect_requested = false;
        self.kill_switch_required = true;
        vec![Action::StopAll { epoch: self.epoch }]
    }

    /// Explicit disconnect is the only normal path that releases the
    /// fail-closed requirement without first proving another tunnel healthy.
    pub fn disconnect(&mut self) -> Vec<Action> {
        self.epoch = self.epoch.wrapping_add(1).max(1);
        self.state = TunnelState::Stopping;
        self.route = None;
        self.fallback.clear();
        self.fallback_index = 0;
        self.disconnect_requested = true;
        self.kill_switch_required = true;
        vec![Action::StopAll { epoch: self.epoch }]
    }

    /// Platform layer calls this only after every prior VpnService/backend has
    /// actually released the TUN. Stale acknowledgements are ignored.
    pub fn backends_stopped(&mut self, epoch: u64) -> Vec<Action> {
        if epoch != self.epoch || self.state != TunnelState::Stopping {
            return Vec::new();
        }
        if self.disconnect_requested || self.route.is_none() {
            self.state = TunnelState::Idle;
            self.kill_switch_required = false;
            return vec![Action::Idle { epoch }];
        }
        self.state = TunnelState::Starting;
        vec![Action::Start {
            epoch,
            route: self.route.expect("route checked above"),
        }]
    }

    /// Starting a backend is not connection success. The next mandatory step
    /// is independent outbound verification through that backend.
    pub fn backend_started(&mut self, epoch: u64) -> Vec<Action> {
        if epoch != self.epoch || self.state != TunnelState::Starting {
            return Vec::new();
        }
        let Some(route) = self.route else {
            return Vec::new();
        };
        self.state = TunnelState::Verifying;
        vec![Action::Verify { epoch, route }]
    }

    pub fn verified(&mut self, epoch: u64, healthy: bool) -> Vec<Action> {
        if epoch != self.epoch || self.state != TunnelState::Verifying {
            return Vec::new();
        }
        if !healthy {
            return self.fail(epoch, FailureReason::VerificationFailed);
        }
        let Some(route) = self.route else {
            return Vec::new();
        };
        self.state = TunnelState::Connected;
        self.kill_switch_required = false;
        vec![Action::Connected { epoch, route }]
    }

    pub fn backend_failed(&mut self, epoch: u64, reason: FailureReason) -> Vec<Action> {
        if epoch != self.epoch {
            return Vec::new();
        }
        self.fail(epoch, reason)
    }

    /// Network changes invalidate the current route and its verification. A
    /// stale callback from the previous path cannot reconnect it because the
    /// epoch changes before the handoff begins.
    pub fn network_changed(&mut self) -> Vec<Action> {
        if matches!(self.state, TunnelState::Idle | TunnelState::Faulted) {
            return Vec::new();
        }
        let epoch = self.epoch;
        self.fail(epoch, FailureReason::NetworkChanged)
    }

    fn fail(&mut self, epoch: u64, reason: FailureReason) -> Vec<Action> {
        if epoch != self.epoch {
            return Vec::new();
        }

        self.kill_switch_required = true;
        if self.fallback_index < self.fallback.len() {
            let next = self.fallback[self.fallback_index];
            self.fallback_index += 1;
            // A new epoch makes every late callback from the failed backend
            // harmless, even if the fallback uses the same protocol engine.
            self.epoch = self.epoch.wrapping_add(1).max(1);
            self.route = Some(next);
            self.state = TunnelState::Stopping;
            return vec![Action::StopAll { epoch: self.epoch }];
        }

        self.state = TunnelState::Faulted;
        vec![
            Action::StopAll { epoch: self.epoch },
            Action::BlockTraffic {
                epoch: self.epoch,
                reason,
            },
        ]
    }
}

/// Conservative normal-network path: VLESS/REALITY first, raw VMess as a TCP
/// compatibility fallback, then native WireGuard when UDP works.
pub fn default_routes() -> (Route, Vec<Route>) {
    (
        Route::new(Protocol::VlessReality, Backend::Xray),
        vec![
            Route::new(Protocol::Vmess, Backend::Xray),
            Route::new(Protocol::WireGuard, Backend::Native),
        ],
    )
}

/// Strict-filtering path that is already supported by the pinned Android
/// sing-box adapter and the Wesi-owned TLS/443 facade. HTTP/2 is intentionally
/// exposed separately until the Android profile parser is promoted to the same
/// independently verified status.
pub fn restrictive_tcp_443_routes() -> (Route, Vec<Route>) {
    (
        Route::new(Protocol::Vmess, Backend::SingBox).with_transport(Transport::TlsWebSocket443),
        vec![Route::new(Protocol::Vmess, Backend::SingBox)
            .with_transport(Transport::TlsGrpc443)],
    )
}

pub const fn restrictive_http2_candidate() -> Route {
    Route::new(Protocol::Vmess, Backend::SingBox).with_transport(Transport::TlsHttp2On443)
}

/// Same client-facing TLS/443 policy for a future two-hop deployment. Runtime
/// code must only select these routes after both Wesi Edge and Wesi Exit have
/// authenticated configuration and independent health checks.
pub fn trusted_edge_tcp_443_routes() -> (Route, Vec<Route>) {
    let (primary, fallback) = restrictive_tcp_443_routes();
    (
        primary.via_trusted_edge(),
        fallback.into_iter().map(Route::via_trusted_edge).collect(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn connect_to_verification(core: &mut TunnelSupervisor) -> u64 {
        let primary = Route::new(Protocol::VlessReality, Backend::Xray);
        assert!(matches!(
            core.connect(primary, Vec::new()).as_slice(),
            [Action::StopAll { .. }]
        ));
        let epoch = core.snapshot().epoch;
        assert_eq!(
            core.backends_stopped(epoch),
            vec![Action::Start {
                epoch,
                route: primary
            }]
        );
        assert_eq!(
            core.backend_started(epoch),
            vec![Action::Verify {
                epoch,
                route: primary
            }]
        );
        epoch
    }

    #[test]
    fn never_reports_connected_before_health_verification() {
        let mut core = TunnelSupervisor::new();
        let epoch = connect_to_verification(&mut core);
        assert_eq!(core.snapshot().state, TunnelState::Verifying);
        assert!(core.snapshot().kill_switch_required);
        let actions = core.verified(epoch, true);
        assert!(matches!(actions.as_slice(), [Action::Connected { .. }]));
        assert_eq!(core.snapshot().state, TunnelState::Connected);
        assert!(!core.snapshot().kill_switch_required);
    }

    #[test]
    fn stale_callback_cannot_resurrect_failed_backend() {
        let mut core = TunnelSupervisor::new();
        let primary = Route::new(Protocol::VlessReality, Backend::Xray);
        let fallback = Route::new(Protocol::Vmess, Backend::Xray);
        core.connect(primary, vec![fallback]);
        let old_epoch = core.snapshot().epoch;
        core.backends_stopped(old_epoch);
        core.backend_started(old_epoch);
        core.verified(old_epoch, false);
        let new_epoch = core.snapshot().epoch;
        assert_ne!(old_epoch, new_epoch);
        assert!(core.verified(old_epoch, true).is_empty());
        assert_ne!(core.snapshot().state, TunnelState::Connected);
    }

    #[test]
    fn failed_verification_serializes_fallback_through_stop_all() {
        let mut core = TunnelSupervisor::new();
        let primary = Route::new(Protocol::VlessReality, Backend::Xray);
        let fallback = Route::new(Protocol::WireGuard, Backend::Native);
        core.connect(primary, vec![fallback]);
        let epoch = core.snapshot().epoch;
        core.backends_stopped(epoch);
        core.backend_started(epoch);
        let actions = core.verified(epoch, false);
        let fallback_epoch = core.snapshot().epoch;
        assert_eq!(
            actions,
            vec![Action::StopAll {
                epoch: fallback_epoch
            }]
        );
        assert_eq!(core.snapshot().route, Some(fallback));
        assert_eq!(core.snapshot().state, TunnelState::Stopping);
        assert!(core.snapshot().kill_switch_required);
    }

    #[test]
    fn exhausted_fallbacks_fail_closed() {
        let mut core = TunnelSupervisor::new();
        let epoch = connect_to_verification(&mut core);
        let actions = core.verified(epoch, false);
        assert!(matches!(
            actions.as_slice(),
            [
                Action::StopAll { .. },
                Action::BlockTraffic {
                    reason: FailureReason::VerificationFailed,
                    ..
                }
            ]
        ));
        assert_eq!(core.snapshot().state, TunnelState::Faulted);
        assert!(core.snapshot().kill_switch_required);
    }

    #[test]
    fn explicit_disconnect_ignores_old_connected_event() {
        let mut core = TunnelSupervisor::new();
        let epoch = connect_to_verification(&mut core);
        core.verified(epoch, true);
        core.disconnect();
        let disconnect_epoch = core.snapshot().epoch;
        assert!(core.verified(epoch, true).is_empty());
        assert_eq!(
            core.backends_stopped(disconnect_epoch),
            vec![Action::Idle {
                epoch: disconnect_epoch
            }]
        );
        assert_eq!(core.snapshot().state, TunnelState::Idle);
        assert!(!core.snapshot().kill_switch_required);
    }

    #[test]
    fn restrictive_policy_falls_back_between_verified_tls_443_transports() {
        let (primary, fallback) = restrictive_tcp_443_routes();
        assert_eq!(primary.protocol, Protocol::Vmess);
        assert_eq!(primary.backend, Backend::SingBox);
        assert_eq!(primary.transport, Transport::TlsWebSocket443);
        assert!(primary.transport.is_live_tcp_443());
        assert_eq!(fallback.len(), 1);
        assert_eq!(fallback[0].transport, Transport::TlsGrpc443);
        assert!(fallback[0].transport.is_live_tcp_443());
        assert_eq!(primary.topology, Topology::SingleHop);
    }

    #[test]
    fn http2_candidate_is_not_silently_promoted_into_live_fallback() {
        let (_, fallback) = restrictive_tcp_443_routes();
        assert!(!fallback.contains(&restrictive_http2_candidate()));
        assert_eq!(
            restrictive_http2_candidate().transport,
            Transport::TlsHttp2On443
        );
    }

    #[test]
    fn trusted_edge_policy_preserves_transports_and_marks_two_hop_topology() {
        let (primary, fallback) = trusted_edge_tcp_443_routes();
        assert_eq!(primary.topology, Topology::TrustedEdgeExit);
        assert_eq!(primary.transport, Transport::TlsWebSocket443);
        assert!(fallback
            .iter()
            .all(|route| route.topology == Topology::TrustedEdgeExit));
        assert!(fallback
            .iter()
            .all(|route| route.transport.is_live_tcp_443()));
    }
}
