import '../models/commerce_models.dart';
import '../models/gateway_models.dart';
import '../services/gateway_engine.dart';
import '../services/secret_store.dart';
import 'gateway_controller.dart';

class PrototypeGatewayController extends GatewayController {
  PrototypeGatewayController({GatewaySecretStore? prototypeStore})
      : _prototypeStore = prototypeStore ?? GatewaySecretStore(),
        super(engine: PlatformGatewayEngine());

  static const String _embeddedPrototypeLicense = String.fromEnvironment(
    'WESI_AERO_PROTOTYPE_LICENSE',
  );

  final GatewaySecretStore _prototypeStore;

  @override
  bool get needsSubscription => false;

  @override
  Future<void> initialize() async {
    await super.initialize();

    // Live prototype builds carry a server-issued key. Never replace a real
    // redeemed license with a synthetic local license: PlatformGatewayEngine
    // provisions every lease through the control plane and therefore needs the
    // exact same server-backed credential.
    final embeddedKey = _embeddedPrototypeLicense.trim();
    if (embeddedKey.isEmpty) {
      license = null;
      licenseKey = null;
      commerceError = 'Эта сборка Wesi Aero не содержит служебный ключ доступа.';
    } else if (license?.isActive != true || licenseKey != embeddedKey) {
      try {
        await redeemLicenseKey(embeddedKey, silent: true);
      } catch (_) {
        license = null;
        licenseKey = null;
        commerceError =
            'Служебный ключ этой сборки не подтверждён сервером. Обновите Wesi Aero.';
      }
    }

    if (selectedNode == null) {
      const prototypeNode = GatewayNode(
        id: 'wesi-relay',
        city: 'Wesi Relay',
        country: 'Wesi Aero',
        countryCode: '',
        endpoint: 'wesi-aero-178-236-247-194.nip.io:8443',
        pingMs: 0,
        load: 0,
        protocols: {
          GatewayProtocol.vlessReality,
          GatewayProtocol.vmessXray,
          GatewayProtocol.amneziaWg,
        },
        recommended: true,
      );
      nodes = const [prototypeNode];
      selectedNode = prototypeNode;
    }

    final node = selectedNode;
    if (node != null && node.protocols.contains(GatewayProtocol.vlessReality)) {
      protocol = GatewayProtocol.vlessReality;
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
    // Prototype access is build-managed. Re-assert the embedded server key
    // instead of leaving the engine with a synthetic/local-only license.
    final embeddedKey = _embeddedPrototypeLicense.trim();
    if (embeddedKey.isEmpty) {
      license = null;
      licenseKey = null;
      notifyListeners();
      return;
    }
    await redeemLicenseKey(embeddedKey, silent: true);
  }
}
