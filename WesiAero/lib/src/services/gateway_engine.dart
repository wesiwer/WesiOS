import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/aero_infrastructure.dart';
import '../models/gateway_models.dart';
import 'aero_commerce_service.dart';
import 'secret_store.dart';

class GatewayTelemetry {
  GatewayTelemetry._();

  static final ValueNotifier<SessionStats> stats =
      ValueNotifier<SessionStats>(const SessionStats());

  static void publish(SessionStats value) {
    stats.value = value;
  }
}

abstract interface class GatewayEngine {
  Stream<GatewaySnapshot> get snapshots;

  Future<List<GatewayNode>> loadNodes();

  Future<void> connect({
    required GatewayNode node,
    required GatewayProtocol protocol,
    required TunnelEngine engine,
    required SplitMode splitMode,
    required List<RoutingRule> rules,
    required bool killSwitch,
  });

  Future<void> disconnect();

  Future<void> importConfig(ImportedGatewayConfig config);

  Future<void> dispose();
}

GatewayEngine createGatewayEngine() {
  const demoMode = bool.fromEnvironment('WESI_AERO_DEMO', defaultValue: true);
  return demoMode ? PreviewGatewayEngine() : PlatformGatewayEngine();
}

class PlatformGatewayEngine implements GatewayEngine {
  static const MethodChannel _methods = MethodChannel(
    'com.wesi.aero/gateway',
  );
  static const EventChannel _events = EventChannel(
    'com.wesi.aero/gateway-events',
  );

  final GatewaySecretStore _secretStore = GatewaySecretStore();
  AeroCommerceService? _leaseCommerce;
  Timer? _leaseHeartbeatTimer;
  String? _activeLeaseId;
  String? _activeLicenseKey;
  String? _activeDeviceId;

  late final Stream<GatewaySnapshot> _snapshots = _publishStructuralSnapshots(
    _events
        .receiveBroadcastStream()
        .where((event) => event is Map<Object?, Object?>)
        .cast<Map<Object?, Object?>>()
        .map(_decodeSnapshot),
  ).asBroadcastStream();

  @override
  Stream<GatewaySnapshot> get snapshots => _snapshots;

  @override
  Future<List<GatewayNode>> loadNodes() async {
    final raw = await _methods.invokeListMethod<Map<Object?, Object?>>(
      'loadNodes',
    );
    return (raw ?? const []).map(_decodeNode).toList(growable: false);
  }

  @override
  Future<void> connect({
    required GatewayNode node,
    required GatewayProtocol protocol,
    required TunnelEngine engine,
    required SplitMode splitMode,
    required List<RoutingRule> rules,
    required bool killSwitch,
  }) async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      throw UnsupportedError('TUN поддерживается только на Android и Windows.');
    }

    final resolvedProtocol = _preferredProtocol(node, protocol);
    final resolvedEngine = _preferredEngine(resolvedProtocol, engine);
    await _provisionProfile(node: node, protocol: resolvedProtocol);

    try {
      await _methods.invokeMethod<void>('connect', {
        'nodeId': node.id,
        'protocol': resolvedProtocol.wireName,
        'engine': resolvedEngine.wireName,
        'splitMode': splitMode.name,
        'killSwitch': killSwitch,
        'rules': rules
            .where((rule) => rule.enabled)
            .map(
              (rule) => {
                'kind': rule.kind.name,
                'value': rule.value,
              },
            )
            .toList(growable: false),
      });
    } catch (_) {
      _stopLeaseHeartbeat();
      rethrow;
    }
  }

  Future<void> _provisionProfile({
    required GatewayNode node,
    required GatewayProtocol protocol,
  }) async {
    final key = await _secretStore.readLicenseKey();
    if (key == null || key.isEmpty) {
      throw const AeroApiException(
        'INVALID_LICENSE_KEY',
        'Для подключения нужен действующий ключ Wesi Aero.',
      );
    }
    final deviceId = await _secretStore.getOrCreateDeviceId();
    final commerce = _leaseCommerce ??= createAeroCommerceService();
    if (commerce.isDemo) {
      throw const AeroApiException(
        'CONTROL_PLANE_UNAVAILABLE',
        'Рабочий сервер Wesi Aero не настроен в этой сборке.',
      );
    }

    final response = await commerce.secureCall(
      key: key,
      payload: {
        'action': 'lease.create',
        'deviceId': deviceId,
        'nodeId': node.id,
        'protocol': protocol.wireName,
      },
    );

    final profile = response['profile'];
    if (profile is! Map<String, dynamic>) {
      throw const AeroApiException(
        'PROFILE_NOT_PROVISIONED',
        'Сервер не выдал профиль подключения.',
      );
    }
    final rawConfig = profile['clientConfig'];
    if (rawConfig is! String || rawConfig.trim().isEmpty) {
      throw const AeroApiException(
        'PROFILE_NOT_PROVISIONED',
        'Сервер вернул пустой профиль подключения.',
      );
    }

    final parsed = GatewayConfigParser.parse(rawConfig);
    if (parsed.protocol != protocol) {
      throw const AeroApiException(
        'PROFILE_PROTOCOL_MISMATCH',
        'Протокол серверного профиля не совпадает с выбранным.',
      );
    }
    await importConfig(parsed);
    await _secretStore.saveProfile(parsed);

    final lease = response['lease'];
    final leaseId = lease is Map<String, dynamic> ? lease['id'] as String? : null;
    if (leaseId == null || leaseId.isEmpty) {
      throw const AeroApiException(
        'LEASE_NOT_CREATED',
        'Сервер не создал сессию подключения.',
      );
    }

    _activeLeaseId = leaseId;
    _activeLicenseKey = key;
    _activeDeviceId = deviceId;
    _startLeaseHeartbeat();
  }

  GatewayProtocol _preferredProtocol(
    GatewayNode node,
    GatewayProtocol requested,
  ) {
    if (requested != GatewayProtocol.automatic) {
      if (!node.protocols.contains(requested)) {
        throw const AeroApiException(
          'PROTOCOL_UNAVAILABLE',
          'Выбранный протокол недоступен на этом сервере.',
        );
      }
      return requested;
    }
    const priority = [
      GatewayProtocol.vlessReality,
      GatewayProtocol.hysteria2,
      GatewayProtocol.tuic,
      GatewayProtocol.vmess,
      GatewayProtocol.trojan,
      GatewayProtocol.shadowsocks,
      GatewayProtocol.amneziaWg,
      GatewayProtocol.wireGuard,
    ];
    for (final candidate in priority) {
      if (node.protocols.contains(candidate)) return candidate;
    }
    throw const AeroApiException(
      'PROTOCOL_UNAVAILABLE',
      'На сервере нет поддерживаемого протокола.',
    );
  }

  TunnelEngine _preferredEngine(
    GatewayProtocol protocol,
    TunnelEngine requested,
  ) {
    if (requested != TunnelEngine.automatic) {
      if (!protocol.supportsEngine(requested)) {
        throw AeroApiException(
          'ENGINE_UNAVAILABLE',
          '${requested.title} не поддерживает ${protocol.title}.',
        );
      }
      return requested;
    }
    if (protocol.supportsEngine(TunnelEngine.singBox)) {
      return TunnelEngine.singBox;
    }
    if (protocol.supportsEngine(TunnelEngine.xray)) {
      return TunnelEngine.xray;
    }
    return TunnelEngine.native;
  }

  void _startLeaseHeartbeat() {
    _leaseHeartbeatTimer?.cancel();
    _leaseHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_heartbeatLease()),
    );
  }

  Future<void> _heartbeatLease() async {
    final leaseId = _activeLeaseId;
    final key = _activeLicenseKey;
    final deviceId = _activeDeviceId;
    final commerce = _leaseCommerce;
    if (leaseId == null || key == null || deviceId == null || commerce == null) {
      return;
    }
    try {
      await commerce.secureCall(
        key: key,
        payload: {
          'action': 'lease.heartbeat',
          'leaseId': leaseId,
          'deviceId': deviceId,
        },
      );
    } catch (_) {
      // One control-plane heartbeat must never tear down a healthy data plane.
    }
  }

  void _stopLeaseHeartbeat() {
    _leaseHeartbeatTimer?.cancel();
    _leaseHeartbeatTimer = null;
    _activeLeaseId = null;
    _activeLicenseKey = null;
    _activeDeviceId = null;
  }

  @override
  Future<void> disconnect() async {
    _stopLeaseHeartbeat();
    await _methods.invokeMethod<void>('disconnect');
  }

  @override
  Future<void> importConfig(ImportedGatewayConfig config) {
    return _methods.invokeMethod<void>('importConfig', {
      'protocol': config.protocol.wireName,
      'displayName': config.displayName,
      'config': config.rawValue,
    });
  }

  @override
  Future<void> dispose() async {
    _stopLeaseHeartbeat();
    _leaseCommerce?.close();
    _leaseCommerce = null;
  }

  static Stream<GatewaySnapshot> _publishStructuralSnapshots(
    Stream<GatewaySnapshot> source,
  ) async* {
    GatewaySnapshot? lastPublished;
    await for (final snapshot in source) {
      GatewayTelemetry.publish(snapshot.stats);
      final previous = lastPublished;
      if (previous == null || _structureChanged(previous, snapshot)) {
        lastPublished = snapshot;
        yield snapshot;
      }
    }
  }

  static bool _structureChanged(
    GatewaySnapshot previous,
    GatewaySnapshot next,
  ) {
    return previous.status != next.status ||
        previous.protocol != next.protocol ||
        previous.engine != next.engine ||
        previous.node?.id != next.node?.id ||
        previous.errorMessage != next.errorMessage ||
        previous.isDemo != next.isDemo ||
        previous.stats.connectedAt != next.stats.connectedAt;
  }

  static GatewayProtocol _decodeProtocol(Object? raw) {
    final name = raw?.toString();
    if (name == 'vmess-xray') return GatewayProtocol.vmess;
    return GatewayProtocol.values.firstWhere(
      (value) => value.wireName == name,
      orElse: () => GatewayProtocol.automatic,
    );
  }

  static GatewaySnapshot _decodeSnapshot(Map<Object?, Object?> raw) {
    final status = TunnelStatus.values.firstWhere(
      (value) => value.name == raw['status'],
      orElse: () => TunnelStatus.error,
    );
    final protocol = _decodeProtocol(raw['protocol']);
    final engine = TunnelEngine.values.firstWhere(
      (value) => value.wireName == raw['engine'],
      orElse: () => TunnelEngine.automatic,
    );
    final nodeRaw = raw['node'];
    return GatewaySnapshot(
      status: status,
      protocol: protocol,
      engine: engine,
      node: nodeRaw is Map<Object?, Object?> ? _decodeNode(nodeRaw) : null,
      errorMessage: raw['error'] as String?,
      stats: SessionStats(
        downloadBytesPerSecond: raw['downloadBps'] as int? ?? 0,
        uploadBytesPerSecond: raw['uploadBps'] as int? ?? 0,
        downloadedBytes: raw['downloadedBytes'] as int? ?? 0,
        uploadedBytes: raw['uploadedBytes'] as int? ?? 0,
        connectedAt: raw['connectedAt'] is String
            ? DateTime.tryParse(raw['connectedAt'] as String)
            : null,
        pingMs: raw['pingMs'] as int?,
      ),
    );
  }

  static GatewayNode _decodeNode(Map<Object?, Object?> raw) {
    final rawProtocols = raw['protocols'];
    final protocols = rawProtocols is List
        ? rawProtocols
            .whereType<String>()
            .map(_decodeProtocol)
            .where((value) => value != GatewayProtocol.automatic)
            .toSet()
        : <GatewayProtocol>{};

    return GatewayNode(
      id: raw['id'] as String,
      city: raw['city'] as String? ?? 'Unknown',
      country: raw['country'] as String? ?? 'Unknown',
      countryCode: raw['countryCode'] as String? ?? '',
      endpoint: raw['endpoint'] as String? ?? '',
      pingMs: raw['pingMs'] as int? ?? 0,
      load: (raw['load'] as num?)?.toDouble() ?? 0,
      protocols: protocols,
      recommended: raw['recommended'] as bool? ?? false,
    );
  }
}

class PreviewGatewayEngine implements GatewayEngine {
  final StreamController<GatewaySnapshot> _controller =
      StreamController<GatewaySnapshot>.broadcast();
  Timer? _ticker;
  GatewaySnapshot _current = const GatewaySnapshot.disconnected(isDemo: true);
  GatewaySnapshot? _lastPublished;

  @override
  Stream<GatewaySnapshot> get snapshots => _controller.stream;

  @override
  Future<List<GatewayNode>> loadNodes() async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    return const [
      GatewayNode(
        id: 'wesi-foreign-relay-candidate',
        city: 'Wesi Relay',
        country: AeroInfrastructure.tunnelProvisioned ? 'Aero node' : 'Demo target',
        countryCode: '',
        endpoint:
            '${AeroInfrastructure.relayPublicHost}:${AeroInfrastructure.candidateRealityPort}',
        pingMs: 28,
        load: 0.24,
        protocols: {
          GatewayProtocol.vlessReality,
          GatewayProtocol.vmess,
          GatewayProtocol.trojan,
          GatewayProtocol.shadowsocks,
          GatewayProtocol.hysteria2,
          GatewayProtocol.tuic,
          GatewayProtocol.wireGuard,
          GatewayProtocol.amneziaWg,
        },
        recommended: true,
      ),
    ];
  }

  @override
  Future<void> connect({
    required GatewayNode node,
    required GatewayProtocol protocol,
    required TunnelEngine engine,
    required SplitMode splitMode,
    required List<RoutingRule> rules,
    required bool killSwitch,
  }) async {
    _ticker?.cancel();
    final resolvedProtocol = protocol == GatewayProtocol.automatic
        ? _preferredProtocol(node.protocols)
        : protocol;
    final resolvedEngine = engine == TunnelEngine.automatic
        ? (resolvedProtocol.supportsEngine(TunnelEngine.singBox)
            ? TunnelEngine.singBox
            : TunnelEngine.native)
        : engine;
    _emit(
      GatewaySnapshot(
        status: TunnelStatus.connecting,
        stats: const SessionStats(),
        node: node,
        protocol: resolvedProtocol,
        engine: resolvedEngine,
        isDemo: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 900));

    final connectedAt = DateTime.now();
    _emit(
      GatewaySnapshot(
        status: TunnelStatus.connected,
        stats: SessionStats(connectedAt: connectedAt, pingMs: node.pingMs),
        node: node,
        protocol: resolvedProtocol,
        engine: resolvedEngine,
        isDemo: true,
      ),
    );

    var tick = 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      tick += 1;
      final down = 620000 + ((tick * 7919) % 4100000);
      final up = 120000 + ((tick * 3571) % 850000);
      _emit(
        _current.copyWith(
          stats: _current.stats.copyWith(
            downloadBytesPerSecond: down,
            uploadBytesPerSecond: up,
            downloadedBytes: _current.stats.downloadedBytes + down,
            uploadedBytes: _current.stats.uploadedBytes + up,
            pingMs: node.pingMs + ((tick % 5) - 2),
          ),
        ),
      );
    });
  }

  GatewayProtocol _preferredProtocol(Set<GatewayProtocol> protocols) {
    const priority = [
      GatewayProtocol.vlessReality,
      GatewayProtocol.hysteria2,
      GatewayProtocol.tuic,
      GatewayProtocol.vmess,
      GatewayProtocol.trojan,
      GatewayProtocol.shadowsocks,
      GatewayProtocol.amneziaWg,
      GatewayProtocol.wireGuard,
    ];
    for (final candidate in priority) {
      if (protocols.contains(candidate)) return candidate;
    }
    throw StateError('У сервера нет поддерживаемого протокола.');
  }

  @override
  Future<void> disconnect() async {
    _ticker?.cancel();
    _emit(_current.copyWith(status: TunnelStatus.disconnecting));
    await Future<void>.delayed(const Duration(milliseconds: 420));
    _emit(const GatewaySnapshot.disconnected(isDemo: true));
  }

  @override
  Future<void> importConfig(ImportedGatewayConfig config) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  void _emit(GatewaySnapshot snapshot) {
    _current = snapshot;
    GatewayTelemetry.publish(snapshot.stats);
    final previous = _lastPublished;
    if (previous == null ||
        PlatformGatewayEngine._structureChanged(previous, snapshot)) {
      _lastPublished = snapshot;
      if (!_controller.isClosed) _controller.add(snapshot);
    }
  }

  @override
  Future<void> dispose() async {
    _ticker?.cancel();
    await _controller.close();
  }
}
