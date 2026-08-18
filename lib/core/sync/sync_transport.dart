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
  /// Записи, которые сервер действительно сохранил из этого push.
  final List<String> deliveredIds;

  /// Фактические timestamps, сохранённые сервером для delivered rows.
  final Map<String, DateTime> acceptedStamps;

  /// Записи, для которых POST дошёл до сервера, но authoritative LWW/policy
  /// оставила уже существующую серверную версию (`applied:false`).
  ///
  /// Это НЕ ошибка сети и НЕ delivered upload. Engine обязан заново fetch-нуть
  /// коллекцию под текущими правами и применить фактическую серверную запись
  /// локально. Иначе stale/tie payload может остаться расходящимся навсегда,
  /// потому что сам сервер при applied:false свою revision не меняет.
  final List<String> authoritativeIds;

  /// Stamp серверной версии из applied:false response. Используется как
  /// sanity-check/диагностика; payload всё равно перечитывается через обычный
  /// permission-filtered GET, чтобы response на write не обходил read policy.
  final Map<String, DateTime> authoritativeStamps;

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
    this.authoritativeIds = const [],
    this.authoritativeStamps = const {},
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
