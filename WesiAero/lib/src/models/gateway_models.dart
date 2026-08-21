import 'dart:convert';

enum TunnelStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

enum TunnelEngine {
  automatic,
  singBox,
  xray,
  native;

  String get title => switch (this) {
        TunnelEngine.automatic => 'Автоматически',
        TunnelEngine.singBox => 'sing-box',
        TunnelEngine.xray => 'Xray',
        TunnelEngine.native => 'Native',
      };

  String get wireName => switch (this) {
        TunnelEngine.automatic => 'auto',
        TunnelEngine.singBox => 'sing-box',
        TunnelEngine.xray => 'xray',
        TunnelEngine.native => 'native',
      };
}

enum GatewayProtocol {
  automatic,
  vlessReality,
  vmess,
  trojan,
  shadowsocks,
  hysteria2,
  tuic,
  wireGuard,
  amneziaWg;

  String get title => switch (this) {
        GatewayProtocol.automatic => 'Автоматически',
        GatewayProtocol.vlessReality => 'VLESS · REALITY',
        GatewayProtocol.vmess => 'VMess',
        GatewayProtocol.trojan => 'Trojan',
        GatewayProtocol.shadowsocks => 'Shadowsocks',
        GatewayProtocol.hysteria2 => 'Hysteria2',
        GatewayProtocol.tuic => 'TUIC',
        GatewayProtocol.wireGuard => 'WireGuard',
        GatewayProtocol.amneziaWg => 'AmneziaWG',
      };

  String get wireName => switch (this) {
        GatewayProtocol.automatic => 'auto',
        GatewayProtocol.vlessReality => 'vless-reality',
        GatewayProtocol.vmess => 'vmess',
        GatewayProtocol.trojan => 'trojan',
        GatewayProtocol.shadowsocks => 'shadowsocks',
        GatewayProtocol.hysteria2 => 'hysteria2',
        GatewayProtocol.tuic => 'tuic',
        GatewayProtocol.wireGuard => 'wireguard',
        GatewayProtocol.amneziaWg => 'amneziawg',
      };

  Set<TunnelEngine> get supportedEngines => switch (this) {
        GatewayProtocol.automatic => const {
            TunnelEngine.automatic,
            TunnelEngine.singBox,
            TunnelEngine.xray,
            TunnelEngine.native,
          },
        GatewayProtocol.vlessReality ||
        GatewayProtocol.vmess ||
        GatewayProtocol.trojan ||
        GatewayProtocol.shadowsocks => const {
            TunnelEngine.automatic,
            TunnelEngine.singBox,
            TunnelEngine.xray,
          },
        GatewayProtocol.hysteria2 || GatewayProtocol.tuic => const {
            TunnelEngine.automatic,
            TunnelEngine.singBox,
          },
        GatewayProtocol.wireGuard => const {
            TunnelEngine.automatic,
            TunnelEngine.native,
            TunnelEngine.singBox,
          },
        GatewayProtocol.amneziaWg => const {
            TunnelEngine.automatic,
            TunnelEngine.native,
          },
      };

  bool supportsEngine(TunnelEngine engine) =>
      engine == TunnelEngine.automatic || supportedEngines.contains(engine);
}

enum SplitMode {
  allTraffic,
  allowlist,
  denylist;

  String get title => switch (this) {
        SplitMode.allTraffic => 'Весь трафик',
        SplitMode.allowlist => 'Только выбранное',
        SplitMode.denylist => 'Кроме выбранного',
      };
}

class GatewayNode {
  const GatewayNode({
    required this.id,
    required this.city,
    required this.country,
    required this.countryCode,
    required this.endpoint,
    required this.pingMs,
    required this.load,
    required this.protocols,
    this.recommended = false,
  });

  final String id;
  final String city;
  final String country;
  final String countryCode;
  final String endpoint;
  final int pingMs;
  final double load;
  final Set<GatewayProtocol> protocols;
  final bool recommended;

  String get label => '$city · $country';

  String get flagEmoji {
    if (countryCode.length != 2) return '🌐';
    return countryCode
        .toUpperCase()
        .codeUnits
        .map((code) => String.fromCharCode(code + 127397))
        .join();
  }
}

class SessionStats {
  const SessionStats({
    this.downloadBytesPerSecond = 0,
    this.uploadBytesPerSecond = 0,
    this.downloadedBytes = 0,
    this.uploadedBytes = 0,
    this.connectedAt,
    this.pingMs,
  });

  final int downloadBytesPerSecond;
  final int uploadBytesPerSecond;
  final int downloadedBytes;
  final int uploadedBytes;
  final DateTime? connectedAt;
  final int? pingMs;

  int get totalBytes => downloadedBytes + uploadedBytes;

  SessionStats copyWith({
    int? downloadBytesPerSecond,
    int? uploadBytesPerSecond,
    int? downloadedBytes,
    int? uploadedBytes,
    DateTime? connectedAt,
    int? pingMs,
    bool clearConnectedAt = false,
  }) {
    return SessionStats(
      downloadBytesPerSecond:
          downloadBytesPerSecond ?? this.downloadBytesPerSecond,
      uploadBytesPerSecond: uploadBytesPerSecond ?? this.uploadBytesPerSecond,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      connectedAt: clearConnectedAt ? null : connectedAt ?? this.connectedAt,
      pingMs: pingMs ?? this.pingMs,
    );
  }
}

class GatewaySnapshot {
  const GatewaySnapshot({
    required this.status,
    required this.stats,
    this.node,
    this.protocol = GatewayProtocol.automatic,
    this.engine = TunnelEngine.automatic,
    this.errorMessage,
    this.isDemo = false,
  });

  const GatewaySnapshot.disconnected({this.isDemo = false})
      : status = TunnelStatus.disconnected,
        stats = const SessionStats(),
        node = null,
        protocol = GatewayProtocol.automatic,
        engine = TunnelEngine.automatic,
        errorMessage = null;

  final TunnelStatus status;
  final SessionStats stats;
  final GatewayNode? node;
  final GatewayProtocol protocol;
  final TunnelEngine engine;
  final String? errorMessage;
  final bool isDemo;

  GatewaySnapshot copyWith({
    TunnelStatus? status,
    SessionStats? stats,
    GatewayNode? node,
    GatewayProtocol? protocol,
    TunnelEngine? engine,
    String? errorMessage,
    bool? isDemo,
    bool clearError = false,
  }) {
    return GatewaySnapshot(
      status: status ?? this.status,
      stats: stats ?? this.stats,
      node: node ?? this.node,
      protocol: protocol ?? this.protocol,
      engine: engine ?? this.engine,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      isDemo: isDemo ?? this.isDemo,
    );
  }
}

class RoutingRule {
  const RoutingRule({
    required this.id,
    required this.label,
    required this.value,
    required this.kind,
    this.enabled = true,
  });

  final String id;
  final String label;
  final String value;
  final RoutingRuleKind kind;
  final bool enabled;

  RoutingRule copyWith({bool? enabled}) => RoutingRule(
        id: id,
        label: label,
        value: value,
        kind: kind,
        enabled: enabled ?? this.enabled,
      );
}

enum RoutingRuleKind { application, domain, ipRange }

class ImportedGatewayConfig {
  const ImportedGatewayConfig({
    required this.protocol,
    required this.displayName,
    required this.rawValue,
  });

  final GatewayProtocol protocol;
  final String displayName;
  final String rawValue;
}

class GatewayConfigParser {
  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  static ImportedGatewayConfig parse(String input) {
    final value = input.trim();
    if (value.isEmpty) {
      throw const FormatException('Конфигурация не может быть пустой.');
    }

    if (value.startsWith('vless://')) return _parseVless(value);
    if (value.startsWith('vmess://')) return _parseVmess(value);
    if (value.startsWith('trojan://')) return _parseSimpleUri(
          value,
          GatewayProtocol.trojan,
          schemes: const {'trojan'},
        );
    if (value.startsWith('ss://')) return _parseShadowsocks(value);
    if (value.startsWith('hysteria2://') || value.startsWith('hy2://')) {
      return _parseSimpleUri(
        value,
        GatewayProtocol.hysteria2,
        schemes: const {'hysteria2', 'hy2'},
      );
    }
    if (value.startsWith('tuic://')) return _parseSimpleUri(
          value,
          GatewayProtocol.tuic,
          schemes: const {'tuic'},
        );

    if (value.contains('[Interface]') && value.contains('[Peer]')) {
      return _parseWireGuardFamily(value);
    }

    if (value.startsWith('{')) return _parseJson(value);

    throw const FormatException(
      'Поддерживаются VLESS, VMess, Trojan, Shadowsocks, Hysteria2, TUIC, WireGuard, AmneziaWG и JSON-профили.',
    );
  }

  static ImportedGatewayConfig _parseVless(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty || uri.port == 0) {
      throw const FormatException('В VLESS-конфигурации нет адреса или порта.');
    }
    if (!_uuid.hasMatch(uri.userInfo)) {
      throw const FormatException('Некорректный UUID VLESS.');
    }
    if (uri.queryParameters['security']?.toLowerCase() != 'reality') {
      throw const FormatException('Ожидается транспорт VLESS + REALITY.');
    }
    if ((uri.queryParameters['pbk'] ?? '').trim().isEmpty ||
        (uri.queryParameters['sni'] ?? '').trim().isEmpty) {
      throw const FormatException(
        'Для VLESS + REALITY необходимы public key (pbk) и SNI.',
      );
    }

    return ImportedGatewayConfig(
      protocol: GatewayProtocol.vlessReality,
      displayName: _uriName(uri),
      rawValue: value,
    );
  }

  static ImportedGatewayConfig _parseVmess(String value) {
    final encoded = value.substring('vmess://'.length).trim();
    if (encoded.isEmpty) {
      throw const FormatException('VMess-профиль пуст.');
    }

    Map<String, dynamic> decoded;
    try {
      final json = utf8.decode(base64.decode(base64.normalize(encoded)));
      final object = jsonDecode(json);
      if (object is! Map<String, dynamic>) {
        throw const FormatException('VMess payload должен быть JSON-объектом.');
      }
      decoded = object;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Некорректный VMess base64/JSON профиль.');
    }

    final host = (decoded['add'] as String?)?.trim() ?? '';
    final uuid = (decoded['id'] as String?)?.trim() ?? '';
    final portValue = decoded['port'];
    final port = portValue is num
        ? portValue.toInt()
        : int.tryParse(portValue?.toString() ?? '');
    if (host.isEmpty || port == null || port < 1 || port > 65535) {
      throw const FormatException('В VMess-конфигурации нет адреса или порта.');
    }
    if (!_uuid.hasMatch(uuid)) {
      throw const FormatException('Некорректный UUID VMess.');
    }

    final name = (decoded['ps'] as String?)?.trim();
    return ImportedGatewayConfig(
      protocol: GatewayProtocol.vmess,
      displayName: name?.isNotEmpty == true ? name! : '$host:$port',
      rawValue: value,
    );
  }

  static ImportedGatewayConfig _parseShadowsocks(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'ss') {
      throw const FormatException('Некорректный Shadowsocks URI.');
    }
    // SIP002 permits both base64 userinfo and legacy fully-base64 payloads.
    // Native engines perform the final method/password validation.
    if (uri.host.isEmpty && !value.substring(5).contains('@')) {
      try {
        final payload = value.substring(5).split('#').first.split('?').first;
        final decoded = utf8.decode(base64.decode(base64.normalize(payload)));
        if (!decoded.contains('@') || !decoded.contains(':')) {
          throw const FormatException('Некорректный Shadowsocks payload.');
        }
      } catch (_) {
        throw const FormatException('Некорректный Shadowsocks URI.');
      }
    }
    return ImportedGatewayConfig(
      protocol: GatewayProtocol.shadowsocks,
      displayName: uri.fragment.isEmpty
          ? (uri.host.isEmpty ? 'Shadowsocks' : '${uri.host}:${uri.port}')
          : Uri.decodeComponent(uri.fragment),
      rawValue: value,
    );
  }

  static ImportedGatewayConfig _parseSimpleUri(
    String value,
    GatewayProtocol protocol, {
    required Set<String> schemes,
  }) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !schemes.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.port < 1 ||
        uri.userInfo.isEmpty) {
      throw FormatException('Некорректный ${protocol.title} URI.');
    }
    return ImportedGatewayConfig(
      protocol: protocol,
      displayName: _uriName(uri),
      rawValue: value,
    );
  }

  static ImportedGatewayConfig _parseWireGuardFamily(String value) {
    final hasPrivateKey = RegExp(
      r'^\s*PrivateKey\s*=\s*\S+',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch(value);
    final hasPublicKey = RegExp(
      r'^\s*PublicKey\s*=\s*\S+',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch(value);
    final hasEndpoint = RegExp(
      r'^\s*Endpoint\s*=\s*\S+',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch(value);

    if (!hasPrivateKey || !hasPublicKey || !hasEndpoint) {
      throw const FormatException(
        'В WireGuard-конфигурации отсутствует ключ или Endpoint.',
      );
    }

    final isAmnezia = RegExp(
      r'^\s*(Jc|Jmin|Jmax|S1|S2|H1|H2|H3|H4)\s*=',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch(value);
    final protocol =
        isAmnezia ? GatewayProtocol.amneziaWg : GatewayProtocol.wireGuard;
    return ImportedGatewayConfig(
      protocol: protocol,
      displayName: isAmnezia ? 'Импортированный AmneziaWG' : 'Импортированный WireGuard',
      rawValue: value,
    );
  }

  static ImportedGatewayConfig _parseJson(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON-профиль должен быть объектом.');
    }

    final protocol = switch (decoded['protocol']) {
      'vless-reality' => GatewayProtocol.vlessReality,
      'vmess' || 'vmess-xray' => GatewayProtocol.vmess,
      'trojan' => GatewayProtocol.trojan,
      'shadowsocks' => GatewayProtocol.shadowsocks,
      'hysteria2' => GatewayProtocol.hysteria2,
      'tuic' => GatewayProtocol.tuic,
      'wireguard' => GatewayProtocol.wireGuard,
      'amneziawg' => GatewayProtocol.amneziaWg,
      _ => throw const FormatException('Неизвестный протокол JSON-профиля.'),
    };
    final config = decoded['config'];
    if (config is! String || config.trim().isEmpty) {
      throw const FormatException('В JSON-профиле отсутствует поле config.');
    }

    final parsed = parse(config);
    if (parsed.protocol != protocol) {
      throw const FormatException('Протокол JSON-профиля не совпадает с config.');
    }

    return ImportedGatewayConfig(
      protocol: protocol,
      displayName: (decoded['name'] as String?)?.trim().isNotEmpty == true
          ? (decoded['name'] as String).trim()
          : parsed.displayName,
      rawValue: config,
    );
  }

  static String _uriName(Uri uri) => uri.fragment.isEmpty
      ? '${uri.host}:${uri.port}'
      : Uri.decodeComponent(uri.fragment);
}

String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final digits = unit == 0 ? 0 : decimals;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String formatDuration(Duration duration) {
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}
