import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/gateway_models.dart';
import '../models/commerce_models.dart';
import '../services/aero_commerce_service.dart';
import '../services/gateway_engine.dart';
import '../services/secret_store.dart';

class GatewayController extends ChangeNotifier {
  GatewayController({
    GatewayEngine? engine,
    GatewaySecretStore? secretStore,
    AeroCommerceService? commerceService,
  })  : _engine = engine ?? createGatewayEngine(),
        _secretStore = secretStore ?? GatewaySecretStore(),
        _commerce = commerceService ?? createAeroCommerceService();

  final GatewayEngine _engine;
  final GatewaySecretStore _secretStore;
  final AeroCommerceService _commerce;
  StreamSubscription<GatewaySnapshot>? _subscription;
  Timer? _catalogTimer;
  Timer? _checkoutTimer;

  GatewaySnapshot snapshot = const GatewaySnapshot.disconnected(isDemo: true);
  List<GatewayNode> nodes = const [];
  GatewayNode? selectedNode;
  GatewayProtocol protocol = GatewayProtocol.automatic;
  TunnelEngine engine = TunnelEngine.automatic;
  SplitMode splitMode = SplitMode.allTraffic;
  ThemeMode themeMode = ThemeMode.light;
  int navigationIndex = 0;
  bool killSwitch = true;
  bool autoConnect = true;
  bool reducedMotion = false;
  bool loadingNodes = true;
  String? importProfileName;
  AeroCatalog? catalog;
  AeroLicense? license;
  String? licenseKey;
  CheckoutOrder? activeOrder;
  AeroQuote? quote;
  TariffPlan? selectedPlan;
  AeroIpMode selectedIpMode = AeroIpMode.shared;
  int selectedDeviceLimit = 1;
  int selectedDurationDays = 30;
  bool commerceLoading = true;
  bool checkoutBusy = false;
  String? commerceError;
  String? deviceId;
  int _quoteGeneration = 0;
  bool _checkoutRefreshBusy = false;

  List<RoutingRule> rules = const [
    RoutingRule(
      id: 'browser',
      label: 'Browser',
      value: 'com.android.chrome',
      kind: RoutingRuleKind.application,
    ),
    RoutingRule(
      id: 'messenger',
      label: 'Messenger',
      value: 'org.telegram.messenger',
      kind: RoutingRuleKind.application,
    ),
    RoutingRule(
      id: 'work-domain',
      label: 'Рабочий домен',
      value: '*.company.example',
      kind: RoutingRuleKind.domain,
    ),
  ];

  bool get isBusy => snapshot.status == TunnelStatus.connecting ||
      snapshot.status == TunnelStatus.disconnecting;

  bool get isConnected => snapshot.status == TunnelStatus.connected;

  bool get isCommerceDemo => _commerce.isDemo;

  bool get needsSubscription => !commerceLoading && license?.isActive != true;

  List<AeroPaymentMethod> get paymentMethods =>
      catalog?.paymentMethods ?? const [];

  Future<void> initialize() async {
    _subscription = _engine.snapshots.listen((value) {
      snapshot = value;
      notifyListeners();
    });
    await _initializeCommerce();
    try {
      if (catalog?.servers.isNotEmpty == true) {
        nodes = catalog!.servers;
      } else {
        nodes = await _engine.loadNodes();
      }
      selectedNode = nodes.cast<GatewayNode?>().firstWhere(
            (node) => node?.recommended == true,
            orElse: () => nodes.isEmpty ? null : nodes.first,
          );
    } catch (_) {
      nodes = const [];
      selectedNode = null;
    } finally {
      loadingNodes = false;
      notifyListeners();
    }
    _catalogTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(syncCatalog(quiet: true)),
    );
  }

  Future<void> _initializeCommerce() async {
    try {
      deviceId = await _secretStore.getOrCreateDeviceId();
      await syncCatalog(quiet: true);
      final storedKey = await _secretStore.readLicenseKey();
      if (storedKey != null && storedKey.isNotEmpty) {
        try {
          await redeemLicenseKey(storedKey, silent: true);
        } catch (_) {
          await _secretStore.clearLicenseKey();
        }
      }
      if (license?.isActive == true) {
        await _secretStore.clearPendingOrder();
      } else {
        final pending = await _secretStore.readPendingOrder();
        if (pending != null) {
          activeOrder = pending;
          _startCheckoutPolling();
          unawaited(refreshCheckout());
        }
      }
    } catch (error) {
      commerceError = _friendlyCommerceError(error);
    } finally {
      commerceLoading = false;
      notifyListeners();
    }
  }

  Future<void> syncCatalog({bool quiet = false}) async {
    try {
      final next = await _commerce.fetchCatalog();
      if (catalog?.revision != next.revision) {
        catalog = next;
        selectedPlan = next.plans.cast<TariffPlan?>().firstWhere(
              (item) => item?.id == selectedPlan?.id,
              orElse: () => next.plans.isEmpty ? null : next.plans.first,
            );
        if (next.servers.isNotEmpty) {
          final selectedId = selectedNode?.id;
          nodes = next.servers;
          selectedNode = nodes.cast<GatewayNode?>().firstWhere(
                (item) => item?.id == selectedId,
                orElse: () => nodes.cast<GatewayNode?>().firstWhere(
                      (item) => item?.recommended == true,
                      orElse: () => nodes.first,
                    ),
              );
        }
        unawaited(refreshQuote());
      }
      commerceError = null;
      notifyListeners();
    } catch (error) {
      if (!quiet) {
        commerceError = _friendlyCommerceError(error);
        notifyListeners();
      }
    }
  }

  void setIpMode(AeroIpMode value) {
    if (selectedIpMode == value) return;
    selectedIpMode = value;
    notifyListeners();
    unawaited(refreshQuote());
  }

  void setDeviceLimit(int value) {
    if (value < 1 || value > 5 || selectedDeviceLimit == value) return;
    selectedDeviceLimit = value;
    notifyListeners();
    unawaited(refreshQuote());
  }

  void setDurationDays(int value) {
    if (!const [7, 30, 90, 180, 365].contains(value) ||
        selectedDurationDays == value) {
      return;
    }
    selectedDurationDays = value;
    notifyListeners();
    unawaited(refreshQuote());
  }

  void setPlan(TariffPlan value) {
    if (selectedPlan?.id == value.id) return;
    selectedPlan = value;
    notifyListeners();
    unawaited(refreshQuote());
  }

  Future<void> refreshQuote() async {
    final plan = selectedPlan;
    if (plan == null) return;
    final generation = ++_quoteGeneration;
    try {
      final next = await _commerce.quote(
        planId: plan.id,
        ipMode: selectedIpMode,
        deviceLimit: selectedDeviceLimit,
        durationDays: selectedDurationDays,
      );
      if (generation != _quoteGeneration) return;
      quote = next;
      commerceError = null;
      notifyListeners();
    } catch (error) {
      if (generation != _quoteGeneration) return;
      commerceError = _friendlyCommerceError(error);
      notifyListeners();
    }
  }

  Future<CheckoutOrder> startCheckout(AeroPaymentProvider provider) async {
    final plan = selectedPlan;
    if (plan == null) {
      throw const AeroApiException('PLAN_UNAVAILABLE', 'Тариф недоступен.');
    }
    checkoutBusy = true;
    commerceError = null;
    notifyListeners();
    try {
      activeOrder = await _commerce.createOrder(
        planId: plan.id,
        ipMode: selectedIpMode,
        deviceLimit: selectedDeviceLimit,
        durationDays: selectedDurationDays,
        provider: provider,
      );
      await _secretStore.savePendingOrder(activeOrder!);
      _startCheckoutPolling();
      return activeOrder!;
    } catch (error) {
      commerceError = _friendlyCommerceError(error);
      rethrow;
    } finally {
      checkoutBusy = false;
      notifyListeners();
    }
  }

  void _startCheckoutPolling() {
    _checkoutTimer?.cancel();
    _checkoutTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(refreshCheckout()),
    );
  }

  Future<bool> refreshCheckout() async {
    final order = activeOrder;
    if (order == null) return false;
    if (_checkoutRefreshBusy) return activeOrder?.paid == true;
    _checkoutRefreshBusy = true;
    try {
      activeOrder = await _commerce.refreshOrder(order);
      await _secretStore.savePendingOrder(activeOrder!);
      if (activeOrder!.paid) {
        await redeemLicenseKey(activeOrder!.key!, silent: true);
        await _secretStore.clearPendingOrder();
        _checkoutTimer?.cancel();
        return true;
      }
      if (const {'canceled', 'expired', 'failed'}.contains(activeOrder!.status)) {
        await _secretStore.clearPendingOrder();
        _checkoutTimer?.cancel();
        commerceError = switch (activeOrder!.status) {
          'canceled' => 'Платёж отменён.',
          'expired' => 'Срок оплаты истёк. Создайте новый заказ.',
          _ => 'Платёж не удалось завершить.',
        };
      }
      notifyListeners();
      return false;
    } catch (error) {
      commerceError = _friendlyCommerceError(error);
      notifyListeners();
      return false;
    } finally {
      _checkoutRefreshBusy = false;
    }
  }

  Future<void> redeemLicenseKey(String key, {bool silent = false}) async {
    final id = deviceId ?? await _secretStore.getOrCreateDeviceId();
    deviceId = id;
    if (!silent) {
      checkoutBusy = true;
      commerceError = null;
      notifyListeners();
    }
    try {
      final activated = await _commerce.redeemKey(
        key: key,
        deviceId: id,
        deviceName: _deviceName(),
        platform: Platform.operatingSystem,
      );
      licenseKey = key.trim();
      license = activated;
      await _secretStore.saveLicenseKey(licenseKey!);
      commerceError = null;
      notifyListeners();
    } catch (error) {
      commerceError = _friendlyCommerceError(error);
      if (!silent) notifyListeners();
      rethrow;
    } finally {
      if (!silent) {
        checkoutBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> removeLicense() async {
    if (isConnected) await _engine.disconnect();
    license = null;
    licenseKey = null;
    activeOrder = null;
    _checkoutTimer?.cancel();
    await Future.wait([
      _secretStore.clearLicenseKey(),
      _secretStore.clearPendingOrder(),
    ]);
    notifyListeners();
  }

  Future<void> toggleConnection() async {
    if (isBusy) return;
    if (isConnected) {
      await _engine.disconnect();
      return;
    }

    if (license?.isActive != true) {
      snapshot = snapshot.copyWith(
        status: TunnelStatus.error,
        errorMessage: 'Активируйте тариф или вставьте действующий ключ.',
      );
      notifyListeners();
      return;
    }

    final node = selectedNode;
    if (node == null) {
      snapshot = snapshot.copyWith(
        status: TunnelStatus.error,
        errorMessage: 'Нет доступного серверного узла.',
      );
      notifyListeners();
      return;
    }

    try {
      final key = licenseKey;
      if (key != null) {
        await _commerce.secureCall(
          key: key,
          payload: {
            'action': 'license.status',
            'deviceId': deviceId,
          },
        );
      }
      await _engine.connect(
        node: node,
        protocol: protocol,
        engine: engine,
        splitMode: splitMode,
        rules: rules,
        killSwitch: killSwitch,
      );
    } catch (error) {
      snapshot = snapshot.copyWith(
        status: TunnelStatus.error,
        errorMessage: error is AeroApiException
            ? _friendlyCommerceError(error)
            : _friendlyEngineError(error),
      );
      notifyListeners();
    }
  }

  void selectNavigation(int index) {
    if (navigationIndex == index) return;
    navigationIndex = index;
    notifyListeners();
  }

  void selectNode(GatewayNode node) {
    if (isConnected || isBusy || selectedNode?.id == node.id) return;
    selectedNode = node;
    if (protocol != GatewayProtocol.automatic &&
        !node.protocols.contains(protocol)) {
      protocol = GatewayProtocol.automatic;
      engine = TunnelEngine.automatic;
    }
    notifyListeners();
  }

  void setProtocol(GatewayProtocol value) {
    if (isConnected || isBusy || protocol == value) return;
    final node = selectedNode;
    if (node != null &&
        value != GatewayProtocol.automatic &&
        !node.protocols.contains(value)) {
      return;
    }
    protocol = value;
    if (value != GatewayProtocol.automatic && !value.supportsEngine(engine)) {
      engine = TunnelEngine.automatic;
    }
    notifyListeners();
  }

  void setEngine(TunnelEngine value) {
    if (isConnected || isBusy || engine == value) return;
    if (protocol != GatewayProtocol.automatic && !protocol.supportsEngine(value)) {
      return;
    }
    engine = value;
    notifyListeners();
  }

  void setSplitMode(SplitMode value) {
    if (isConnected || isBusy || splitMode == value) return;
    splitMode = value;
    notifyListeners();
  }

  void toggleRule(String id, bool enabled) {
    if (isConnected || isBusy) return;
    rules = rules
        .map((rule) =>
            rule.id == id ? rule.copyWith(enabled: enabled) : rule)
        .toList(growable: false);
    notifyListeners();
  }

  void addRule({
    required String label,
    required String value,
    required RoutingRuleKind kind,
  }) {
    if (isConnected || isBusy) return;
    rules = [
      ...rules,
      RoutingRule(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        label: label,
        value: value,
        kind: kind,
      ),
    ];
    notifyListeners();
  }

  void removeRule(String id) {
    if (isConnected || isBusy) return;
    rules = rules.where((rule) => rule.id != id).toList(growable: false);
    notifyListeners();
  }

  void setKillSwitch(bool value) {
    killSwitch = value;
    notifyListeners();
  }

  void setAutoConnect(bool value) {
    autoConnect = value;
    notifyListeners();
  }

  void setReducedMotion(bool value) {
    reducedMotion = value;
    notifyListeners();
  }

  void toggleTheme() {
    themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  Future<ImportedGatewayConfig> importConfig(String value) async {
    final parsed = GatewayConfigParser.parse(value);
    await _engine.importConfig(parsed);
    await _secretStore.saveProfile(parsed);
    protocol = parsed.protocol;
    if (!parsed.protocol.supportsEngine(engine)) engine = TunnelEngine.automatic;
    importProfileName = parsed.displayName;
    notifyListeners();
    return parsed;
  }

  String _friendlyEngineError(Object error) {
    if (error is UnsupportedError) {
      return error.message?.toString() ?? error.toString();
    }
    return 'Туннельный модуль недоступен. Проверьте нативную интеграцию.';
  }

  String _friendlyCommerceError(Object error) {
    if (error is AeroApiException) {
      return switch (error.code) {
        'DEVICE_LIMIT_EXCEEDED' =>
          'Достигнут лимит устройств для этого ключа.',
        'LICENSE_EXPIRED' => 'Срок действия ключа истёк.',
        'LICENSE_REVOKED' => 'Ключ отозван администратором.',
        'INVALID_LICENSE_KEY' => 'Ключ не найден или введён неверно.',
        'PAYMENT_METHOD_UNAVAILABLE' => 'Этот способ оплаты пока недоступен.',
        'ENGINE_UNAVAILABLE' => error.message,
        _ => error.message,
      };
    }
    if (error is SocketException || error is TimeoutException) {
      return 'Сервер Wesi Aero временно недоступен.';
    }
    return 'Не удалось выполнить запрос. Попробуйте ещё раз.';
  }

  String _deviceName() {
    try {
      return Platform.localHostname.isEmpty
          ? '${Platform.operatingSystem} device'
          : Platform.localHostname;
    } catch (_) {
      return '${Platform.operatingSystem} device';
    }
  }

  @override
  void dispose() {
    _catalogTimer?.cancel();
    _checkoutTimer?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_engine.dispose());
    _commerce.close();
    super.dispose();
  }
}
