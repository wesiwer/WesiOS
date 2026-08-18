import 'package:wesios/core/sync/sync_merge.dart';
import 'package:wesios/core/sync/sync_transport.dart';

/// Сервер синхронизации, живущий в памяти теста.
class FakeSyncTransport implements SyncTransport {
  /// Состояние «сервера»: коллекция → записи.
  final Map<String, Map<String, SyncRecord>> store = {};

  final List<String> calls = [];

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

  /// Записи, которые «сервер» отказывается принимать.
  final Set<String> rejectIds = {};

  /// Необязательная нормализация принятого времени конкретной записи.
  ///
  /// Реальный сервер использует это, когда часы устройства слишком далеко в
  /// будущем. По умолчанию fake сохраняет исходный timestamp, как нормальный
  /// успешный серверный write.
  final Map<String, DateTime> acceptedStampOverrides = {};

  /// Имитирует повреждённый успешный ответ: запись сервер принял, но stamp в
  /// ответе отсутствует/не разбирается. Engine обязан fail closed перевести
  /// journal этой записи в epoch и получить серверную версию следующим pull.
  final Set<String> omitAcceptedStampIds = {};

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
    final acceptedStamps = <String, DateTime>{};
    SyncFailure? failure;

    for (final r in records) {
      if (rejectIds.contains(r.id)) {
        failure ??= const SyncFailure('HTTP_400', 'Запись не принята');
        continue;
      }

      final acceptedStamp = acceptedStampOverrides[r.id] ?? r.updatedAt;
      bucket[r.id] = SyncRecord(
        id: r.id,
        fields: r.fields,
        updatedAt: acceptedStamp,
        deleted: r.deleted,
      );
      delivered.add(r.id);
      if (!omitAcceptedStampIds.contains(r.id)) {
        acceptedStamps[r.id] = acceptedStamp;
      }
    }

    return SyncPushResult(
      deliveredIds: delivered,
      acceptedStamps: acceptedStamps,
      failure: failure,
    );
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