import 'sync_merge.dart';

class SyncFailure {
  final String code;
  final String message;

  const SyncFailure(this.code, this.message);

  static const SyncFailure offline =
      SyncFailure('NETWORK', 'Нет связи с сервером');
  static const SyncFailure notSignedIn =
      SyncFailure('NOT_SIGNED_IN', 'Вход на сервер не выполнен');

  String describe({bool russian = true}) {
    if (!russian) return message;
    return switch (code) {
      'NETWORK' => 'Нет связи с сервером',
      'NOT_SIGNED_IN' => 'Вход на сервер не выполнен',
      'BAD_CREDENTIALS' => 'Неверный логин или пароль',
      'FORBIDDEN' => 'Сервер отказал в доступе',
      'BAD_ADDRESS' => 'Адрес сервера записан неправильно',
      'NOT_WESIOS' => 'По этому адресу отвечает не сервер WesiOS',
      _ => message,
    };
  }

  @override
  String toString() => 'SyncFailure($code, $message)';
}

class SyncResult<T> {
  final T? value;
  final SyncFailure? failure;

  const SyncResult.ok(T this.value) : failure = null;
  const SyncResult.fail(SyncFailure this.failure) : value = null;

  bool get ok => failure == null;
}

/// Итог отправки одной коллекции.
class SyncPushResult {
  /// Записи, которые сервер действительно сохранил.
  final List<String> deliveredIds;

  /// Фактические timestamps, сохранённые сервером для delivered rows.
  final Map<String, DateTime> acceptedStamps;

  /// Записи, запись которых сервер запретил текущей server identity.
  ///
  /// Это отдельный исход, а не обычная ошибка сети. После fetch клиент уже
  /// знает, видна ли серверная версия такого ID текущему сотруднику. Engine
  /// использует это для очистки отозванного локального кэша или отката
  /// запрещённой локальной правки к read-only remote версии.
  final List<String> forbiddenIds;

  /// Первая обычная причина частичного/полного сбоя.
  final SyncFailure? failure;

  const SyncPushResult({
    this.deliveredIds = const [],
    this.acceptedStamps = const {},
    this.forbiddenIds = const [],
    this.failure,
  });

  int get sent => deliveredIds.length;
  bool get ok => failure == null;
}

abstract class SyncTransport {
  Future<SyncResult<String>> signIn(String login, String password);

  bool get isSignedIn;

  void signOut();

  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection);

  Future<SyncPushResult> push(String collection, List<SyncRecord> records);
}
