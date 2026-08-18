import 'sync_merge.dart';

/// Почему обмен с сервером не состоялся.
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

/// Итог отправки: какие записи сервер действительно принял, какой timestamp
/// он зафиксировал и что помешало остальным.
class SyncPushResult {
  /// Идентификаторы записей, которые сервер принял.
  final List<String> deliveredIds;

  /// Фактический timestamp, сохранённый сервером для принятой записи.
  ///
  /// Обычно он совпадает с отправленным клиентом. Но сервер намеренно
  /// нормализует слишком будущие часы устройства. Если клиент проигнорирует
  /// нормализованный stamp, его journal останется «в будущем» и запись будет
  /// отправляться снова после каждого pull.
  final Map<String, DateTime> acceptedStamps;

  /// Первая причина, по которой часть записей не уехала.
  final SyncFailure? failure;

  const SyncPushResult({
    this.deliveredIds = const [],
    this.acceptedStamps = const {},
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
