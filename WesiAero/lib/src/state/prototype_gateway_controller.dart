import '../models/commerce_models.dart';
import '../services/secret_store.dart';
import 'gateway_controller.dart';

class PrototypeGatewayController extends GatewayController {
  PrototypeGatewayController({GatewaySecretStore? prototypeStore})
      : _prototypeStore = prototypeStore ?? GatewaySecretStore();

  final GatewaySecretStore _prototypeStore;

  @override
  bool get needsSubscription => false;

  @override
  Future<void> initialize() async {
    await super.initialize();

    // Billing is deliberately bypassed for the networking prototype. Keep the
    // normal commerce implementation intact so it can be re-enabled later.
    licenseKey = null;
    license = AeroLicense(
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

    final profile = await _prototypeStore.readProfile();
    if (profile != null) {
      try {
        await importConfig(profile);
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
    license = AeroLicense(
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
    notifyListeners();
  }
}
