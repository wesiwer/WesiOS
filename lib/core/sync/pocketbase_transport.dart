import 'dart:convert';
import 'dart:io';

import 'sync_clock.dart';
import 'sync_endpoint.dart';
import 'sync_merge.dart';
import 'sync_transport.dart';

class PocketBaseTransport implements SyncTransport {
  static const String collectionName = 'wesios_records';
  static const int pageSize = 500;

  /// Extended sync collections are routed through fresh versioned callbacks.
  /// PocketBase can retain already-registered JS callbacks across hot hook
  /// reloads, so reusing the legacy path could keep executing stale code even
  /// when the hook file on disk is already fixed. These v3 paths were deployed
  /// and verified independently on production before the client switched over.
  static const Set<String> _v3Collections = {
    'sandbox_transactions',
    'what_if_presets',
    'profile',
    'shield_private',
    'finance_categories',
    'team_skills',
    'time_center',
    'horizon_predictions',
    'horizon_learning',
    'horizon_competition',
    'horizon_contracts',
    'task_ai_memory',
    'audio_extras',
  };

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

  @override
  Future<SyncResult<String>> signIn(String login, String password) async {
    return const SyncResult.fail(
      SyncFailure(
        'MFA_REQUIRED',
        'Войдите через защищённый экран WesiOS и подтвердите код из почты',
      ),
    );
  }

  String _collectionPath(String collection) => _v3Collections.contains(collection)
      ? '/api/wesi/sync-v3/$collection'
      : '/api/wesi/sync/$collection';

  @override
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection) async {
    if (!isSignedIn) return const SyncResult.fail(SyncFailure.notSignedIn);

    final res = await _send('GET', _collectionPath(collection));
    if (res.failure != null) return SyncResult.fail(res.failure!);

    final items = res.value!['items'];
    if (items is! List) {
      return const SyncResult.fail(
        SyncFailure('NOT_WESIOS', 'В ответе нет списка записей'),
      );
    }

    final out = <String, SyncRecord>{};
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (item is! Map) {
        return SyncResult.fail(
          SyncFailure(
            'REMOTE_DATA_INVALID',
            'Повреждена запись $collection[$index] на сервере',
          ),
        );
      }
      final rid = item['rid'];
      final stamp = DateTime.tryParse('${item['stamp']}');
      final payload = item['payload'];
      if (rid is! String ||
          rid.isEmpty ||
          stamp == null ||
          payload is! Map) {
        return SyncResult.fail(
          SyncFailure(
            'REMOTE_DATA_INVALID',
            'Некорректная запись $collection[$index] на сервере',
          ),
        );
      }
      if (out.containsKey(rid)) {
        return SyncResult.fail(
          SyncFailure(
            'REMOTE_DATA_INVALID',
            'Сервер вернул дубликат $collection:$rid',
          ),
        );
      }
      out[rid] = SyncRecord(
        id: rid,
        updatedAt: stamp,
        deleted: item['deleted'] == true,
        fields: Map<String, dynamic>.from(payload),
      );
    }
    return SyncResult.ok(out);
  }

  Future<SyncResult<String>> revision() async {
    if (!isSignedIn) return const SyncResult.fail(SyncFailure.notSignedIn);

    // Prefer the newly registered route. Fallbacks remain only for rolling
    // compatibility with a server that has not received v3 yet.
    var res = await _send('GET', '/api/wesi/sync-v3/revision');
    if (res.failure?.code == 'NOT_WESIOS') {
      res = await _send('GET', '/api/wesi/sync/revision-v2');
    }
    if (res.failure != null) {
      if (res.failure!.code == 'NOT_WESIOS') {
        final legacy = await _send('GET', '/api/wesi/sync/revision');
        if (legacy.failure != null) return SyncResult.fail(legacy.failure!);

        // Rolling-deploy compatibility. The old endpoint derives its token
        // from a single max row and can miss equal-timestamp writes. While a
        // new client waits for a modern revision route to appear, append a
        // coarse safety bucket so a full pull happens at least once every five
        // seconds. This mode disappears automatically when v3/v2 is available.
        final legacyRevision = revisionFromResponse(legacy.value!);
        final safetyBucket = DateTime.now().millisecondsSinceEpoch ~/ 5000;
        return SyncResult.ok('$legacyRevision|compat:$safetyBucket');
      }
      return SyncResult.fail(res.failure!);
    }
    final revision = res.value!['revision'];
    if (revision is! String || revision.isEmpty) {
      return const SyncResult.fail(
        SyncFailure('NOT_WESIOS', 'Сервер не вернул ревизию синхронизации'),
      );
    }
    return SyncResult.ok(revision);
  }

  static String revisionFromResponse(Map<String, dynamic> json) {
    final direct = json['revision'];
    if (direct is String && direct.isNotEmpty) return direct;

    final items = json['items'];
    if (items is! List || items.isEmpty) return 'empty';
    final first = items.first;
    if (first is! Map) return 'empty';
    final id = '${first['id'] ?? ''}';
    final stamp = '${first['stamp'] ?? ''}';
    return '$id|$stamp';
  }

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
    final acceptedStamps = <String, DateTime>{};
    final authoritative = <String>[];
    final authoritativeStamps = <String, DateTime>{};
    final forbidden = <String>[];
    SyncFailure? firstFailure;

    for (final r in records) {
      final res = await _send(
        'POST',
        _collectionPath(collection),
        body: {
          'rid': r.id,
          'payload': r.fields,
          'stamp': r.updatedAt.toUtc().toIso8601String(),
          'deleted': r.deleted,
        },
      );
      if (res.failure != null) {
        if (res.failure!.code == 'FORBIDDEN') {
          forbidden.add(r.id);
          continue;
        }

        firstFailure ??= res.failure;
        if (_fatalCodes.contains(res.failure!.code)) break;
        continue;
      }

      final accepted = DateTime.tryParse('${res.value!['stamp'] ?? ''}');
      if (accepted == null) {
        firstFailure ??= SyncFailure(
          'REMOTE_DATA_INVALID',
          'Сервер ответил на $collection:${r.id}, но не вернул корректное время authoritative записи',
        );
        continue;
      }

      if (res.value!['applied'] == false) {
        // The request was understood, but server LWW/immutability kept its
        // existing row. This is not delivered local state: engine must refetch
        // the permission-filtered authoritative payload and apply it locally.
        authoritative.add(r.id);
        authoritativeStamps[r.id] = accepted;
        continue;
      }

      delivered.add(r.id);
      acceptedStamps[r.id] = accepted;
    }

    return SyncPushResult(
      deliveredIds: delivered,
      acceptedStamps: acceptedStamps,
      authoritativeIds: authoritative,
      authoritativeStamps: authoritativeStamps,
      forbiddenIds: forbidden,
      failure: firstFailure,
    );
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
      await SyncClock.observeServerDate(
        res.headers.value(HttpHeaders.dateHeader),
        sentAt: sentAt,
        receivedAt: DateTime.now(),
      );
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
            _briefly(text).isEmpty
                ? 'Нет доступа к этим данным'
                : _briefly(text),
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
