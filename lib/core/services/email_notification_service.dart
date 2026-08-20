import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

import '../notifications/wesi_notifications.dart';
import '../sync/sync_endpoint.dart';

/// Серверное дублирование уведомлений на электронную почту сотрудника.
///
/// Адрес получателя намеренно не передаётся с клиента: сервер каждый раз
/// берёт актуальную почту из карточки сотрудника. В защищённом хранилище
/// лежит только небольшой outbox на случай временной потери связи.
class EmailNotificationService {
  const EmailNotificationService._();

  static const String _settingsBox = 'wesios_settings';
  static const String _enabledKey = 'notify_email_enabled';
  static const String _outboxKey = 'wesios_email_notification_outbox_v1';
  static const int _maxPending = 200;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Future<void> _tail = Future<void>.value();

  static Box<dynamic>? _box() {
    try {
      return Hive.box<dynamic>(_settingsBox);
    } catch (_) {
      return null;
    }
  }

  /// Email-дублирование включено по умолчанию: это новый основной канал,
  /// который пользователь при необходимости может отключить отдельно.
  static bool get enabled => _box()?.get(_enabledKey) != false;

  static Future<void> setEnabled(bool value) => _serialized(() async {
        await _box()?.put(_enabledKey, value);
        if (!value) {
          try {
            await _secureStorage.delete(key: _outboxKey);
          } catch (error) {
            debugPrint('WesiOS email outbox clear failed: $error');
          }
        }
        revision.value++;
        if (value) await _flushUnlocked();
      });

  /// Сначала фиксирует событие в защищённом outbox, затем пытается отправить.
  /// Ошибки канала не ломают локальное уведомление и не выходят наружу.
  static Future<void> enqueue(WesiNotification notification) =>
      _serialized(() async {
        if (!enabled) return;
        final auth = _auth();
        if (auth == null) return;

        final pending = await _readOutbox();
        final exists = pending.any(
          (entry) =>
              entry['scope'] == auth.scope && entry['id'] == notification.id,
        );
        if (!exists) {
          pending.add(<String, dynamic>{
            'scope': auth.scope,
            'id': notification.id,
            'title': notification.title,
            'body': notification.body,
            'kind': notification.kind.name,
            'route': notification.route,
            'occurredAt': DateTime.now().toUtc().toIso8601String(),
          });
          if (pending.length > _maxPending) {
            pending.removeRange(0, pending.length - _maxPending);
          }
          await _writeOutbox(pending);
        }
        await _flushUnlocked();
      });

  /// Повторяет отправку накопленного outbox после запуска или восстановления
  /// соединения. События другой учётной записи не смешиваются с текущей.
  static Future<void> flush() => _serialized(_flushUnlocked);

  static Future<void> _flushUnlocked() async {
    if (!enabled) return;
    final auth = _auth();
    if (auth == null) return;

    var pending = await _readOutbox();
    while (true) {
      final index = pending.indexWhere((entry) => entry['scope'] == auth.scope);
      if (index < 0) return;

      final entry = pending[index];
      final result = await _send(auth, entry);
      if (result == _EmailSendResult.retry) return;

      pending.removeAt(index);
      await _writeOutbox(pending);
    }
  }

  static Future<_EmailSendResult> _send(
    _EmailAuth auth,
    Map<String, dynamic> entry,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .postUrl(auth.baseUri.resolve('/api/wesi/notifications/email'))
          .timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.authorizationHeader, auth.token);
      request.headers.set('X-WesiOS-Session', auth.sessionId);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.write(jsonEncode(<String, dynamic>{
        'id': '${entry['id'] ?? ''}',
        'title': '${entry['title'] ?? ''}',
        'body': '${entry['body'] ?? ''}',
        'kind': '${entry['kind'] ?? ''}',
        'route': entry['route'],
        'occurredAt': '${entry['occurredAt'] ?? ''}',
      }));

      final response = await request.close().timeout(const Duration(seconds: 20));
      await response.drain().timeout(const Duration(seconds: 8));
      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        return _EmailSendResult.delivered;
      }
      // Некорректное событие, закрытый профиль или отсутствующая почта —
      // постоянные причины. Старое письмо не должно внезапно уйти позже.
      if (status == 400 || status == 403 || status == 422) {
        return _EmailSendResult.drop;
      }
      // 401 может исчезнуть после обновления сессии, 404 — после серверного
      // деплоя, 429/5xx — после восстановления сервиса.
      return _EmailSendResult.retry;
    } catch (error) {
      debugPrint('WesiOS email notification send failed: $error');
      return _EmailSendResult.retry;
    } finally {
      client.close(force: true);
    }
  }

  static _EmailAuth? _auth() {
    if (!SyncEndpoint.isConnected) return null;
    final session = SyncEndpoint.session;
    if (session == null) return null;

    final token = '${session['token'] ?? ''}'.trim();
    final userId = '${session['userId'] ?? ''}'.trim();
    final sessionId = '${session['sessionId'] ?? ''}'.trim();
    final baseUri = Uri.tryParse(SyncEndpoint.url);
    if (token.isEmpty ||
        userId.isEmpty ||
        sessionId.isEmpty ||
        baseUri == null ||
        !baseUri.hasScheme ||
        baseUri.host.isEmpty) {
      return null;
    }
    return _EmailAuth(
      baseUri: baseUri,
      token: token,
      sessionId: sessionId,
      scope: '${baseUri.origin}|$userId',
    );
  }

  static Future<List<Map<String, dynamic>>> _readOutbox() async {
    try {
      final raw = await _secureStorage.read(key: _outboxKey);
      if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return <Map<String, dynamic>>[
        for (final item in decoded)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    } catch (error) {
      debugPrint('WesiOS email outbox read failed: $error');
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> _writeOutbox(
    List<Map<String, dynamic>> pending,
  ) async {
    try {
      if (pending.isEmpty) {
        await _secureStorage.delete(key: _outboxKey);
      } else {
        await _secureStorage.write(
          key: _outboxKey,
          value: jsonEncode(pending),
        );
      }
    } catch (error) {
      debugPrint('WesiOS email outbox write failed: $error');
    }
  }

  static Future<void> _serialized(Future<void> Function() action) {
    final next = _tail.then((_) async {
      try {
        await action();
      } catch (error, stackTrace) {
        debugPrint('WesiOS email notification error: $error\n$stackTrace');
      }
    });
    _tail = next;
    return next;
  }
}

enum _EmailSendResult { delivered, retry, drop }

class _EmailAuth {
  const _EmailAuth({
    required this.baseUri,
    required this.token,
    required this.sessionId,
    required this.scope,
  });

  final Uri baseUri;
  final String token;
  final String sessionId;
  final String scope;
}
