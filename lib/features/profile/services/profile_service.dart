import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../../core/sync/sync_account_scope.dart';

/// Профиль человека: имя, почта, дата рождения, страна и аватарка.
///
/// Профиль синхронизируется в private server scope, поэтому и локальный Hive
/// обязан быть private per auth-user. Общий `wesios_profile` позволял профилю
/// предыдущего сотрудника остаться на общем устройстве и стать локальной
/// записью следующего аккаунта.
class ProfileService {
  static const String baseBoxName = 'wesios_profile';
  static String get boxName => SyncAccountScope.boxName(baseBoxName);

  /// Ключ единственной записи. Постоянный внутри личного account namespace.
  static const String recordKey = 'me';

  static const String settingsBoxName = 'wesios_settings';
  static const String _migratedKey = 'profile_moved_to_record_v1';
  static const String _projectionOwnerKey = 'profile_projection_auth_user_v2';
  static const List<String> _projectionKeys = <String>[
    'profile_name',
    'profile_email',
    'profile_gender',
    'profile_country',
    'profile_birth',
    'avatar_index',
    'avatar_custom',
  ];

  /// Предел на аватарку. Записи уходят на сервер целиком, и лимит там — два
  /// мегабайта на запись; картинка в base64 растёт ещё на треть. Полмегабайта
  /// с запасом хватает на любое разумное фото профиля.
  static const int maxPhotoBytes = 512 * 1024;

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Box<String>? _box;
  static String? _openedBoxName;

  static Future<Box<String>> _open() async {
    await _ensureProjectionOwner();

    final currentName = boxName;
    final cached = _box;
    if (cached != null && cached.isOpen && _openedBoxName == currentName) {
      await _migrateIfNeeded();
      return cached;
    }

    // ProfileService — static singleton. После account switch старый Box
    // может оставаться живым в памяти, даже если новый server-session уже
    // активен. Закрываем его до открытия namespace нового auth-user.
    if (cached != null && cached.isOpen && _openedBoxName != currentName) {
      await cached.close();
    }

    final box = Hive.isBoxOpen(currentName)
        ? Hive.box<String>(currentName)
        : await Hive.openBox<String>(currentName);
    _box = box;
    _openedBoxName = currentName;
    await _migrateIfNeeded();
    return box;
  }

  static Box<dynamic>? get _settings => Hive.isBoxOpen(settingsBoxName)
      ? Hive.box<dynamic>(settingsBoxName)
      : null;

  /// `profile_*` в wesios_settings — только UI-проекция, не источник общей
  /// истины. Она принадлежит конкретному PocketBase auth-user.
  ///
  /// Важный migration edge: старые версии вообще не имели owner-marker. Пока
  /// подтверждённой сессии нет, такие legacy-ключи НЕ очищаем и НЕ переносим в
  /// anonymous box — оставляем их нетронутыми до входа. Первый подтверждённый
  /// auth-user может забрать эту unowned legacy-проекцию один раз. После записи
  /// marker любое переключение на другой auth-user идёт fail-closed и очищает
  /// UI-проекцию, поэтому профиль предыдущего аккаунта не пересекает границу.
  static Future<void> _ensureProjectionOwner() async {
    final settings = _settings;
    if (settings == null) return;
    final currentOwner = SyncAccountScope.currentUserId;
    final previousOwner = settings.get(_projectionOwnerKey);

    if (previousOwner == currentOwner) return;

    if (previousOwner == null) {
      // До подтверждённого входа нельзя ни уничтожать legacy-профиль, ни
      // приписывать его anonymous namespace. Оставляем миграцию отложенной.
      if (currentOwner == 'anonymous') return;
      await settings.put(_projectionOwnerKey, currentOwner);
      return;
    }

    // Owner уже был зафиксирован и изменился: это настоящий account switch.
    for (final key in _projectionKeys) {
      await settings.delete(key);
    }
    await settings.put(_projectionOwnerKey, currentOwner);
    await settings.delete(_migratedKey);
  }

  static bool _migrating = false;

  /// Перенос старых ключей текущего аккаунта в его scoped record.
  static Future<void> _migrateIfNeeded() async {
    if (_migrating) return;
    final settings = _settings;
    if (settings == null || settings.get(_migratedKey) == true) return;

    // Не забираем legacy profile_* в anonymous namespace. После успешного
    // входа [_ensureProjectionOwner] закрепит их за конкретным auth-user и
    // следующий read/write выполнит миграцию в его scoped box.
    final currentOwner = SyncAccountScope.currentUserId;
    if (currentOwner == 'anonymous' &&
        settings.get(_projectionOwnerKey) == null) {
      return;
    }

    _migrating = true;
    try {
      final box = _box;
      if (box == null) return;
      if (!box.containsKey(recordKey)) {
        final photo = _photoFrom(settings.get('avatar_custom'));
        final data = <String, dynamic>{
          'name': '${settings.get('profile_name') ?? ''}',
          'email': '${settings.get('profile_email') ?? ''}',
          'gender': '${settings.get('profile_gender') ?? ''}',
          'country': '${settings.get('profile_country') ?? ''}',
          'birth': '${settings.get('profile_birth') ?? ''}',
          'avatarIndex': settings.get('avatar_index') is int
              ? settings.get('avatar_index') as int
              : 0,
          if (photo != null) 'photo': base64Encode(photo),
        };
        // Пустой профиль на сервер не отправляем: он выглядел бы как
        // осмысленная правка и затёр бы заполненный профиль с другого
        // устройства.
        if (data.values.any((v) => v is String && v.isNotEmpty) ||
            data['avatarIndex'] != 0 ||
            data.containsKey('photo')) {
          await box.put(recordKey, jsonEncode(data));
        }
      }
      await settings.put(_migratedKey, true);
    } catch (_) {
      // Профиль — не то, ради чего стоит ронять запуск.
    } finally {
      _migrating = false;
    }
  }

  static Uint8List? _photoFrom(Object? raw) {
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    return null;
  }

  /// Текущий профиль. Пустая карта — профиль ещё не заполняли.
  static Future<Map<String, dynamic>> read() async {
    final box = await _open();
    final raw = box.get(recordKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Записать профиль целиком и продублировать в настройки — на них пока
  /// смотрит интерфейс.
  static Future<void> write({
    required String name,
    required String email,
    required String gender,
    required String country,
    DateTime? birth,
    int? avatarIndex,
    Uint8List? photo,
    bool clearPhoto = false,
  }) async {
    final box = await _open();
    final current = await read();

    final data = <String, dynamic>{
      'name': name.trim(),
      'email': email.trim(),
      'gender': gender,
      'country': country,
      'birth': birth?.toIso8601String() ?? '',
      'avatarIndex': avatarIndex ?? (current['avatarIndex'] as int? ?? 0),
    };
    if (!clearPhoto) {
      if (photo != null && photo.length <= maxPhotoBytes) {
        data['photo'] = base64Encode(photo);
      } else if (photo == null && current['photo'] is String) {
        data['photo'] = current['photo'];
      }
    }
    await box.put(recordKey, jsonEncode(data));

    final settings = _settings;
    if (settings != null) {
      final owner = SyncAccountScope.currentUserId;
      if (owner != 'anonymous') {
        await settings.put(_projectionOwnerKey, owner);
      }
      await settings.put('profile_name', data['name']);
      await settings.put('profile_email', data['email']);
      await settings.put('profile_gender', data['gender']);
      await settings.put('profile_country', data['country']);
      if (birth != null) {
        await settings.put('profile_birth', birth.toIso8601String());
      } else {
        await settings.delete('profile_birth');
      }
      final index = data['avatarIndex'];
      if (index is int) await settings.put('avatar_index', index);
      if (data['photo'] is String) {
        try {
          await settings.put(
            'avatar_custom',
            base64Decode(data['photo'] as String),
          );
        } catch (_) {}
      } else if (clearPhoto) {
        await settings.delete('avatar_custom');
      }
    }
    revision.value++;
  }

  /// Разложить приехавший профиль по ключам настроек.
  static Future<void> spreadToSettings() async {
    await _ensureProjectionOwner();
    final settings = _settings;
    if (settings == null) return;
    final data = await read();
    if (data.isEmpty) return;

    Future<void> copy(String from, String to) async {
      final value = data[from];
      if (value is! String) return;
      if (value.isEmpty) {
        await settings.delete(to);
      } else {
        await settings.put(to, value);
      }
    }

    final owner = SyncAccountScope.currentUserId;
    if (owner != 'anonymous') {
      await settings.put(_projectionOwnerKey, owner);
    }
    await copy('name', 'profile_name');
    await copy('email', 'profile_email');
    await copy('gender', 'profile_gender');
    await copy('country', 'profile_country');
    await copy('birth', 'profile_birth');

    final index = data['avatarIndex'];
    if (index is int) await settings.put('avatar_index', index);

    final photo = data['photo'];
    if (photo is String && photo.isNotEmpty) {
      try {
        await settings.put('avatar_custom', base64Decode(photo));
      } catch (_) {
        // Испорченная картинка — не повод терять остальной профиль.
      }
    } else {
      await settings.delete('avatar_custom');
    }
    revision.value++;
  }

  static Future<void> clearForTest() async {
    await (await _open()).clear();
    final settings = _settings;
    await settings?.delete(_migratedKey);
    await settings?.delete(_projectionOwnerKey);
    revision.value++;
  }
}