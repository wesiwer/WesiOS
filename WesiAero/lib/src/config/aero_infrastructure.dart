/// Public, non-secret infrastructure hints discovered in the WesiOS source.
///
/// The host below currently serves Wesi AI Relay over HTTPS. Wesi Aero keeps
/// its VPN transports on dedicated non-conflicting ports: VLESS/REALITY on
/// 8443, VMess/Xray on 8444 and WireGuard/AmneziaWG on 51820/UDP.
abstract final class AeroInfrastructure {
  static const String relayPublicHost = String.fromEnvironment(
    'WESI_AERO_RELAY_HOST',
    defaultValue: 'wesi-ai-178-236-247-194.nip.io',
  );

  static const String relayPublicIp = '178.236.247.194';
  static const int existingHttpsPort = 443;
  static const int candidateRealityPort = 8443;
  static const int candidateVmessPort = 8444;
  static const int candidateAmneziaWgPort = 51820;

  static const bool tunnelProvisioned = bool.fromEnvironment(
    'WESI_AERO_TUNNEL_PROVISIONED',
    defaultValue: false,
  );
}
