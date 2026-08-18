import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:hive/hive.dart';

import '../../features/profile/services/profile_service.dart';
import '../../features/team/services/team_service.dart';
import '../security/secret_vault.dart';
import '../security/shield_service.dart';
import 'sync_account_scope.dart';
import 'sync_auto.dart';
import 'sync_codec.dart';
import 'sync_endpoint.dart';
import 'sync_engine.dart';

/// Synchronization for private settings that are not represented by normal
/// business models.
///
/// User profile is intentionally NOT here anymore. It has one canonical
/// `profile/me` record through [ProfileService]/ProfileSync. This extension
/// owns only portable Shield configuration and encrypted Secret Vault rows.
class SyncFeatureExtensions {
  SyncFeatureExtensions._();

  static const _settingsBox = 'wesios_settings';

  /// Legacy marker used only to decide whether old unscoped Shield settings
  /// may be migrated on the first launch after upgrade.
  static const _legacySettingsOwnerKey = 'sync_profile_settings_owner_v1';

  /// Keep the old base name so the already-created auth-scoped box is reused,
  /// but its contents are sanitized to Shield-only during bind.
  static const _shieldBoxPrefix = 'wesios_profile_sync_v1';
  static const _vaultBoxPrefix = 'wesios_vault_sync_v1';
  static const _vaultSaltKey = 'vault_kdf_salt';
  static const _vaultPrefix = 'vault_secret_';

  static const Set<String> _legacyProfileKeys = {
    'profile_name',
    'profile_email',
    'profile_gender',
    'profile_country',
    'profile_birth',
    'avatar_index',
    'avatar_custom',
  };

  /// Only portable Shield configuration belongs to shield_private.
  /// Biometric enrollment, failed attempts and security log remain local.
  static const Set<String> _shieldKeys = {
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

  static String shieldBoxName([String? authUserId]) =>
      SyncAccountScope.forUser(
        _shieldBoxPrefix,
        authUserId ?? SyncAccountScope.currentUserId,
      );

  static String vaultBoxName([String? authUserId]) =>
      SyncAccountScope.forUser(
        _vaultBoxPrefix,
        authUserId ?? SyncAccountScope.currentUserId,
      );

  static String _legacyPrivateBoxName(String employeeId) =>
      '${_shieldBoxPrefix}_${_safe(employeeId)}';

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
      if (SyncCodec.byName('shield_private') == null) {
        SyncCodec.collections.add(_ShieldPrivateSync());
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
    if (_bindingMatchesCurrent()) return;
    _requestRebind();
  }

  static void _requestRebind() {
    _rebindRequestGeneration++;
    unawaited(_ensureRebindWorker());
  }

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

  /// Copies old employee-scoped private storage into the current auth-user
  /// namespace exactly once. Auth-scoped target wins if it already has data.
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

  /// Before the old overloaded private box is reduced to Shield-only, rescue
  /// profile fields into the canonical ProfileService record when that record
  /// is still empty. This handles devices that had local profile_private data
  /// but never successfully uploaded the newer `profile/me` record.
  static Future<void> _migrateEmbeddedLegacyProfile(Box<dynamic> oldPrivate) async {
    final hasLegacy = _legacyProfileKeys.any(oldPrivate.containsKey);
    if (!hasLegacy) return;

    final canonical = await ProfileService.read();
    if (canonical.isNotEmpty) return;

    String text(String key) => '${oldPrivate.get(key) ?? ''}'.trim();
    final birthText = text('profile_birth');
    final rawAvatar = oldPrivate.get('avatar_index');
    final avatarIndex = rawAvatar is num ? rawAvatar.toInt() : int.tryParse('$rawAvatar') ?? 0;
    final rawPhoto = oldPrivate.get('avatar_custom');
    Uint8List? photo;
    if (rawPhoto is Uint8List) {
      photo = rawPhoto;
    } else if (rawPhoto is List<int>) {
      photo = Uint8List.fromList(rawPhoto);
    }
    if (photo != null && photo.length > ProfileService.maxPhotoBytes) {
      photo = null;
    }

    final name = text('profile_name');
    final email = text('profile_email');
    final gender = text('profile_gender');
    final country = text('profile_country');
    final birth = DateTime.tryParse(birthText);
    final meaningful = name.isNotEmpty ||
        email.isNotEmpty ||
        gender.isNotEmpty ||
        country.isNotEmpty ||
        birth != null ||
        avatarIndex != 0 ||
        photo != null;
    if (!meaningful) return;

    await ProfileService.write(
      name: name,
      email: email,
      gender: gender,
      country: country,
      birth: birth,
      avatarIndex: avatarIndex,
      photo: photo,
    );
  }

  static Future<void> _keepShieldOnly(Box<dynamic> shield) async {
    for (final rawKey in shield.keys.toList()) {
      final key = '$rawKey';
      if (!_shieldKeys.contains(key)) await shield.delete(rawKey);
    }
  }

  static Future<void> _bind({required bool allowLegacy}) async {
    final id = TeamService.current?.id;
    final authUserId = SyncAccountScope.currentUserId;
    final settings = Hive.box<dynamic>(_settingsBox);
    final previousOwner = settings.get(_legacySettingsOwnerKey);

    if (id == null || id.isEmpty || authUserId == 'anonymous') {
      _boundEmployeeId = null;
      _boundAuthUserId = authUserId;
      SecretVault.lock();
      return;
    }
    if (_boundEmployeeId == id && _boundAuthUserId == authUserId) return;

    final migrateLegacySettings = allowLegacy &&
        _boundEmployeeId == null &&
        (previousOwner == null || '$previousOwner' == id);

    final shield = await _open(shieldBoxName(authUserId));
    final vault = await _open(vaultBoxName(authUserId));
    await _migrateLegacyPrivateBox(_legacyPrivateBoxName(id), shield);
    await _migrateLegacyPrivateBox(_legacyVaultBoxName(id), vault);
    await _migrateEmbeddedLegacyProfile(shield);
    await _keepShieldOnly(shield);

    if (TeamService.current?.id != id ||
        SyncAccountScope.currentUserId != authUserId) {
      return;
    }

    if (migrateLegacySettings && shield.isEmpty) {
      await _seedShield(settings, shield);
    } else {
      await _restoreShield(settings, shield);
    }
    if (migrateLegacySettings && vault.isEmpty) {
      await _seedVault(settings, vault);
    } else {
      await _restoreVault(settings, vault);
    }

    if (TeamService.current?.id != id ||
        SyncAccountScope.currentUserId != authUserId) {
      return;
    }

    await settings.put(_legacySettingsOwnerKey, id);
    _boundEmployeeId = id;
    _boundAuthUserId = authUserId;
    await _projectAvatarToEmployee();
  }

  static Future<Box<dynamic>> _open(String name) => Hive.isBoxOpen(name)
      ? Future.value(Hive.box<dynamic>(name))
      : Hive.openBox<dynamic>(name);

  static Future<void> _seedShield(
    Box<dynamic> settings,
    Box<dynamic> shield,
  ) async {
    for (final key in _shieldKeys) {
      if (!settings.containsKey(key)) continue;
      final value = settings.get(key);
      if (value != null) await shield.put(key, value);
    }
  }

  static Future<void> _restoreShield(
    Box<dynamic> settings,
    Box<dynamic> shield,
  ) async {
    for (final key in _shieldKeys) {
      await settings.delete(key);
    }
    for (final rawKey in shield.keys) {
      final key = '$rawKey';
      if (_shieldKeys.contains(key)) {
        await settings.put(key, shield.get(rawKey));
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
    if (key == _legacySettingsOwnerKey) return;

    if (_shieldKeys.contains(key)) {
      final box = await _open(shieldBoxName());
      if (event.deleted) {
        await box.delete(key);
      } else if (!_same(box.get(key), event.value)) {
        await box.put(key, event.value);
      }
      return;
    }

    // Avatar still projects to the employee/contact card, but it is NOT
    // mirrored into shield_private. ProfileService is the only profile sync
    // authority and already owns profile settings projection.
    if (key == 'avatar_index' || key == 'avatar_custom') {
      _scheduleAvatarProjection();
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

class _ShieldPrivateSync extends _KeyedStateSync {
  @override
  String get name => 'shield_private';

  @override
  String get boxName => SyncFeatureExtensions.shieldBoxName();

  @override
  Set<String> get keys => SyncFeatureExtensions._shieldKeys;

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
    ShieldService.revision.value++;
    return true;
  }

  @override
  Future<void> removeById(String id) async {
    final key = SyncFeatureExtensions.privateKeyFromRecordId(id);
    await box()?.delete(key);
    await Hive.box<dynamic>(SyncFeatureExtensions._settingsBox).delete(key);
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