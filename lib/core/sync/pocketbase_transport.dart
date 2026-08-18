import 'dart:convert';
import 'dart:io';

import 'sync_clock.dart';
import 'sync_endpoint.dart';
import 'sync_merge.dart';
import 'sync_transport.dart';

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
    final res = await _send('GET', '/api/wesi/sync/revision-v2');
    if (res.failure != null) {
      if (res.failure!.code == 'NOT_WESIOS') {
        final legacy = await _send('GET', '/api/wesi/sync/revision');
        if (legacy.failure != null) return SyncResult.fail(legacy.failure!);
        return SyncResult.ok(revisionFromResponse(legacy.value!));
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
    SyncFailure? firstFailure;

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
        if (res.failure!.code == 'FORBIDDEN') continue;

        firstFailure ??= res.failure;
        if (_fatalCodes.contains(res.failure!.code)) break;
        continue;
      }

      // HTTP 200 + applied:false means the server rejected this stale write
      // at its LWW boundary. It must NOT be reported as delivered; the next
      // revision-driven pull will apply the authoritative remote row.
      if (res.value!['applied'] == false) continue;

      delivered.add(r.id);

      // The server can normalize an invalid/far-future client timestamp to its
      // own clock. Preserve the timestamp that was actually committed so the
      // local journal converges to the same LWW coordinate immediately.
      final accepted = DateTime.tryParse('${res.value!['stamp'] ?? ''}');
      if (accepted != null) {
        acceptedStamps[r.id] = accepted;
      } else {
        // The write already happened, so do not retry it blindly as if it
        // failed. Mark the pass degraded; SyncEngine will use an epoch journal
        // fallback for this delivered row, forcing a safe authoritative pull.
        firstFailure ??= SyncFailure(
          'REMOTE_DATA_INVALID',
          'Сервер принял $collection:${r.id}, но не вернул корректное время записи',
        );
      }
    }

    return SyncPushResult(
      deliveredIds: delivered,
      acceptedStamps: acceptedStamps,
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
