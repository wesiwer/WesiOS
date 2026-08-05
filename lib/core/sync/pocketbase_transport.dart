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

  /// Транспорт на корпоративный сервер, с пропуском, если он ещё годен.
  ///
  /// Возврата null здесь больше нет: адрес зашит в сборку, «сервера не
  /// настроен» не бывает. Отсутствие входа — отдельный случай, и о нём
  /// говорит `isSignedIn`, а не отсутствие транспорта.
  static PocketBaseTransport fromSettings() {
    final t = PocketBaseTransport(SyncEndpoint.url);
    final session = SyncEndpoint.session;
    final expires = DateTime.tryParse('${session?['expiresAt']}');
    if (session != null && expires != null && expires.isAfter(DateTime.now())) {
      t._token = '${session['token']}';
      t._userId = '${session['userId']}';
    }
    return t;
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

    // PocketBase по умолчанию выдаёт токен на две недели. Точный срок лежит
    // внутри самого токена (JWT), но разбирать его ради этого не стоит:
    // просроченный токен всё равно распознаётся по ответу 401, а запас
    // в сутки избавляет от входа ровно на границе срока.
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
          // Без сортировки PocketBase отдаёт страницы в порядке создания;
          // явный порядок делает разбиение на страницы устойчивым, когда
          // между двумя запросами кто-то дописал запись.
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
          ? await _send('POST', '/api/collections/$collectionName/records',
              body: body)
          : await _send(
              'PATCH', '/api/collections/$collectionName/records/$serverId',
              body: body);

      if (res.failure != null) {
        // Одна отказавшая запись не должна отменять уже отправленные:
        // они на сервере, и сообщать об этом «ничего не ушло» — врать.
        return sent == 0
            ? SyncResult.fail(res.failure!)
            : SyncResult.ok(sent);
      }
      final id = res.value?['id'];
      if (id is String) _serverIds['$collection/${r.id}'] = id;
      sent++;
    }
    return SyncResult.ok(sent);
  }

  static int item2int(Object? raw) =>
      raw is num ? raw.toInt() : int.tryParse('$raw') ?? 1;

  // --------------------------------------------------------------- HTTP

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

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.openUrl(method, uri);
      if (auth && _token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, _token!);
      }
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 25));
      final text = await res.transform(utf8.decoder).join();

      if (res.statusCode == 401 || res.statusCode == 403) {
        // Токен протух или прав нет. Вход по паролю отличается отдельно:
        // там 400, и путать «пароль не тот» с «пропуск просрочен» нельзя.
        return SyncResult.fail(auth
            ? const SyncFailure('NOT_SIGNED_IN', 'Пропуск недействителен')
            : const SyncFailure('BAD_CREDENTIALS', 'Неверный логин или пароль'));
      }
      if (res.statusCode == 400 && !auth) {
        return const SyncResult.fail(
            SyncFailure('BAD_CREDENTIALS', 'Неверный логин или пароль'));
      }
      if (res.statusCode == 404) {
        return const SyncResult.fail(SyncFailure(
            'NOT_WESIOS', 'На сервере нет коллекции $collectionName'));
      }
      if (res.statusCode >= 400) {
        return SyncResult.fail(
            SyncFailure('HTTP_${res.statusCode}', _briefly(text)));
      }

      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) {
        return const SyncResult.fail(
            SyncFailure('NOT_WESIOS', 'Ответ сервера не разобрался'));
      }
      return SyncResult.ok(json);
    } on SocketException {
      return const SyncResult.fail(SyncFailure.offline);
    } on HandshakeException {
      return const SyncResult.fail(SyncFailure(
          'NETWORK', 'Сертификат сервера не принят'));
    } on FormatException {
      return const SyncResult.fail(
          SyncFailure('NOT_WESIOS', 'Ответ сервера не разобрался'));
    } catch (_) {
      return const SyncResult.fail(SyncFailure.offline);
    } finally {
      client.close();
    }
  }

  /// Ответ сервера может быть страницей на сотню килобайт. В сообщении об
  /// ошибке от неё пользы нет, а в журнале она мешает.
  static String _briefly(String text) {
    final one = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length <= 160 ? one : '${one.substring(0, 157)}…';
  }
}
