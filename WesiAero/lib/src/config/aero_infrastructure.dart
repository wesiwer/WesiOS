/// Public, non-secret infrastructure hints discovered in the WesiOS source.
///
/// The host below currently serves Wesi AI Relay over HTTPS. It is a deployment
/// target for Wesi Aero, not proof that VLESS or AmneziaWG is already installed.
abstract final class AeroInfrastructure {
  static const String relayPublicHost = String.fromEnvironment(
    'WESI_AERO_RELAY_HOST',
    defaultValue: 'wesi-ai-178-236-247-194.nip.io',
  );

  static const String relayPublicIp = '178.236.247.194';
  static const int existingHttpsPort = 443;
  static const int candidateRealityPort = 8443;
  static const int candidateAmneziaWgPort = 51820;

  static const bool tunnelProvisioned = bool.fromEnvironment(
    'WESI_AERO_TUNNEL_PROVISIONED',
    defaultValue: false,
  );
}
