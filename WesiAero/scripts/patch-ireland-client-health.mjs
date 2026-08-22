import fs from 'node:fs';

const file = 'WesiAero/lib/src/state/gateway_controller.dart';
let source = fs.readFileSync(file, 'utf8');

function replaceOnce(before, after, label) {
  const count = source.split(before).length - 1;
  if (count !== 1) throw new Error(`${label}: expected one match, found ${count}`);
  source = source.replace(before, after);
}

if (!source.includes("../services/tunnel_health_service.dart")) {
  replaceOnce(
    "import '../services/secret_store.dart';\n",
    "import '../services/secret_store.dart';\nimport '../services/tunnel_health_service.dart';\n",
    'health import',
  );
}

if (!source.includes('Timer? _tunnelHealthTimer;')) {
  replaceOnce(
    '  Timer? _checkoutTimer;\n',
    '  Timer? _checkoutTimer;\n  Timer? _tunnelHealthTimer;\n  final TunnelHealthService _tunnelHealth = const TunnelHealthService();\n',
    'health fields',
  );
}

if (!source.includes('_startTunnelHealthMonitoring();')) {
  replaceOnce(
`    _subscription = _engine.snapshots.listen((value) {\n      snapshot = value;\n      notifyListeners();\n    });`,
`    _subscription = _engine.snapshots.listen((value) {\n      final wasConnected = snapshot.status == TunnelStatus.connected;\n      snapshot = value;\n      final isNowConnected = value.status == TunnelStatus.connected;\n      if (!wasConnected && isNowConnected) {\n        _startTunnelHealthMonitoring();\n      } else if (wasConnected && !isNowConnected) {\n        _stopTunnelHealthMonitoring();\n      }\n      notifyListeners();\n    });`,
    'snapshot health lifecycle',
  );
}

if (!source.includes('Future<void> _runTunnelHealthCheck()')) {
  const anchor = '  void selectNavigation(int index) {';
  const methods = `  void _startTunnelHealthMonitoring() {\n    _stopTunnelHealthMonitoring();\n    if (snapshot.node?.id != 'ireland-bs') return;\n    unawaited(_runTunnelHealthCheck());\n    _tunnelHealthTimer = Timer.periodic(\n      const Duration(seconds: 25),\n      (_) => unawaited(_runTunnelHealthCheck()),\n    );\n  }\n\n  void _stopTunnelHealthMonitoring() {\n    _tunnelHealthTimer?.cancel();\n    _tunnelHealthTimer = null;\n  }\n\n  Future<void> _runTunnelHealthCheck() async {\n    if (!isConnected || snapshot.node?.id != 'ireland-bs') return;\n    final key = licenseKey;\n    final currentDeviceId = deviceId;\n    final node = snapshot.node;\n    if (key == null || currentDeviceId == null || node == null) return;\n    final result = await _tunnelHealth.probe();\n    try {\n      await _commerce.secureCall(\n        key: key,\n        payload: {\n          'action': 'route.health.report',\n          'deviceId': currentDeviceId,\n          'nodeId': node.id,\n          'protocol': snapshot.protocol.wireName,\n          'result': result.toJson(),\n        },\n      );\n    } catch (_) {\n      // Telemetry/control-plane failure must not tear down a healthy data plane.\n    }\n  }\n\n`;
  if (!source.includes(anchor)) throw new Error('navigation anchor missing');
  source = source.replace(anchor, methods + anchor);
}

if (!source.includes('_tunnelHealthTimer?.cancel();')) {
  replaceOnce(
    '    _checkoutTimer?.cancel();\n    unawaited(_subscription?.cancel());',
    '    _checkoutTimer?.cancel();\n    _tunnelHealthTimer?.cancel();\n    unawaited(_subscription?.cancel());',
    'dispose health timer',
  );
}

fs.writeFileSync(file, source);
console.log('Ireland client health patch applied');
