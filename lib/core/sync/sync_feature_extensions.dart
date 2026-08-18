import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:hive/hive.dart';

import '../../features/team/models/employee_model.dart';
import '../../features/team/services/team_service.dart';
import '../security/secret_vault.dart';
import '../security/shield_service.dart';
import 'sync_account_scope.dart';
import 'sync_auto.dart';
import 'sync_codec.dart';
import 'sync_endpoint.dart';
import 'sync_engine.dart';

/// Adds synchronization for feature state that used to live only on one
/// device: Roadmap, CRM, Profile/Shield and encrypted Secret Vault rows.
class SyncFeatureExtensions {
  SyncFeatureExtensions._();

  static const _settingsBox = 'wesios_settings';
  static const _profileOwnerKey = 'sync_profile_settings_owner_v1';
  static const _profileBoxPrefix = 'wesios_profile_sync_v1';
  static const _vaultBoxPrefix = 'wesios_vault_sync_v1';
  static const _lastRunKey = 'sync_last_run';
  static const _seededKey = 'sync_seeded_at';
  static const _vaultSaltKey = 'vault_kdf_salt';
  static const _vaultPrefix = 'vault_secret_';

  static const Set<String> _profileKeys = {
    'profile_name',
    'profile_email',
    'profile_gender',
    'profile_country',
    'profile_birth',
    'avatar_index',
    'avatar_custom',
    // Portable Shield configuration. Biometric enrollment, failed attempts
    // and the local security log stay device-local.
    'shield_hash',
    'shield_salt',
    'shield_iterations',
    'shield_scope',
    'shield_timeout_minutes',
    'shield_wipe_after',
    'shield_password_hint',
  };

  static bool _registered = false;
  static bool _rebinding = false;
  static Future<void>? _rebindFuture;
  static int _rebindRequestGeneration = 0;
  static String? _boundEmployeeId;
  static String? _boundAuthUserId;
  static StreamSubscription<BoxEvent>? _settingsSub;
  static Timer? _avatarProjection;

  static String _safe(String raw) =>
      raw.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  /// Private box namespace follows PocketBase auth user — the same identity the
  /// server uses for `owner=e.auth.id` and SyncJournal uses for its account
  /// scope. Employee id remains part of the record id, but must never decide
  /// which local vault/profile box is opened.
  static String profileBoxName([String? authUserId]) =>
      SyncAccountScope.forUser(
        _profileBoxPrefix,
        authUserId ?? SyncAccountScope.currentUserId,
      );

  static String vaultBoxName([String? authUserId]) =>
      SyncAccountScope.forUser(
        _vaultBoxPrefix,
        authUserId ?? SyncAccountScope.currentUserId,
      );

  static String _legacyProfileBoxName(String employeeId) =>
      '${_profileBoxPrefix}_${_safe(employeeId)}';

  static String _legacyVaultBoxName(String employeeId) =>
      '${_vaultBoxPrefix}_${_safe(employeeId)}';

  static String privateRecordId(String key, [String? employeeId]) =>
      '${_safe(employeeId ?? TeamService.current?.id ?? 'anonymous')}::$key';

  static String privateKeyFromRecordId(String id) {
    final i = id.indexOf('::');
    return i < 0 ? id : id.substring(i + 2);
  }

  static bool _vaultKey(Object? key) {
    final value = '$key';
    return value == _vaultSaltKey || value.startsWith(_vaultPrefix);
  }

  static Future<void> install() async {
    if (!_registered) {
      _registered = true;
      if (SyncCodec.byName('profile_private') == null) {
        SyncCodec.collections.add(_ProfilePrivateSync());
      }
      if (SyncCodec.byName('vault_private') == null) {
        SyncCodec.collections.add(_VaultPrivateSync());
      }
      TeamService.revision.addListener(_onTeamRevision);
    }

    await _bind(allowLegacy: true);
    _settingsSub ??= Hive.box<dynamic>(_settingsBox).watch().listen(
          (event) => unawaited(_mirrorSetting(event)),
        );
  }

  static bool _bindingMatchesCurrent() {
    final authUserId = SyncAccountScope.currentUserId;
    final employeeId = authUserId == 'anonymous' ? null : TeamService.current?.id;
    return _boundEmployeeId == employeeId && _boundAuthUserId == authUserId;
  }

  static void _onTeamRevision() {
    // A revision can fire while a previous logout/account rebind is still
    // awaiting SyncEngine.reset() or private-box restoration. Never discard a
    // different identity just because `_rebinding` is true. Mark another pass
    // as requested; the single worker below drains requests until both the
    // business employee and the auth-user namespace are current.
    if (_bindingMatchesCurrent()) return;
    _requestRebind();
  }

  static void _requestRebind() {
    _rebindRequestGeneration++;
    unawaited(_ensureRebindWorker());
  }

  /// Serializes account switches and coalesces changes that happen while a
  /// previous switch is still running.
  static Future<void> rebindCurrentAccountAndSync() {
    _rebindRequestGeneration++;
    return _ensureRebindWorker();
  }

  static Future<void> _ensureRebindWorker() {
    if (_rebindFuture case final running?) return running;
    final future = _drainRebindRequests();
    _rebindFuture = future;
    unawaited(future.then<void>(
      (_) {
        if (identical(_rebindFuture, future)) _rebindFuture = null;
      },
      onError: (Object _, StackTrace __) {
        if (identical(_rebindFuture, future)) _rebindFuture = null;
      },
    ));
    return future;
  }

  static Future<void> _drainRebindRequests() async {
    _rebinding = true;
    try {
      while (true) {
        final handledGeneration = _rebindRequestGeneration;
        await _performRebindPass();

        if (handledGeneration == _rebindRequestGeneration &&
            _bindingMatchesCurrent()) {
          break;
        }
      }
    } finally {
      _rebinding = false;
    }
  }

  static Future<void> _performRebindPass() async {
    final targetEmployeeId = TeamService.current?.id;
    final targetAuthUserId = SyncAccountScope.currentUserId;

    SyncAuto.stop(force: true);
    await SyncEngine.reset();

    if (TeamService.current?.id != targetEmployeeId ||
        SyncAccountScope.currentUserId != targetAuthUserId) {
      return;
    }

    await _bind(allowLegacy: false);

    if (TeamService.current?.id != targetEmployeeId ||
        SyncAccountScope.currentUserId != targetAuthUserId ||
        !_bindingMatchesCurrent()) {
      return;
    }

    if (TeamService.current != null && SyncEndpoint.isConnected) {
      await SyncEngine.runOnLaunch();

      if (TeamService.current?.id == targetEmployeeId &&
          SyncAccountScope.currentUserId == targetAuthUserId &&
          _bindingMatchesCurrent() &&
          SyncEndpoint.isConnected) {
        SyncAuto.start();
      }
    }
  }

  static String _marker(String key, String employeeId) =>
      '$key.account.${_safe(employeeId)}';

  static Future<void> _stashMarkers(Box<dynamic> settings, String id) async {
    for (final key in const [_lastRunKey, _seededKey]) {
      final value = settings.get(key);
      if (value != null) await settings.put(_marker(key, id), value);
    }
  }

  static Future<void> _restoreMarkers(
    Box<dynamic> settings,
    String id, {
    required bool allowLegacy,
  }) async {
    for (final key in const [_lastRunKey, _seededKey]) {
      final scoped = settings.get(_marker(key, id));
      if (scoped != null) {
        await settings.put(key, scoped);
      } else if (allowLegacy && settings.get(key) != null) {
        await settings.put(_marker(key, id), settings.get(key));
      } else {
        await settings.delete(key);
      }
    }
  }

  /// One-time migration from the previous employee-scoped private boxes.
  ///
  /// Copy only when the new auth-scoped target is empty. If both exist, the
  /// auth-scoped box is authoritative. In either case clear the legacy box so
  /// private profile/vault values do not remain readable under a namespace
  /// that is weaker than the server's auth-user boundary.
  static Future<void> _migrateLegacyPrivateBox(
    String legacyName,
    Box<dynamic> target,
  ) async {
    if (legacyName == target.name) return;
    final legacy = await _open(legacyName);
    if (legacy.isEmpty) return;

    if (target.isEmpty) {
      final copy = <dynamic, dynamic>{};
      for (final key in legacy.keys) {
        copy[key] = legacy.get(key);
      }
      if (copy.isNotEmpty) await target.putAll(copy);
    }

    await legacy.clear();
  }

  static Future<void> _bind({required bool allowLegacy}) async {
    final current = TeamService.current;
    final id = current?.id;
    final authUserId = SyncAccountScope.currentUserId;
    final settings = Hive.box<dynamic>(_settingsBox);
    final previousOwner = settings.get(_profileOwnerKey);

    if (id == null || id.isEmpty || authUserId == 'anonymous') {
      final previous = _boundEmployeeId ??
          (previousOwner is String && previousOwner.isNotEmpty
              ? previousOwner
              : null);
      if (previous != null) await _stashMarkers(settings, previous);
      await settings.delete(_lastRunKey);
      await settings.delete(_seededKey);
      _boundEmployeeId = null;
      _boundAuthUserId = authUserId;
      SecretVault.lock();
      return;
    }
    if (_boundEmployeeId == id && _boundAuthUserId == authUserId) return;

    if (_boundEmployeeId case final previous? when previous != id) {
      await _stashMarkers(settings, previous);
    }
    final migrateLegacy = allowLegacy &&
        _boundEmployeeId == null &&
        (previousOwner == null || '$previousOwner' == id);
    await _restoreMarkers(settings, id, allowLegacy: migrateLegacy);

    final profile = await _open(profileBoxName(authUserId));
    final vault = await _open(vaultBoxName(authUserId));
    await _migrateLegacyPrivateBox(_legacyProfileBoxName(id), profile);
    await _migrateLegacyPrivateBox(_legacyVaultBoxName(id), vault);

    // Account could switch while legacy Hive data was being copied. Do not
    // project the stale target into global settings; the drain loop will reset
    // and bind the new identity immediately.
    if (TeamService.current?.id != id ||
        SyncAccountScope.currentUserId != authUserId) {
      return;
    }

    if (migrateLegacy && profile.isEmpty) {
      await _seedProfile(settings, profile);
    } else {
      await _restoreProfile(settings, profile, current!);
    }
    if (migrateLegacy && vault.isEmpty) {
      await _seedVault(settings, vault);
    } else {
      await _restoreVault(settings, vault);
    }

    if (TeamService.current?.id != id ||
        SyncAccountScope.currentUserId != authUserId) {
      return;
    }

    await settings.put(_profileOwnerKey, id);
    _boundEmployeeId = id;
    _boundAuthUserId = authUserId;
    await _projectAvatarToEmployee();
  }

  static Future<Box<dynamic>> _open(String name) => Hive.isBoxOpen(name)
      ? Future.value(Hive.box<dynamic>(name))
      : Hive.openBox<dynamic>(name);

  static Future<void> _seedProfile(
    Box<dynamic> settings,
    Box<dynamic> profile,
  ) async {
    for (final key in _profileKeys) {
      if (!settings.containsKey(key)) continue;
      var value = settings.get(key);
      if (key == 'avatar_custom') value = await _normalizeAvatar(value);
      if (value != null) await profile.put(key, value);
    }
  }

  static Future<void> _restoreProfile(
    Box<dynamic> settings,
    Box<dynamic> profile,
    EmployeeModel current,
  ) async {
    for (final key in _profileKeys) {
      await settings.delete(key);
    }
    if (profile.isEmpty) {
      await profile.put('profile_name', current.fullName);
      await profile.put('profile_email', current.email);
      await profile.put('avatar_index', current.avatarIndex);
      final photo = await _normalizeAvatar(current.photo);
      if (photo != null) await profile.put('avatar_custom', photo);
    }
    for (final rawKey in profile.keys) {
      final key = '$rawKey';
      if (_profileKeys.contains(key)) {
        await settings.put(key, profile.get(rawKey));
      }
    }
    ShieldService.revision.value++;
  }

  static Future<void> _seedVault(
    Box<dynamic> settings,
    Box<dynamic> vault,
  ) async {
    for (final rawKey in settings.keys.toList()) {
      if (_vaultKey(rawKey)) await vault.put('$rawKey', settings.get(rawKey));
    }
  }

  static Future<void> _restoreVault(
    Box<dynamic> settings,
    Box<dynamic> vault,
  ) async {
    for (final rawKey in settings.keys.toList()) {
      if (_vaultKey(rawKey)) await settings.delete(rawKey);
    }
    SecretVault.lock();
    for (final rawKey in vault.keys) {
      if (_vaultKey(rawKey)) await settings.put('$rawKey', vault.get(rawKey));
    }
    SecretVault.revision.value++;
  }

  static Future<void> _mirrorSetting(BoxEvent event) async {
    if (_rebinding || TeamService.current == null) return;
    final key = '${event.key}';
    if (key == _profileOwnerKey) return;

    if (_profileKeys.contains(key)) {
      final box = await _open(profileBoxName());
      if (event.deleted) {
        await box.delete(key);
      } else {
        var value = event.value;
        if (key == 'avatar_custom') {
          value = await _normalizeAvatar(value);
          if (value == null) {
            await box.delete(key);
            await Hive.box<dynamic>(_settingsBox).delete(key);
            _scheduleAvatarProjection();
            return;
          }
          final settings = Hive.box<dynamic>(_settingsBox);
          if (!_same(settings.get(key), value)) await settings.put(key, value);
        }
        if (!_same(box.get(key), value)) await box.put(key, value);
      }
      if (key == 'avatar_index' || key == 'avatar_custom') {
        _scheduleAvatarProjection();
      }
      return;
    }

    if (_vaultKey(key)) {
      final box = await _open(vaultBoxName());
      if (event.deleted) {
        await box.delete(key);
      } else if (!_same(box.get(key), event.value)) {
        await box.put(key, event.value);
      }
    }
  }

  static void _scheduleAvatarProjection() {
    _avatarProjection?.cancel();
    _avatarProjection = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_projectAvatarToEmployee()),
    );
  }

  static Future<void> _projectAvatarToEmployee() async {
    final current = TeamService.current;
    if (current == null) return;
    final settings = Hive.box<dynamic>(_settingsBox);
    final rawIndex = settings.get('avatar_index');
    final index = rawIndex is num ? rawIndex.toInt() : current.avatarIndex;
    final photo = await _normalizeAvatar(settings.get('avatar_custom'));
    if (current.avatarIndex == index && _same(current.photo, photo)) return;
    await TeamService.save(current.copyWith(
      avatarIndex: index,
      photo: photo,
      clearPhoto: photo == null,
    ));
  }

  static Future<Uint8List?> _normalizeAvatar(Object? raw) async {
    final bytes = raw is Uint8List
        ? raw
        : raw is List<int>
            ? Uint8List.fromList(raw)
            : null;
    if (bytes == null || bytes.isEmpty) return null;
    if (bytes.length <= TeamService.maxPhotoBytes) return bytes;
    for (final width in const [192, 144, 112, 96, 72, 56]) {
      try {
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
        final frame = await codec.getNextFrame();
        final data =
            await frame.image.toByteData(format: ui.ImageByteFormat.png);
        frame.image.dispose();
        codec.dispose();
        if (data == null) continue;
        final scaled = data.buffer.asUint8List();
        if (scaled.length <= TeamService.maxPhotoBytes) return scaled;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static bool _same(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is List<int> && b is Uint8List) a = Uint8List.fromList(a);
    if (a is Uint8List && b is List<int>) b = Uint8List.fromList(b);
    if (a is Uint8List && b is Uint8List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    return a == b;
  }
}

class _KeyedValue {
  final String key;
  final dynamic value;
  const _KeyedValue(this.key, this.value);
}

abstract class _KeyedStateSync extends SyncCollection<dynamic> {
  Set<String> get keys;

  @override
  String idOf(dynamic value) => value is _KeyedValue ? value.key : '';

  @override
  Map<String, dynamic> local() {
    final b = box();
    if (b == null) return const {};
    return {
      for (final key in keys)
        if (b.containsKey(key)) key: _KeyedValue(key, b.get(key)),
    };
  }

  @override
  Map<String, dynamic> encode(dynamic value) => value is _KeyedValue
      ? {'key': value.key, 'value': _wire(value.value)}
      : const {};

  @override
  dynamic decode(Map<String, dynamic> fields) {
    final key = fields['key'];
    if (key is! String || !keys.contains(key)) return null;
    return _KeyedValue(key, _unwire(fields['value']));
  }

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final incoming = decode(fields);
    final b = box();
    if (incoming is! _KeyedValue || b == null) return false;
    await b.put(incoming.key, incoming.value);
    return true;
  }
}

class _ProfilePrivateSync extends _KeyedStateSync {
  @override
  String get name => 'profile_private';
  @override
  String get boxName => SyncFeatureExtensions.profileBoxName();
  @override
  Set<String> get keys => SyncFeatureExtensions._profileKeys;

  @override
  bool watchesBoxKey(Object? key) => keys.contains('$key');

  @override
  String syncIdForBoxKey(Object? key) =>
      SyncFeatureExtensions.privateRecordId('$key');

  @override
  String idOf(dynamic value) => value is _KeyedValue
      ? SyncFeatureExtensions.privateRecordId(value.key)
      : '';

  @override
  Map<String, dynamic> local() {
    final b = box();
    if (b == null) return const {};
    return {
      for (final key in keys)
        if (b.containsKey(key))
          SyncFeatureExtensions.privateRecordId(key):
              _KeyedValue(key, b.get(key)),
    };
  }

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final incoming = decode(fields);
    final b = box();
    if (incoming is! _KeyedValue || b == null) return false;
    await b.put(incoming.key, incoming.value);
    await Hive.box<dynamic>(SyncFeatureExtensions._settingsBox)
        .put(incoming.key, incoming.value);
    if (incoming.key == 'avatar_index' || incoming.key == 'avatar_custom') {
      SyncFeatureExtensions._scheduleAvatarProjection();
    }
    ShieldService.revision.value++;
    return true;
  }

  @override
  Future<void> removeById(String id) async {
    final key = SyncFeatureExtensions.privateKeyFromRecordId(id);
    await box()?.delete(key);
    await Hive.box<dynamic>(SyncFeatureExtensions._settingsBox).delete(key);
    if (key == 'avatar_index' || key == 'avatar_custom') {
      SyncFeatureExtensions._scheduleAvatarProjection();
    }
    ShieldService.revision.value++;
  }
}

class _VaultPrivateSync extends SyncCollection<dynamic> {
  @override
  String get name => 'vault_private';
  @override
  String get boxName => SyncFeatureExtensions.vaultBoxName();
  @override
  bool watchesBoxKey(Object? key) => SyncFeatureExtensions._vaultKey(key);
  @override
  String syncIdForBoxKey(Object? key) =>
      SyncFeatureExtensions.privateRecordId('$key');
  @override
  String idOf(dynamic value) => value is _KeyedValue
      ? SyncFeatureExtensions.privateRecordId(value.key)
      : '';

  @override
  Map<String, dynamic> local() {
    final b = box();
    if (b == null) return const {};
    final out = <String, dynamic>{};
    for (final rawKey in b.keys) {
      final key = '$rawKey';
      if (!SyncFeatureExtensions._vaultKey(key)) continue;
      out[SyncFeatureExtensions.privateRecordId(key)] =
          _KeyedValue(key, b.get(rawKey));
    }
    return out;
  }

  @override
  Map<String, dynamic> encode(dynamic value) => value is _KeyedValue
      ? {'key': value.key, 'value': _wire(value.value)}
      : const {};

  @override
  dynamic decode(Map<String, dynamic> fields) {
    final key = fields['key'];
    if (key is! String || !SyncFeatureExtensions._vaultKey(key)) return null;
    return _KeyedValue(key, _unwire(fields['value']));
  }

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final incoming = decode(fields);
    final b = box();
    if (incoming is! _KeyedValue || b == null) return false;
    await b.put(incoming.key, incoming.value);
    await Hive.box<dynamic>(SyncFeatureExtensions._settingsBox)
        .put(incoming.key, incoming.value);
    if (incoming.key == SyncFeatureExtensions._vaultSaltKey) SecretVault.lock();
    SecretVault.revision.value++;
    return true;
  }

  @override
  Future<void> removeById(String id) async {
    final key = SyncFeatureExtensions.privateKeyFromRecordId(id);
    await box()?.delete(key);
    await Hive.box<dynamic>(SyncFeatureExtensions._settingsBox).delete(key);
    if (key == SyncFeatureExtensions._vaultSaltKey) SecretVault.lock();
    SecretVault.revision.value++;
  }
}

dynamic _wire(dynamic value) {
  if (value is Uint8List || value is List<int>) {
    return {'__wesios_bytes_v1': base64Encode(value as List<int>)};
  }
  return value;
}

dynamic _unwire(dynamic value) {
  if (value is Map &&
      value.length == 1 &&
      value['__wesios_bytes_v1'] is String) {
    try {
      return Uint8List.fromList(
          base64Decode(value['__wesios_bytes_v1'] as String));
    } catch (_) {
      return null;
    }
  }
  return value;
}