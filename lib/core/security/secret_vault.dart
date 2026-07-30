import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pointycastle/export.dart';

import 'shield_service.dart';

/// Почему ключ недоступен.
enum VaultLockReason {
  /// Пароль Shield не задан — выводить ключ не из чего.
  noPassword,

  /// Пароль задан, но в этой сессии его ещё не вводили.
  locked,
}

/// Локальное хранилище секретов, закрытое паролем Wesi Shield.
///
/// Хранит не сами секреты, а их шифротекст. Ключ шифрования **нигде не
/// лежит**: он выводится из пароля Shield в момент разблокировки и живёт
/// только в памяти процесса. Забрать базу Hive без пароля бесполезно.
///
/// Шифрование — AES-256-GCM из pointycastle. Писать его руками было бы
/// безответственно: в отличие от PBKDF2, который сводится к циклу поверх
/// HMAC, GCM требует арифметики в поле Галуа, и ошибка там тихо превращает
/// шифрование в его видимость.
///
/// **Чего это не даёт.** Защиты от вас самих. Приложение, которое умеет
/// показать вам ключ, показало бы его и тому, кто знает пароль Shield.
/// Смысл здесь — в том, что человек с вашим устройством, но без пароля,
/// не получит ничего.
class SecretVault {
  static const String _box = 'wesios_settings';
  static const String _prefix = 'vault_secret_';
  static const String _saltKey = 'vault_kdf_salt';

  /// Итераций для вывода ключа шифрования.
  ///
  /// Меньше, чем у проверки пароля (120 000): там итерации — единственный
  /// барьер против перебора, здесь же они лишь дополняют его. Держать
  /// столько же значило бы платить задержкой на каждой операции без выигрыша.
  static const int _iterations = 60000;

  /// Ключ шифрования текущей сессии. В Hive не попадает никогда.
  static Uint8List? _sessionKey;

  /// Разблокировано ли хранилище прямо сейчас.
  static final ValueNotifier<bool> unlocked = ValueNotifier<bool>(false);

  /// Меняется при записи и удалении — экраны перечитывают список.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Box<dynamic>? _openBox() {
    try {
      return Hive.box(_box);
    } catch (_) {
      return null;
    }
  }

  /// Соль вывода ключа. Отдельная от соли пароля: из одного пароля не должны
  /// получаться два одинаковых материала для разных целей.
  static Future<String> _salt() async {
    final box = _openBox();
    final existing = box?.get(_saltKey);
    if (existing is String && existing.isNotEmpty) return existing;
    final rng = Random.secure();
    final salt =
        base64Url.encode(List<int>.generate(16, (_) => rng.nextInt(256)));
    await box?.put(_saltKey, salt);
    return salt;
  }

  /// Открывает хранилище паролем Shield.
  ///
  /// Пароль здесь **не проверяется** — проверять его нечем, кроме успешной
  /// расшифровки. Неверный пароль просто даст ключ, которым ничего не
  /// открывается, и [read] вернёт null. Это правильное поведение: отдельная
  /// проверка пароля означала бы ещё одно место, где его можно подобрать.
  static Future<void> unlock(String password) async {
    final salt = await _salt();
    _sessionKey =
        base64.decode(ShieldService.derive(password, salt, _iterations));
    unlocked.value = true;
  }

  /// Закрывает хранилище: ключ забывается.
  static void lock() {
    _sessionKey = null;
    unlocked.value = false;
  }

  /// Почему сейчас нельзя прочитать секреты, или null — если можно.
  static VaultLockReason? get lockReason {
    if (_sessionKey != null) return null;
    return ShieldService.isConfigured
        ? VaultLockReason.locked
        : VaultLockReason.noPassword;
  }

  // ------------------------------------------------------------- шифрование

  static GCMBlockCipher _cipher(Uint8List nonce, bool forEncryption) {
    final gcm = GCMBlockCipher(AESEngine())
      ..init(
        forEncryption,
        AEADParameters(
          KeyParameter(_sessionKey!),
          128, // длина тега аутентификации в битах
          nonce,
          Uint8List(0),
        ),
      );
    return gcm;
  }

  static Uint8List _nonce() {
    // 96 бит — размер, для которого GCM и спроектирован. Nonce не секрет,
    // но обязан не повторяться при одном ключе, поэтому берётся из
    // криптографического источника, а не из счётчика.
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(12, (_) => rng.nextInt(256)));
  }

  /// Шифрует строку. Формат: base64(nonce ‖ шифротекст ‖ тег).
  static String encryptValue(String plain) {
    final nonce = _nonce();
    final out = _cipher(nonce, true).process(
      Uint8List.fromList(utf8.encode(plain)),
    );
    return base64.encode(Uint8List.fromList([...nonce, ...out]));
  }

  /// Расшифровывает строку. null — не тот ключ или испорченные данные.
  ///
  /// GCM проверяет тег сам: подменённый шифротекст не расшифруется в мусор,
  /// а честно бросит исключение. Именно за это его тут и выбрали.
  static String? decryptValue(String stored) {
    try {
      final raw = base64.decode(stored);
      if (raw.length <= 12) return null;
      final nonce = Uint8List.fromList(raw.sublist(0, 12));
      final body = Uint8List.fromList(raw.sublist(12));
      return utf8.decode(_cipher(nonce, false).process(body));
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------ доступ

  /// Имена всех сохранённых секретов. Видны и без разблокировки: сам факт,
  /// что ключ существует, не секрет — секретно его значение.
  static List<String> get names {
    final box = _openBox();
    if (box == null) return const [];
    return box.keys
        .whereType<String>()
        .where((k) => k.startsWith(_prefix))
        .map((k) => k.substring(_prefix.length))
        .toList()
      ..sort();
  }

  static bool has(String name) =>
      _openBox()?.get('$_prefix$name') is String;

  /// Читает секрет. null — хранилище закрыто, ключа нет или пароль не тот.
  static String? read(String name) {
    if (_sessionKey == null) return null;
    final stored = _openBox()?.get('$_prefix$name');
    if (stored is! String) return null;
    return decryptValue(stored);
  }

  /// Записывает секрет. false — хранилище закрыто.
  static Future<bool> write(String name, String value) async {
    if (_sessionKey == null) return false;
    final box = _openBox();
    if (box == null) return false;
    await box.put('$_prefix$name', encryptValue(value));
    revision.value++;
    return true;
  }

  static Future<void> delete(String name) async {
    await _openBox()?.delete('$_prefix$name');
    revision.value++;
  }

  /// Стирает все секреты и соль.
  ///
  /// Вызывается при смене пароля Shield: старые записи новым ключом уже не
  /// открыть, и оставить их значило бы копить мусор, который выглядит как
  /// данные.
  static Future<void> wipe() async {
    final box = _openBox();
    if (box == null) return;
    for (final name in names) {
      await box.delete('$_prefix$name');
    }
    await box.delete(_saltKey);
    lock();
    revision.value++;
  }
}
