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

  /// Человеческая формулировка. Код без объяснения — это не сообщение об
  /// ошибке, а повод её не понять.
  String describe({bool russian = true}) {
    if (!russian) return message;
    return switch (code) {
      'NETWORK' => 'Нет связи с сервером',
      'NOT_SIGNED_IN' => 'Вход на сервер не выполнен',
      'BAD_CREDENTIALS' => 'Неверный логин или пароль',
      'FORBIDDEN' => 'Сервер отказал в доступе',
      'BAD_ADDRESS' => 'Адрес сервера записан неправильно',
      // Сервер ответил, но не тем, чего мы ждём: обычно это чужой сайт по
      // указанному адресу, а не сломанный WesiOS-сервер. Разница важная —
      // человеку надо проверить адрес, а не чинить сервер.
      'NOT_WESIOS' => 'По этому адресу отвечает не сервер WesiOS',
      _ => message,
    };
  }

  @override
  String toString() => 'SyncFailure($code, $message)';
}

/// Результат: либо значение, либо причина отказа. Ровно одно из двух.
class SyncResult<T> {
  final T? value;
  final SyncFailure? failure;

  const SyncResult.ok(T this.value) : failure = null;
  const SyncResult.fail(SyncFailure this.failure) : value = null;

  bool get ok => failure == null;
}

/// Итог отправки: что именно уехало и что помешало остальным.
///
/// Раньше отправка возвращала просто число. Из-за этого две вещи терялись
/// молча. Во-первых, ошибка на одной записи прекращала отправку всех
/// следующих: сбойная третья из пятидесяти оставляла сорок семь дома.
/// Во-вторых, при частичном успехе отказ вообще не возвращался — отчёт
/// показывал «отправлено 2» и зелёную галочку, хотя остальное не уехало. Если
/// причина устойчивая (запись больше лимита, конфликт ключей), это
/// повторялось каждый проход, и человек не видел ни одного признака.
///
/// Поэтому здесь и список доехавших, и причина отказа одновременно: они не
/// исключают друг друга.
class SyncPushResult {
  /// Идентификаторы записей, которые сервер принял.
  final List<String> deliveredIds;

  /// Первая причина, по которой часть записей не уехала.
  final SyncFailure? failure;

  const SyncPushResult({this.deliveredIds = const [], this.failure});

  int get sent => deliveredIds.length;

  bool get ok => failure == null;
}

/// Связь с сервером синхронизации.
///
/// Отдельный интерфейс здесь не ради «архитектуры»: без него всё, что ниже —
/// слияние, журнал, применение к боксам — можно было бы проверить только
/// живым сервером. То есть никогда, потому что сервера в тестах нет, а на
/// живом ошибка синхронизации стоит потерянных данных.
abstract class SyncTransport {
  /// Вход. Токен транспорт держит у себя: движку он не нужен, а лишняя
  /// копия токена — лишнее место, откуда он может утечь.
  Future<SyncResult<String>> signIn(String login, String password);

  bool get isSignedIn;

  void signOut();

  /// Всё, что лежит на сервере в этой коллекции, включая надгробия.
  ///
  /// Надгробия обязательно: без них удаление, сделанное на другом
  /// устройстве, до нас не доедет, а запись воскреснет.
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection);

  /// Отправка. Записи, которых на сервере нет, создаются; остальные
  /// переписываются целиком.
  ///
  /// Отказ на одной записи не должен отменять остальные: реализация обязана
  /// пропустить её и продолжить, вернув и список доехавших, и причину.
  Future<SyncPushResult> push(String collection, List<SyncRecord> records);
}
