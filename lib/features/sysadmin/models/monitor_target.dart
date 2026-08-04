/// Что именно наблюдаем.
enum TargetKind {
  /// Машина: смотрим порт, а если стоит агент — ещё и загрузку.
  server,

  /// Домен: разрешается ли имя, жив ли сертификат.
  domain,

  /// Сайт: отвечает ли по HTTP и каким кодом.
  site,
}

/// Наблюдаемый узел.
///
/// Хранится обычным JSON в настройках, без адаптера Hive. Причина простая:
/// список из нескольких строк не стоит отдельного типа на диске, а менять
/// набор полей по ходу дела придётся не раз.
class MonitorTarget {
  final String id;
  final String name;

  /// Имя или адрес. Для сайта берётся из [url], если не задано отдельно.
  final String host;

  /// Порт для замера времени ответа.
  final int port;

  /// Полный адрес для проверки по HTTP. null — не проверяем.
  final String? url;

  /// Откуда брать загрузку сервера. Это адрес агента, установленного на
  /// самом сервере (`server/wesios-agent.sh`). Без него загрузку узнать
  /// неоткуда — см. пояснение в `NetworkProbe.load`.
  final String? loadUrl;

  final TargetKind kind;

  /// Проверять срок сертификата.
  final bool checkTls;

  const MonitorTarget({
    required this.id,
    required this.name,
    required this.host,
    this.port = 443,
    this.url,
    this.loadUrl,
    this.kind = TargetKind.server,
    this.checkTls = false,
  });

  MonitorTarget copyWith({
    String? name,
    String? host,
    int? port,
    Object? url = _unset,
    Object? loadUrl = _unset,
    TargetKind? kind,
    bool? checkTls,
  }) =>
      MonitorTarget(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        // Тот же приём, что в статьях базы знаний: без метки «не передано»
        // нельзя отличить «оставь как было» от «сотри».
        url: identical(url, _unset) ? this.url : url as String?,
        loadUrl:
            identical(loadUrl, _unset) ? this.loadUrl : loadUrl as String?,
        kind: kind ?? this.kind,
        checkTls: checkTls ?? this.checkTls,
      );

  static const Object _unset = Object();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'url': url,
        'loadUrl': loadUrl,
        'kind': kind.name,
        'checkTls': checkTls,
      };

  static MonitorTarget? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    final host = json['host'];
    if (id is! String || host is! String || host.trim().isEmpty) return null;
    return MonitorTarget(
      id: id,
      name: json['name'] is String && (json['name'] as String).trim().isNotEmpty
          ? json['name'] as String
          : host,
      host: host.trim(),
      port: json['port'] is num ? (json['port'] as num).toInt() : 443,
      url: json['url'] is String ? json['url'] as String : null,
      loadUrl: json['loadUrl'] is String ? json['loadUrl'] as String : null,
      kind: TargetKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => TargetKind.server,
      ),
      checkTls: json['checkTls'] == true,
    );
  }

  String labelRu() => switch (kind) {
        TargetKind.server => 'Сервер',
        TargetKind.domain => 'Домен',
        TargetKind.site => 'Сайт',
      };

  String labelEn() => switch (kind) {
        TargetKind.server => 'Server',
        TargetKind.domain => 'Domain',
        TargetKind.site => 'Site',
      };
}
