import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_merge.dart';
import 'package:wesios/core/sync/sync_transport.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/treasury/services/account_service.dart';

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
  bool _organizationBaselineReady = false;

  FakeSyncTransport({bool signedIn = true}) : _signedIn = signedIn;

  @override
  bool get isSignedIn => _signedIn;

  @override
  void signOut() => _signedIn = false;

  Future<void> _ensureProductionBaseline() async {
    if (_organizationBaselineReady) return;
    // Production initializes organizations and the root financial account
    // before normal synchronization. Legacy sync tests exercise SyncEngine in
    // isolation, so the fake transport mirrors that bootstrap when adapters
    // for the organization-aware model are present.
    if (Hive.isAdapterRegistered(81)) {
      await OrganizationService.ensureBaseline();
      await AccountService.ensureMain();
    }
    _organizationBaselineReady = true;
  }

  @override
  Future<SyncResult<String>> signIn(String login, String password) async {
    if (failWith != null) return SyncResult.fail(failWith!);
    _signedIn = true;
    return const SyncResult.ok('fake-user');
  }

  @override
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection) async {
    await _ensureProductionBaseline();
    calls.add('fetch:$collection');
    if (failWith != null) return SyncResult.fail(failWith!);
    if (!_signedIn) return const SyncResult.fail(SyncFailure.notSignedIn);
    return SyncResult.ok(Map.of(store[collection] ?? const {}));
  }

  @override
  Future<SyncResult<int>> push(
    String collection,
    List<SyncRecord> records,
  ) async {
    await _ensureProductionBaseline();
    calls.add('push:$collection:${records.length}');
    if (failWith != null) return SyncResult.fail(failWith!);
    if (!_signedIn) return const SyncResult.fail(SyncFailure.notSignedIn);
    final bucket = store.putIfAbsent(collection, () => {});
    for (final r in records) {
      bucket[r.id] = r;
    }
    return SyncResult.ok(records.length);
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
