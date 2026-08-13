import 'package:wesios/core/sync/sync_merge.dart';
import 'package:wesios/core/sync/sync_transport.dart';

/// Сервер синхронизации, живущий в памяти теста.
///
/// Нужен, потому что иначе всё, что ниже транспорта — журнал, слияние,
/// применение к боксам — проверялось бы только живым сервером. Ошибка
/// синхронизации стоит потерянных данных, и обнаруживать её на настоящих
/// данных недопустимо.
class FakeSyncTransport implements SyncTransport {
  /// Состояние «сервера»: коллекция → записи.
  final Map<String, Map<String, SyncRecord>> store = {};

  /// Что и в каком порядке спрашивали — по этому проверяется, что движок
  /// действительно ходит на сервер, а не притворяется.
  final List<String> calls = [];

  /// Отказ, который транспорт выдаёт вместо работы. Так проверяется
  /// поведение при обрыве связи.
  SyncFailure? failWith;

  bool _signedIn = true;

  FakeSyncTransport({bool signedIn = true}) : _signedIn = signedIn;

  @override
  bool get isSignedIn => _signedIn;

  @override
  void signOut() => _signedIn = false;

  @override
  Future<SyncResult<String>> signIn(String login, String password) async {
    if (failWith != null) return SyncResult.fail(failWith!);
    _signedIn = true;
    return const SyncResult.ok('fake-user');
  }

  @override
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection) async {
    calls.add('fetch:$collection');
    if (failWith != null) return SyncResult.fail(failWith!);
    if (!_signedIn) return const SyncResult.fail(SyncFailure.notSignedIn);
    return SyncResult.ok(Map.of(store[collection] ?? const {}));
  }

  /// Записи, которые «сервер» отказывается принимать. Так проверяется, что
  /// одна упрямая запись не запирает всю очередь за собой.
  final Set<String> rejectIds = {};

  @override
  Future<SyncPushResult> push(
    String collection,
    List<SyncRecord> records,
  ) async {
    calls.add('push:$collection:${records.length}');
    if (failWith != null) return SyncPushResult(failure: failWith);
    if (!_signedIn) {
      return const SyncPushResult(failure: SyncFailure.notSignedIn);
    }
    final bucket = store.putIfAbsent(collection, () => {});
    final delivered = <String>[];
    SyncFailure? failure;
    for (final r in records) {
      if (rejectIds.contains(r.id)) {
        failure ??= const SyncFailure('HTTP_400', 'Запись не принята');
        continue;
      }
      bucket[r.id] = r;
      delivered.add(r.id);
    }
    return SyncPushResult(deliveredIds: delivered, failure: failure);
  }

  /// Положить запись «с другого устройства».
  void seed(
    String collection,
    String id,
    Map<String, dynamic> fields,
    DateTime at, {
    bool deleted = false,
  }) {
    store.putIfAbsent(collection, () => {})[id] = SyncRecord(
      id: id,
      fields: fields,
      updatedAt: at,
      deleted: deleted,
    );
  }
}
