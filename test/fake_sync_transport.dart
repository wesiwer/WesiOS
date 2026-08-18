import 'package:wesios/core/sync/sync_merge.dart';
import 'package:wesios/core/sync/sync_transport.dart';

/// Сервер синхронизации, живущий в памяти теста.
class FakeSyncTransport implements SyncTransport {
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

  /// Обычный устойчивый отказ конкретной записи (HTTP 400 и т.п.).
  final Set<String> rejectIds = {};

  /// Policy denial: запись текущей server identity изменять нельзя.
  final Set<String> forbiddenIds = {};

  /// Необязательная нормализация принятого времени конкретной записи.
  final Map<String, DateTime> acceptedStampOverrides = {};

  /// Успешный write без возвращённого stamp.
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
    final forbidden = <String>[];
    SyncFailure? failure;

    for (final r in records) {
      if (forbiddenIds.contains(r.id)) {
        forbidden.add(r.id);
        continue;
      }
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
      forbiddenIds: forbidden,
      failure: failure,
    );
  }

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