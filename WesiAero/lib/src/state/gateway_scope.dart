import 'package:flutter/widgets.dart';

import 'gateway_controller.dart';

/// Provides the controller while filtering high-frequency controller changes
/// before they reach the widget tree.
///
/// The controller intentionally remains a single source of truth, but tunnel
/// telemetry and background commerce work must not invalidate every glass,
/// blur and animation layer. Consumers using [of] rebuild only when the
/// visual UI signature actually changes. Consumers that only need callbacks
/// can use [read] and create no inherited dependency at all.
class GatewayScope extends StatefulWidget {
  const GatewayScope({
    required this.controller,
    required this.child,
    super.key,
  });

  final GatewayController controller;
  final Widget child;

  static GatewayController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_GatewayScopeData>();
    assert(scope != null, 'GatewayScope not found in widget tree.');
    return scope!.controller;
  }

  static GatewayController read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<_GatewayScopeData>();
    final scope = element?.widget as _GatewayScopeData?;
    assert(scope != null, 'GatewayScope not found in widget tree.');
    return scope!.controller;
  }

  @override
  State<GatewayScope> createState() => _GatewayScopeState();
}

class _GatewayScopeState extends State<GatewayScope> {
  late _GatewayUiNotifier _uiNotifier;

  @override
  void initState() {
    super.initState();
    _uiNotifier = _GatewayUiNotifier(widget.controller);
  }

  @override
  void didUpdateWidget(covariant GatewayScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    _uiNotifier.dispose();
    _uiNotifier = _GatewayUiNotifier(widget.controller);
  }

  @override
  void dispose() {
    _uiNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GatewayScopeData(
      controller: widget.controller,
      notifier: _uiNotifier,
      child: widget.child,
    );
  }
}

class _GatewayScopeData extends InheritedNotifier<_GatewayUiNotifier> {
  const _GatewayScopeData({
    required this.controller,
    required super.notifier,
    required super.child,
  });

  final GatewayController controller;
}

class _GatewayUiNotifier extends ChangeNotifier {
  _GatewayUiNotifier(this.controller) : _signature = _visualSignature(controller) {
    controller.addListener(_handleControllerChanged);
  }

  final GatewayController controller;
  int _signature;

  void _handleControllerChanged() {
    final next = _visualSignature(controller);
    if (next == _signature) return;
    _signature = next;
    notifyListeners();
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  static int _visualSignature(GatewayController controller) {
    final snapshot = controller.snapshot;
    final selectedNode = controller.selectedNode;

    // Deliberately exclude byte counters and instantaneous throughput. Those
    // values have their own lightweight GatewayTelemetry notifier on the
    // dashboard. Including them here would rebuild the complete screen every
    // second while a tunnel is active.
    final connectionSignature = Object.hash(
      snapshot.status,
      snapshot.protocol,
      snapshot.node?.id,
      snapshot.errorMessage,
      snapshot.isDemo,
      snapshot.stats.connectedAt,
    );

    final selectedNodeSignature = selectedNode == null
        ? 0
        : Object.hash(
            selectedNode.id,
            selectedNode.endpoint,
            selectedNode.pingMs,
            selectedNode.load,
            selectedNode.recommended,
            Object.hashAll(selectedNode.protocols),
          );

    final nodeListSignature = Object.hashAll(
      controller.nodes.map(
        (node) => Object.hash(
          node.id,
          node.endpoint,
          node.pingMs,
          node.load,
          node.recommended,
          Object.hashAll(node.protocols),
        ),
      ),
    );

    final routeSignature = Object.hashAll(
      controller.rules.map(
        (rule) => Object.hash(
          rule.id,
          rule.enabled,
          rule.label,
          rule.value,
          rule.kind,
        ),
      ),
    );

    final coreSignature = Object.hashAll([
      connectionSignature,
      selectedNodeSignature,
      nodeListSignature,
      routeSignature,
      controller.navigationIndex,
      controller.protocol,
      controller.splitMode,
      controller.themeMode,
      controller.killSwitch,
      controller.autoConnect,
      controller.reducedMotion,
      controller.loadingNodes,
      controller.importProfileName,
      controller.commerceLoading,
      controller.needsSubscription,
    ]);

    // Once a valid prototype/production license is active, quote polling,
    // checkout state and other commerce changes are irrelevant to the main VPN
    // shell. Ignoring them prevents background control-plane work from
    // invalidating expensive glass and backdrop layers.
    if (!controller.commerceLoading && !controller.needsSubscription) {
      return coreSignature;
    }

    return Object.hashAll([
      coreSignature,
      controller.catalog?.revision,
      controller.license?.id,
      controller.license?.status,
      controller.license?.deviceCount,
      controller.activeOrder?.id,
      controller.activeOrder?.status,
      controller.quote?.amountMinor,
      controller.selectedPlan?.id,
      controller.selectedIpMode,
      controller.selectedDeviceLimit,
      controller.selectedDurationDays,
      controller.checkoutBusy,
      controller.commerceError,
    ]);
  }
}
