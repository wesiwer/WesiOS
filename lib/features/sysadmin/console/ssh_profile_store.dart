import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

enum SshAuthType { password, privateKey }

class SshProfile {
  final String targetId;
  final String username;
  final int port;
  final SshAuthType authType;
  final String? hostKeyFingerprint;

  const SshProfile({
    required this.targetId,
    required this.username,
    this.port = 22,
    this.authType = SshAuthType.password,
    this.hostKeyFingerprint,
  });

  SshProfile copyWith({
    String? username,
    int? port,
    SshAuthType? authType,
    Object? hostKeyFingerprint = _unset,
  }) =>
      SshProfile(
        targetId: targetId,
        username: username ?? this.username,
        port: port ?? this.port,
        authType: authType ?? this.authType,
        hostKeyFingerprint: identical(hostKeyFingerprint, _unset)
            ? this.hostKeyFingerprint
            : hostKeyFingerprint as String?,
      );

  static const _unset = Object();

  Map<String, dynamic> toJson() => {
        'targetId': targetId,
        'username': username,
        'port': port,
        'authType': authType.name,
        'hostKeyFingerprint': hostKeyFingerprint,
      };

  static SshProfile? tryParse(Map<String, dynamic> json) {
    final targetId = json['targetId'];
    final username = json['username'];
    if (targetId is! String || username is! String || username.trim().isEmpty) {
      return null;
    }
    return SshProfile(
      targetId: targetId,
      username: username.trim(),
      port: json['port'] is num ? (json['port'] as num).toInt() : 22,
      authType: SshAuthType.values.firstWhere(
        (value) => value.name == json['authType'],
        orElse: () => SshAuthType.password,
      ),
      hostKeyFingerprint: json['hostKeyFingerprint'] is String
          ? json['hostKeyFingerprint'] as String
          : null,
    );
  }
}

class SshProfileStore {
  SshProfileStore._();

  static const _boxName = 'wesios_settings';
  static const _profilesKey = 'sysadmin_ssh_profiles_v1';
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  static String _secretKey(String targetId, String suffix) =>
      'wesios_ssh_${targetId}_$suffix';

  static Map<String, SshProfile> _loadAll() {
    try {
      final raw = Hive.box<dynamic>(_boxName).get(_profilesKey);
      if (raw is! String || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, SshProfile>{};
      for (final entry in decoded.entries) {
        if (entry.value is! Map) continue;
        final profile = SshProfile.tryParse(
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (profile != null) result[profile.targetId] = profile;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  static SshProfile? profileFor(String targetId) => _loadAll()[targetId];

  static Future<void> saveProfile(SshProfile profile) async {
    final all = _loadAll();
    all[profile.targetId] = profile;
    final encoded = <String, dynamic>{
      for (final entry in all.entries) entry.key: entry.value.toJson(),
    };
    await Hive.box<dynamic>(_boxName).put(_profilesKey, jsonEncode(encoded));
  }

  static Future<void> remove(String targetId) async {
    final all = _loadAll()..remove(targetId);
    final encoded = <String, dynamic>{
      for (final entry in all.entries) entry.key: entry.value.toJson(),
    };
    await Hive.box<dynamic>(_boxName).put(_profilesKey, jsonEncode(encoded));
    await Future.wait([
      _secure.delete(key: _secretKey(targetId, 'password')),
      _secure.delete(key: _secretKey(targetId, 'private_key')),
      _secure.delete(key: _secretKey(targetId, 'passphrase')),
    ]);
  }

  static Future<void> savePassword(String targetId, String password) =>
      _secure.write(key: _secretKey(targetId, 'password'), value: password);

  static Future<String?> readPassword(String targetId) =>
      _secure.read(key: _secretKey(targetId, 'password'));

  static Future<void> savePrivateKey(
    String targetId,
    String privateKey, {
    String? passphrase,
  }) async {
    await _secure.write(
      key: _secretKey(targetId, 'private_key'),
      value: privateKey,
    );
    if (passphrase == null || passphrase.isEmpty) {
      await _secure.delete(key: _secretKey(targetId, 'passphrase'));
    } else {
      await _secure.write(
        key: _secretKey(targetId, 'passphrase'),
        value: passphrase,
      );
    }
  }

  static Future<String?> readPrivateKey(String targetId) =>
      _secure.read(key: _secretKey(targetId, 'private_key'));

  static Future<String?> readPassphrase(String targetId) =>
      _secure.read(key: _secretKey(targetId, 'passphrase'));

  static Future<bool> hasSecret(SshProfile profile) async {
    return switch (profile.authType) {
      SshAuthType.password =>
        ((await readPassword(profile.targetId)) ?? '').isNotEmpty,
      SshAuthType.privateKey =>
        ((await readPrivateKey(profile.targetId)) ?? '').isNotEmpty,
    };
  }
}
