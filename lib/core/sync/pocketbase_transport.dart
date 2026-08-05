import 'dart:convert';
import 'dart:io';

import 'sync_endpoint.dart';
import 'sync_merge.dart';
import 'sync_transport.dart';

/// Связь с сервером синхронизации на PocketBase.
///
/// **Почему PocketBase.** Сервер — один процессор и два гигабайта памяти.
/// PocketBase — один исполняемый файл на Go с SQLite внутри, ему хватает
/// полусотни мегабайт. Тот же набор возможностей на связке Postgres +
/// приложение + очередь съел бы всю память, и синхронизация конкурировала бы
/// за неё с остальным, что на сервере живёт.
///
/// **Одна коллекция вместо пяти.** Всё лежит в `wesios_records`: операции,
/// задачи, счета, статьи, люди — с пометкой, что это. Иначе схему на сервере
/// пришлось бы менять при каждом новом поле в модели, а расхождение схемы с
/// приложением выглядит как «синхронизация молча не работает».
class PocketBaseTransport implements SyncTransport {
  /// Имя коллекции на сервере. Совпадает с рецептом развёртывания
  /// (`server/README.md`) — менять только вместе с ним.
  static const String collectionName = 'wesios_records';

  /// Сколько записей просить за раз. PocketBase отдаёт максимум 500.
  static const int pageSize = 500;

  final String baseUrl;

  String? _token;
  String? _userId;

  /// Наш идентификатор → внутренний идентификатор PocketBase.
  ///
  /// Нужен, потому что upsert-а в PocketBase нет: чтобы переписать запись,
  /// надо знать её `id`, а он назначается сервером и с нашим не совпадает.
  /// Заполняется при [fetch], которое всё равно происходит перед [push].
  final Map<String, String> _serverIds = {};

  PocketBaseTransport(this.baseUrl);

  /// Транспорт из сохранённых настроек. Корпоративный сервер теперь всегда
  /// задан, nullable-тип оставлен только для совместимости старых вызовов.
  static PocketBaseTransport? fromSettings() {
    final transport = PocketBaseTransport(SyncEndpoint.url);
    final session = SyncEndpoint.session;
    final expires = DateTime.tryParse('${session?['expiresAt']}');
    if (session != null && expires != null && expires.isAfter(DateTime.now())) {
      transport._token = '${session['token']}';
      transport._userId = '${session['userId']}';
    }
    return transport;
  }

  @override
  bool get isSignedIn => _token != null && _userId != null;

  @override
  void signOut() {
    _token = null;
    _userId = null;
    _serverIds.clear();
  }

  @override
  Future<SyncResult<String>> signIn(String login, String password) async {
    final res = await _send(
      'POST',
      '/api/collections/users/auth-with-password',
      body: {'identity': login, 'password': password},
      auth: false,
    );
    if (res.failure != null) return SyncResult.fail(res.failure!);

    final json = res.value!;
    final token = json['token'];
    final record = json['record'];
    if (token is! String || record is! Map || record['id'] is! String) {
      return const SyncResult.fail(
        SyncFailure('NOT_WESIOS', 'Сервер ответил не тем, чего мы ждём'),
      );
    }
    _token = token;
    _userId = '${record['id']}';

    await SyncEndpoint.saveSession(
      token: token,
      userId: _userId!,
      expiresAt: DateTime.now().add(const Duration(days: 13)),
    );
    return SyncResult.ok(_userId!);
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

  @override
  Future<SyncResult<int>> push(
    String collection,
    List<SyncRecord> records,
  ) async {
    if (!isSignedIn) return const SyncResult.fail(SyncFailure.notSignedIn);
    if (records.isEmpty) return const SyncResult.ok(0);

    var sent = 0;
    for (final record in records) {
      final body = {
        'owner': _userId,
        'coll': collection,
        'rid': record.id,
        'payload': record.fields,
        'stamp': record.updatedAt.toUtc().toIso8601String(),
        'deleted': record.deleted,
      };
      final serverId = _serverIds['$collection/${record.id}'];
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
        return sent == 0
            ? SyncResult.fail(res.failure!)
            : SyncResult.ok(sent);
      }
      final id = res.value?['id'];
      if (id is String) _serverIds['$collection/${record.id}'] = id;
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
      return const SyncResult.fail(
        SyncFailure('BAD_ADDRESS', 'Плохой адрес'),
      );
    }
    final uri = base.replace(path: path, queryParameters: query);

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.openUrl(method, uri);
      if (auth && _token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, _token!);
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response =
          await request.close().timeout(const Duration(seconds: 25));
      final text = await response.transform(utf8.decoder).join();

      if (response.statusCode == 401 || response.statusCode == 403) {
        return SyncResult.fail(
          auth
              ? const SyncFailure(
                  'NOT_SIGNED_IN',
                  'Пропуск недействителен',
                )
              : const SyncFailure(
                  'BAD_CREDENTIALS',
                  'Неверный логин или пароль',
                ),
        );
      }
      if (response.statusCode == 400 && !auth) {
        return const SyncResult.fail(
          SyncFailure('BAD_CREDENTIALS', 'Неверный логин или пароль'),
        );
      }
      if (response.statusCode == 404) {
        return const SyncResult.fail(
          SyncFailure(
            'NOT_WESIOS',
            'На сервере нет коллекции $collectionName',
          ),
        );
      }
      if (response.statusCode >= 400) {
        return SyncResult.fail(
          SyncFailure('HTTP_${response.statusCode}', _briefly(text)),
        );
      }

      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        return const SyncResult.fail(
          SyncFailure('NOT_WESIOS', 'Ответ сервера не разобрался'),
        );
      }
      return SyncResult.ok(decoded);
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
    } finally {
      client.close();
    }
  }

  static String _briefly(String text) {
    final one = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length <= 160 ? one : '${one.substring(0, 157)}…';
  }
}
