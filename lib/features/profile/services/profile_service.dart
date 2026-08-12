import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Профиль человека: имя, почта, дата рождения, страна и аватарка.
///
/// Раньше всё это лежало прямо в `wesios_settings` отдельными ключами, а тот
/// бокс не синхронизируется — и правильно, что не синхронизируется: там же
/// адрес сервера, пропуск сессии и смещение часов, которым на чужом
/// устройстве делать нечего. В результате человек, заполнив профиль на
/// компьютере, на телефоне видел пустые поля и стандартную аватарку.
///
/// Профиль вынесен в собственный бокс одной записью — так он попадает в общий
/// обмен, а секреты остаются на месте.
///
/// Запись одна, ключ постоянный: у человека один профиль, и заводить под него
/// идентификатор незачем — данные и так лежат в личном пространстве владельца.
class ProfileService {
  static const String boxName = 'wesios_profile';

  /// Ключ единственной записи. Постоянный: если бы он зависел от устройства,
  /// на сервере оказалось бы столько профилей, сколько у человека телефонов.
  static const String recordKey = 'me';

  static const String settingsBoxName = 'wesios_settings';
  static const String _migratedKey = 'profile_moved_to_record_v1';

  /// Предел на аватарку. Записи уходят на сервер целиком, и лимит там — два
  /// мегабайта на запись; картинка в base64 растёт ещё на треть. Полмегабайта
  /// с запасом хватает на любое разумное фото профиля.
  static const int maxPhotoBytes = 512 * 1024;

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Box<String>? _box;

  static Future<Box<String>> _open() async {
    final cached = _box;
    if (cached != null && cached.isOpen) {
      await _migrateIfNeeded();
      return cached;
    }
    final box = Hive.isBoxOpen(boxName)
        ? Hive.box<String>(boxName)
        : await Hive.openBox<String>(boxName);
    _box = box;
    await _migrateIfNeeded();
    return box;
  }

  static Box<dynamic>? get _settings => Hive.isBoxOpen(settingsBoxName)
      ? Hive.box<dynamic>(settingsBoxName)
      : null;

  static bool _migrating = false;

  /// Перенос профиля из настроек.
  ///
  /// Старые ключи не удаляются: на них смотрит аватарка в шапке и ещё
  /// несколько экранов, и выдёргивать их из-под работающего интерфейса ради
  /// переезда незачем. Отметка о переносе не даёт затереть более свежий
  /// профиль, приехавший с другого устройства.
  static Future<void> _migrateIfNeeded() async {
    if (_migrating) return;
    final settings = _settings;
    if (settings == null || settings.get(_migratedKey) == true) return;
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
      await settings.put('profile_name', data['name']);
      await settings.put('profile_email', data['email']);
      await settings.put('profile_gender', data['gender']);
      await settings.put('profile_country', data['country']);
      if (birth != null) {
        await settings.put('profile_birth', birth.toIso8601String());
      } else {
        await settings.delete('profile_birth');
      }
    }
    revision.value++;
  }

  /// Разложить приехавший профиль по ключам настроек.
  ///
  /// Вызывается синхронизацией после применения чужой записи: интерфейс
  /// читает настройки, и без этого шага профиль доехал бы до устройства, но
  /// на экране остался бы прежним до перезаполнения вручную.
  static Future<void> spreadToSettings() async {
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
    _settings?.delete(_migratedKey);
    revision.value++;
  }
}
