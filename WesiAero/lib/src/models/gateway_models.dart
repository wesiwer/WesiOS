import 'dart:convert';

enum TunnelStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

enum GatewayProtocol {
  automatic,
  vlessReality,
  amneziaWg;

  String get title => switch (this) {
        GatewayProtocol.automatic => 'Автоматически',
        GatewayProtocol.vlessReality => 'VLESS · REALITY',
        GatewayProtocol.amneziaWg => 'AmneziaWG',
      };

  String get wireName => switch (this) {
        GatewayProtocol.automatic => 'auto',
        GatewayProtocol.vlessReality => 'vless-reality',
        GatewayProtocol.amneziaWg => 'amneziawg',
      };
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
    this.errorMessage,
    this.isDemo = false,
  });

  const GatewaySnapshot.disconnected({this.isDemo = false})
      : status = TunnelStatus.disconnected,
        stats = const SessionStats(),
        node = null,
        protocol = GatewayProtocol.automatic,
        errorMessage = null;

  final TunnelStatus status;
  final SessionStats stats;
  final GatewayNode? node;
  final GatewayProtocol protocol;
  final String? errorMessage;
  final bool isDemo;

  GatewaySnapshot copyWith({
    TunnelStatus? status,
    SessionStats? stats,
    GatewayNode? node,
    GatewayProtocol? protocol,
    String? errorMessage,
    bool? isDemo,
    bool clearError = false,
  }) {
    return GatewaySnapshot(
      status: status ?? this.status,
      stats: stats ?? this.stats,
      node: node ?? this.node,
      protocol: protocol ?? this.protocol,
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

    if (value.startsWith('vless://')) {
      return _parseVless(value);
    }

    if (value.contains('[Interface]') && value.contains('[Peer]')) {
      return _parseAmneziaWg(value);
    }

    if (value.startsWith('{')) {
      return _parseJson(value);
    }

    throw const FormatException(
      'Поддерживаются VLESS URI, AmneziaWG/WireGuard INI и JSON-профиль.',
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

    final name = uri.fragment.isEmpty
        ? '${uri.host}:${uri.port}'
        : Uri.decodeComponent(uri.fragment);
    return ImportedGatewayConfig(
      protocol: GatewayProtocol.vlessReality,
      displayName: name,
      rawValue: value,
    );
  }

  static ImportedGatewayConfig _parseAmneziaWg(String value) {
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
        'В конфигурации AmneziaWG отсутствует ключ или Endpoint.',
      );
    }

    return ImportedGatewayConfig(
      protocol: GatewayProtocol.amneziaWg,
      displayName: 'Импортированный AmneziaWG',
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
      'amneziawg' => GatewayProtocol.amneziaWg,
      _ => throw const FormatException('Неизвестный протокол JSON-профиля.'),
    };
    final config = decoded['config'];
    if (config is! String || config.trim().isEmpty) {
      throw const FormatException('В JSON-профиле отсутствует поле config.');
    }

    return ImportedGatewayConfig(
      protocol: protocol,
      displayName: (decoded['name'] as String?)?.trim().isNotEmpty == true
          ? (decoded['name'] as String).trim()
          : 'Импортированный профиль',
      rawValue: config,
    );
  }
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

