import '../models/commerce_models.dart';
import '../models/gateway_models.dart';
import '../services/gateway_engine.dart';
import '../services/secret_store.dart';
import 'gateway_controller.dart';

class PrototypeGatewayController extends GatewayController {
  PrototypeGatewayController({GatewaySecretStore? prototypeStore})
      : _prototypeStore = prototypeStore ?? GatewaySecretStore(),
        super(engine: PlatformGatewayEngine());

  final GatewaySecretStore _prototypeStore;

  @override
  bool get needsSubscription => false;

  @override
  Future<void> initialize() async {
    await super.initialize();

    // Billing is deliberately bypassed for the networking prototype. Keep the
    // normal commerce implementation intact so it can be re-enabled later.
    licenseKey = null;
    license = _prototypeLicense();

    if (selectedNode == null) {
      const prototypeNode = GatewayNode(
        id: 'imported-wireguard',
        city: 'Wesi Aero',
        country: 'WireGuard',
        countryCode: '',
        endpoint: 'Imported profile',
        pingMs: 0,
        load: 0,
        protocols: {GatewayProtocol.amneziaWg},
        recommended: true,
      );
      nodes = const [prototypeNode];
      selectedNode = prototypeNode;
    }

    final profile = await _prototypeStore.readProfile();
    if (profile != null) {
      try {
        await importConfig(profile.rawValue);
        protocol = profile.protocol;
        importProfileName = profile.displayName;
      } catch (error) {
        commerceError = 'Не удалось восстановить VPN-профиль: $error';
      }
    }

    commerceLoading = false;
    notifyListeners();
  }

  @override
  Future<void> removeLicense() async {
    licenseKey = null;
    license = _prototypeLicense();
    notifyListeners();
  }

  AeroLicense _prototypeLicense() => AeroLicense(
        id: 'prototype-access',
        planId: null,
        ipMode: AeroIpMode.shared,
        deviceLimit: 1,
        deviceCount: 1,
        durationDays: 365,
        status: 'active',
        expiresAt: DateTime.now().add(const Duration(days: 3650)),
        maskedKey: 'PROTOTYPE',
      );
}
