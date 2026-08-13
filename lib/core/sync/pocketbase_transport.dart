import 'dart:convert';
import 'dart:io';

import 'sync_clock.dart';
import 'sync_endpoint.dart';
import 'sync_merge.dart';
import 'sync_transport.dart';

/// Связь с сервером синхронизации на PocketBase.
class PocketBaseTransport implements SyncTransport {
  static const String collectionName = 'wesios_records';
  static const int pageSize = 500;

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 30);

  final String baseUrl;
  String? _token;
  String? _userId;
  String? _sessionId;
  final Map<String, String> _serverIds = {};

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
    _serverIds.clear();
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

    final out = <String, SyncRecord>{};
    var page = 1;
    while (true) {
      final res = await _send(
        'GET',
        '/api/collections/$collectionName/records',
        query: {
          'filter': "coll='$collection'",
          'perPage': '$pageSize',
          'page': '$page',
          'sort': 'id',
        },
      );
      if (res.failure != null) return SyncResult.fail(res.failure!);

      final items = res.value!['items'];
      if (items is! List) {
        return const SyncResult.fail(
          SyncFailure('NOT_WESIOS', 'В ответе нет списка записей'),
        );
      }
      for (final item in items) {
        if (item is! Map) continue;
        final rid = item['rid'];
        final serverId = item['id'];
        final stamp = DateTime.tryParse('${item['stamp']}');
        if (rid is! String || serverId is! String || stamp == null) continue;

        _serverIds['$collection/$rid'] = serverId;
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

      final totalPages = item2int(res.value!['totalPages']);
      if (items.length < pageSize || page >= totalPages) break;
      page++;
    }
    return SyncResult.ok(out);
  }

  Future<SyncResult<String>> revision() async {
    if (!isSignedIn) return const SyncResult.fail(SyncFailure.notSignedIn);
    final res = await _send(
      'GET',
      '/api/collections/$collectionName/records',
      query: const {
        'perPage': '1',
        'page': '1',
        'sort': '-stamp,-id',
        'fields': 'id,stamp',
      },
    );
    if (res.failure != null) return SyncResult.fail(res.failure!);
    return SyncResult.ok(revisionFromResponse(res.value!));
  }

  static String revisionFromResponse(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List || items.isEmpty) return 'empty';
    final first = items.first;
    if (first is! Map) return 'empty';
    final id = '${first['id'] ?? ''}';
    final stamp = '${first['stamp'] ?? ''}';
    return '$id|$stamp';
  }

  /// Отказы, после которых продолжать бессмысленно: дело не в записи, а в
  /// связи или в самом сервере. Всё остальное — беда конкретной записи
  /// (слишком большая, конфликт ключей), и она не повод бросать остальные.
  static const Set<String> _fatalCodes = {
    'NOT_SIGNED_IN',
    'NETWORK',
    'BAD_ADDRESS',
    'NOT_WESIOS',
  };

  @override
  Future<SyncPushResult> push(
    String collection,
    List<SyncRecord> records,
  ) async {
    if (!isSignedIn) {
      return const SyncPushResult(failure: SyncFailure.notSignedIn);
    }
    if (records.isEmpty) return const SyncPushResult();

    final delivered = <String>[];
    SyncFailure? firstFailure;
    for (final r in records) {
      final body = {
        'owner': _userId,
        'coll': collection,
        'rid': r.id,
        'payload': r.fields,
        'stamp': r.updatedAt.toUtc().toIso8601String(),
        'deleted': r.deleted,
      };
      final serverId = _serverIds['$collection/${r.id}'];
      final res = serverId == null
          ? await _send(
              'POST',
              '/api/collections/$collectionName/records',
              body: body,
            )
          : await _send(
              'PATCH',
              '/api/collections/$collectionName/records/$serverId',
              body: body,
            );

      if (res.failure != null) {
        firstFailure ??= res.failure;
        // Пропускаем эту запись и берёмся за следующую: одна упрямая
        // запись не должна держать взаперти всё, что за ней в очереди.
        if (_fatalCodes.contains(res.failure!.code)) break;
        continue;
      }
      final id = res.value?['id'];
      if (id is String) _serverIds['$collection/${r.id}'] = id;
      delivered.add(r.id);
    }
    return SyncPushResult(deliveredIds: delivered, failure: firstFailure);
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

    final sentAt = DateTime.now();
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
      // Сверяем часы по каждому ответу: это единственный момент, когда
      // устройство вообще слышит время сервера.
      await SyncClock.observeServerDate(
        res.headers.value(HttpHeaders.dateHeader),
        sentAt: sentAt,
        receivedAt: DateTime.now(),
      );
      final text = await res.transform(utf8.decoder).join();

      if (res.statusCode == 401 || res.statusCode == 403) {
        return SyncResult.fail(
          auth
              ? const SyncFailure('NOT_SIGNED_IN', 'Сеанс завершён')
              : const SyncFailure('BAD_CREDENTIALS', 'Неверные данные входа'),
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
            'На сервере нет коллекции $collectionName',
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
