import 'dart:convert';
import 'dart:io';

import 'sync_endpoint.dart';
import 'sync_merge.dart';
import 'sync_transport.dart';

/// Связь с сервером синхронизации WesiOS поверх PocketBase.
///
/// Прямые CRUD-запросы к `wesios_records` намеренно не используются:
/// встроенные правила коллекции оставляют каждую запись видимой только её
/// auth-владельцу. Корпоративный обмен сотрудников проходит через
/// `/api/wesi/sync/*`, где сервер проверяет WesiOS session, employeeId,
/// модульные права, организационные гранты и область конкретной записи.
class PocketBaseTransport implements SyncTransport {
  /// Оставлены публичными для совместимости старых тестов/диагностики.
  static const String collectionName = 'wesios_records';
  static const int pageSize = 500;

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 30);

  final String baseUrl;
  String? _token;
  String? _userId;
  String? _sessionId;

  PocketBaseTransport(this.baseUrl);

  static PocketBaseTransport fromSettings() {
    final t = PocketBaseTransport(SyncEndpoint.url);
    final session = SyncEndpoint.session;
    final expires = DateTime.tryParse('${session?['expiresAt']}');
    final sid = session?['sessionId'];
    if (session != null &&
        expires != null &&
        expires.isAfter(DateTime.now()) &&
        sid is String &&
        sid.isNotEmpty) {
      t._token = '${session['token']}';
      t._userId = '${session['userId']}';
      t._sessionId = sid;
    }
    return t;
  }

  @override
  bool get isSignedIn =>
      _token != null && _userId != null && _sessionId != null;

  @override
  void signOut() {
    _token = null;
    _userId = null;
    _sessionId = null;
  }

  /// Прямой password-auth больше не используется: он обходил бы почтовый
  /// второй фактор. Вход выполняет защищённый экран WesiOS, после чего этот
  /// транспорт получает готовый server token + revocable session id.
  @override
  Future<SyncResult<String>> signIn(String login, String password) async {
    return const SyncResult.fail(
      SyncFailure(
        'MFA_REQUIRED',
        'Войдите через защищённый экран WesiOS и подтвердите код из почты',
      ),
    );
  }

  @override
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection) async {
    if (!isSignedIn) return const SyncResult.fail(SyncFailure.notSignedIn);

    final res = await _send('GET', '/api/wesi/sync/$collection');
    if (res.failure != null) return SyncResult.fail(res.failure!);

    final items = res.value!['items'];
    if (items is! List) {
      return const SyncResult.fail(
        SyncFailure('NOT_WESIOS', 'В ответе нет списка записей'),
      );
    }

    final out = <String, SyncRecord>{};
    for (final item in items) {
      if (item is! Map) continue;
      final rid = item['rid'];
      final stamp = DateTime.tryParse('${item['stamp']}');
      if (rid is! String || rid.isEmpty || stamp == null) continue;
      final payload = item['payload'];
      out[rid] = SyncRecord(
        id: rid,
        updatedAt: stamp,
        deleted: item['deleted'] == true,
        fields: payload is Map
            ? Map<String, dynamic>.from(payload)
            : const {},
      );
    }
    return SyncResult.ok(out);
  }

  Future<SyncResult<String>> revision() async {
    if (!isSignedIn) return const SyncResult.fail(SyncFailure.notSignedIn);
    final res = await _send('GET', '/api/wesi/sync/revision');
    if (res.failure != null) return SyncResult.fail(res.failure!);
    final revision = res.value!['revision'];
    if (revision is! String || revision.isEmpty) {
      return const SyncResult.fail(
        SyncFailure('NOT_WESIOS', 'Сервер не вернул ревизию синхронизации'),
      );
    }
    return SyncResult.ok(revision);
  }

  /// Старый формат ответа PocketBase оставлен для unit-тестов миграционного
  /// слоя. Рабочий transport получает готовую строку с `/api/wesi/sync/revision`.
  static String revisionFromResponse(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List || items.isEmpty) return 'empty';
    final first = items.first;
    if (first is! Map) return 'empty';
    final id = '${first['id'] ?? ''}';
    final stamp = '${first['stamp'] ?? ''}';
    return '$id|$stamp';
  }

  @override
  Future<SyncResult<int>> push(
    String collection,
    List<SyncRecord> records,
  ) async {
    if (!isSignedIn) return const SyncResult.fail(SyncFailure.notSignedIn);
    if (records.isEmpty) return const SyncResult.ok(0);

    var sent = 0;
    for (final r in records) {
      final res = await _send(
        'POST',
        '/api/wesi/sync/$collection',
        body: {
          'rid': r.id,
          'payload': r.fields,
          'stamp': r.updatedAt.toUtc().toIso8601String(),
          'deleted': r.deleted,
        },
      );
      if (res.failure != null) {
        // Локальная база может содержать строки, которые были доступны
        // предыдущему сотруднику на общем устройстве. Сервер — настоящая
        // граница доступа: запрещённую строку не отправляем, но и не срываем
        // синхронизацию разрешённых строк той же коллекции.
        if (res.failure!.code == 'FORBIDDEN') continue;
        return sent == 0
            ? SyncResult.fail(res.failure!)
            : SyncResult.ok(sent);
      }
      sent++;
    }
    return SyncResult.ok(sent);
  }

  static int item2int(Object? raw) =>
      raw is num ? raw.toInt() : int.tryParse('$raw') ?? 1;

  Future<SyncResult<Map<String, dynamic>>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final base = Uri.tryParse(baseUrl);
    if (base == null || base.host.isEmpty) {
      return const SyncResult.fail(SyncFailure('BAD_ADDRESS', 'Плохой адрес'));
    }
    final uri = base.replace(path: path, queryParameters: query);

    try {
      final req = await _http.openUrl(method, uri);
      if (auth && _token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, _token!);
        if (_sessionId != null) {
          req.headers.set('X-WesiOS-Session', _sessionId!);
        }
      }
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 25));
      final text = await res.transform(utf8.decoder).join();

      if (res.statusCode == 401) {
        return SyncResult.fail(
          auth
              ? const SyncFailure('NOT_SIGNED_IN', 'Сеанс завершён')
              : const SyncFailure('BAD_CREDENTIALS', 'Неверные данные входа'),
        );
      }
      if (res.statusCode == 403) {
        return SyncResult.fail(
          SyncFailure(
            'FORBIDDEN',
            _briefly(text).isEmpty ? 'Нет доступа к этим данным' : _briefly(text),
          ),
        );
      }
      if (res.statusCode == 400 && !auth) {
        return const SyncResult.fail(
          SyncFailure('BAD_CREDENTIALS', 'Неверные данные входа'),
        );
      }
      if (res.statusCode == 404) {
        return const SyncResult.fail(
          SyncFailure(
            'NOT_WESIOS',
            'На сервере не установлен шлюз синхронизации WesiOS',
          ),
        );
      }
      if (res.statusCode >= 400) {
        return SyncResult.fail(
          SyncFailure('HTTP_${res.statusCode}', _briefly(text)),
        );
      }

      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) {
        return const SyncResult.fail(
          SyncFailure('NOT_WESIOS', 'Ответ сервера не разобрался'),
        );
      }
      return SyncResult.ok(json);
    } on SocketException {
      return const SyncResult.fail(SyncFailure.offline);
    } on HandshakeException {
      return const SyncResult.fail(
        SyncFailure('NETWORK', 'Сертификат сервера не принят'),
      );
    } on FormatException {
      return const SyncResult.fail(
        SyncFailure('NOT_WESIOS', 'Ответ сервера не разобрался'),
      );
    } catch (_) {
      return const SyncResult.fail(SyncFailure.offline);
    }
  }

  static String _briefly(String text) {
    final one = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length <= 160 ? one : '${one.substring(0, 157)}…';
  }
}
