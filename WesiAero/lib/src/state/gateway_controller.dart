import 'dart:async';

import 'package:flutter/material.dart';

import '../models/gateway_models.dart';
import '../services/gateway_engine.dart';
import '../services/secret_store.dart';

class GatewayController extends ChangeNotifier {
  GatewayController({
    GatewayEngine? engine,
    GatewaySecretStore? secretStore,
  })  : _engine = engine ?? createGatewayEngine(),
        _secretStore = secretStore ?? GatewaySecretStore();

  final GatewayEngine _engine;
  final GatewaySecretStore _secretStore;
  StreamSubscription<GatewaySnapshot>? _subscription;

  GatewaySnapshot snapshot = const GatewaySnapshot.disconnected(isDemo: true);
  List<GatewayNode> nodes = const [];
  GatewayNode? selectedNode;
  GatewayProtocol protocol = GatewayProtocol.automatic;
  SplitMode splitMode = SplitMode.allTraffic;
  ThemeMode themeMode = ThemeMode.light;
  int navigationIndex = 0;
  bool killSwitch = true;
  bool autoConnect = true;
  bool reducedMotion = false;
  bool loadingNodes = true;
  String? importProfileName;

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

  Future<void> initialize() async {
    _subscription = _engine.snapshots.listen((value) {
      snapshot = value;
      notifyListeners();
    });
    try {
      nodes = await _engine.loadNodes();
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
  }

  Future<void> toggleConnection() async {
    if (isBusy) return;
    if (isConnected) {
      await _engine.disconnect();
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
      await _engine.connect(
        node: node,
        protocol: protocol,
        splitMode: splitMode,
        rules: rules,
        killSwitch: killSwitch,
      );
    } catch (error) {
      snapshot = snapshot.copyWith(
        status: TunnelStatus.error,
        errorMessage: _friendlyEngineError(error),
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
        .map((rule) => rule.id == id ? rule.copyWith(enabled: enabled) : rule)
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

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_engine.dispose());
    super.dispose();
  }
}
