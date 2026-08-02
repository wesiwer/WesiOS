import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_auth/local_auth.dart';

import '../services/backup_service.dart';
import '../services/github_auth_service.dart';
import 'package:flutter/services.dart';

/// Что именно закрывает Wesi Shield.
enum ShieldScope {
  /// Только секция с ключами Firebase (как было до Shield).
  keysOnly,

  /// Всё приложение: блокировка при запуске и после бездействия.
  wholeApp,
}

/// Событие журнала безопасности.
class ShieldEvent {
  final DateTime at;
  final String kind;
  final bool success;
  final String? detail;

  const ShieldEvent({
    required this.at,
    required this.kind,
    required this.success,
    this.detail,
  });

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'kind': kind,
        'success': success,
        'detail': detail,
      };

  static ShieldEvent? fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    final kind = json['kind'];
    if (at == null || kind is! String) return null;
    return ShieldEvent(
      at: at,
      kind: kind,
      success: json['success'] == true,
      detail: json['detail'] as String?,
    );
  }
}

/// Оценка защищённости — то, что показывает панель Shield.
class ShieldAssessment {
  /// 0..100. Не «безопасность» в абсолюте, а насколько использованы те меры,
  /// которые приложение реально умеет.
  final int score;
  final List<String> good;
  final List<String> advice;

  const ShieldAssessment({
    required this.score,
    required this.good,
    required this.advice,
  });
}

/// Wesi Shield — защита доступа к WesiOS.
///
/// Что изменилось против прежнего замка на ключах Firebase:
///
/// 1. **PBKDF2 вместо одиночного SHA-256.** Один проход SHA-256 считается
///    миллиардами хэшей в секунду на обычной видеокарте, поэтому короткий
///    пароль подбирался бы за минуты даже с солью. Здесь 120 000 итераций
///    HMAC-SHA256: проверка занимает доли секунды у владельца и делает
///    перебор дороже на пять-шесть порядков.
/// 2. **Задержка после неудачных попыток.** Растёт экспоненциально, чтобы
///    подбор пароля на самом устройстве упирался во время, а не только в
///    стойкость хэша.
/// 3. **Автоблокировка по бездействию** и блокировка всего приложения, а не
///    одной секции.
/// 4. **Журнал** — видно, были ли неудачные попытки входа.
///
/// Пароль по-прежнему **не хранится**: в Hive лежит только соль, число
/// итераций и производный ключ.
class ShieldService {
  static const String _box = 'wesios_settings';

  static const String _hashKey = 'shield_hash';
  static const String _saltKey = 'shield_salt';
  static const String _iterKey = 'shield_iterations';
  static const String _bioKey = 'shield_biometrics';
  static const String _scopeKey = 'shield_scope';
  static const String _timeoutKey = 'shield_timeout_minutes';
  static const String _failKey = 'shield_failed_attempts';
  static const String _lastFailKey = 'shield_last_failure';
  static const String _logKey = 'shield_log';
  static const String _wipeKey = 'shield_wipe_after';

  // Ключи прежнего замка на секции Firebase. Нужны только для переноса: у тех,
  // кто уже задал пароль, он должен продолжить работать после обновления.
  static const String _legacyHashKey = 'vault_pass_hash';
  static const String _legacySaltKey = 'vault_pass_salt';
  static const String _legacyBioKey = 'vault_biometrics_enabled';

  /// Итераций PBKDF2. Подобрано так, чтобы проверка занимала десятки
  /// миллисекунд на телефоне: заметно для перебора, незаметно для человека.
  static const int _iterations = 120000;

  /// Сколько событий журнала храним. Больше не нужно: журнал — для того,
  /// чтобы заметить чужие попытки, а не для вечного архива.
  static const int _logLimit = 50;

  static final LocalAuthentication _auth = LocalAuthentication();

  /// Заблокировано ли приложение прямо сейчас.
  static final ValueNotifier<bool> locked = ValueNotifier<bool>(false);

  /// Меняется при любой правке настроек — панель Shield перечитывает статус.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static DateTime? _lastActivity;

  // ---------------------------------------------------------------- пароль

  static bool get isConfigured {
    try {
      final h = Hive.box(_box).get(_hashKey);
      if (h is String && h.isNotEmpty) return true;
      return hasLegacyPassword;
    } catch (_) {
      return false;
    }
  }

  /// Остался ли пароль от прежнего замка на ключах Firebase.
  ///
  /// Пока он есть, вход по нему работает: молча обнулить чужой пароль при
  /// обновлении — значит открыть секцию с ключами всем подряд.
  static bool get hasLegacyPassword {
    try {
      final h = Hive.box(_box).get(_legacyHashKey);
      return h is String && h.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static bool _verifyLegacy(String password) {
    try {
      final box = Hive.box(_box);
      final salt = box.get(_legacySaltKey);
      final stored = box.get(_legacyHashKey);
      if (salt is! String || stored is! String) return false;
      final hash =
          sha256.convert(utf8.encode('$salt$password')).toString();
      return _constantTimeEquals(hash, stored);
    } catch (_) {
      return false;
    }
  }

  /// Переносит старый пароль на PBKDF2 и стирает слабый хэш.
  ///
  /// Момент выбран не случайно: только при успешном входе пароль известен в
  /// открытом виде, а значит только тогда из него и можно вывести новый ключ.
  static Future<void> _upgradeLegacy(String password) async {
    final box = Hive.box(_box);
    final bio = box.get(_legacyBioKey) == true;
    await setPassword(password);
    if (bio) await box.put(_bioKey, true);
    for (final key in [_legacyHashKey, _legacySaltKey, _legacyBioKey]) {
      await box.delete(key);
    }
    await _log('legacy_upgrade', true, 'PBKDF2');
  }

  static String _newSalt() {
    // Random.secure() — криптографический источник; обычный Random
    // предсказуем и для соли не годится.
    final rng = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => rng.nextInt(256)));
  }

  /// PBKDF2-HMAC-SHA256.
  ///
  /// Реализован вручную: пакет `crypto` даёт только Hmac, а тянуть ещё одну
  /// зависимость ради двадцати строк смысла нет. Алгоритм стандартный
  /// (RFC 8018), поэтому результат воспроизводим и проверяем тестом.
  static String derive(String password, String salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(password));
    // dkLen == длине хэша, поэтому один блок: INT_32_BE(1).
    final block = <int>[...utf8.encode(salt), 0, 0, 0, 1];
    var u = Uint8List.fromList(hmac.convert(block).bytes);
    final result = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return base64.encode(result);
  }

  static Future<void> setPassword(String password) async {
    final salt = _newSalt();
    final box = Hive.box(_box);
    await box.put(_saltKey, salt);
    await box.put(_iterKey, _iterations);
    await box.put(_hashKey, derive(password, salt, _iterations));
    await box.put(_failKey, 0);
    await _log('password_set', true);
    revision.value++;
  }

  /// Сравнение хэшей за постоянное время.
  ///
  /// Обычное `==` на строках выходит на первом различии, и по времени ответа
  /// можно подбирать хэш посимвольно. Здесь время не зависит от того, где
  /// именно строки разошлись.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static bool _verifyRaw(String password) {
    try {
      final box = Hive.box(_box);
      final salt = box.get(_saltKey);
      final stored = box.get(_hashKey);
      final iterations = (box.get(_iterKey) as num?)?.toInt() ?? _iterations;
      if (salt is! String || stored is! String) return _verifyLegacy(password);
      return _constantTimeEquals(derive(password, salt, iterations), stored);
    } catch (_) {
      return false;
    }
  }

  /// Проверяет пароль с учётом задержки и счётчика неудач.
  static Future<bool> verify(String password) async {
    if (lockoutRemaining > Duration.zero) return false;

    final ok = _verifyRaw(password);
    final box = Hive.box(_box);
    if (ok) {
      if (hasLegacyPassword) await _upgradeLegacy(password);
      await box.put(_failKey, 0);
      await _log('unlock_password', true);
      unlock();
    } else {
      final fails = failedAttempts + 1;
      await box.put(_failKey, fails);
      await box.put(_lastFailKey, DateTime.now().toIso8601String());
      await _log('unlock_password', false, 'попытка $fails');
      // Порог стирания — осознанный выбор пользователя, по умолчанию выключен.
      final wipeAfter = wipeAfterAttempts;
      if (wipeAfter != null && fails >= wipeAfter) {
        await _wipeData();
      }
    }
    revision.value++;
    return ok;
  }

  // ------------------------------------------------------- защита от подбора

  static int get failedAttempts {
    try {
      return (Hive.box(_box).get(_failKey) as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Задержка после неудач: растёт экспоненциально, но не бесконечно.
  ///
  /// До третьей попытки задержки нет вовсе — обычная опечатка не должна
  /// наказывать владельца. Дальше 15 с, 30 с, минута… с потолком в 15 минут:
  /// без потолка забытый пароль превратил бы устройство в кирпич.
  static Duration get lockoutRemaining {
    final fails = failedAttempts;
    if (fails < 3) return Duration.zero;
    try {
      final raw = Hive.box(_box).get(_lastFailKey);
      final last = DateTime.tryParse(raw as String? ?? '');
      if (last == null) return Duration.zero;
      final penaltySeconds =
          min(15 * pow(2, fails - 3).toInt(), 15 * 60);
      final until = last.add(Duration(seconds: penaltySeconds));
      final left = until.difference(DateTime.now());
      return left.isNegative ? Duration.zero : left;
    } catch (_) {
      return Duration.zero;
    }
  }

  /// Сколько неудачных попыток до стирания данных. null — никогда.
  static int? get wipeAfterAttempts {
    try {
      final v = Hive.box(_box).get(_wipeKey);
      return v is int && v > 0 ? v : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setWipeAfterAttempts(int? attempts) async {
    final box = Hive.box(_box);
    if (attempts == null || attempts <= 0) {
      await box.delete(_wipeKey);
    } else {
      await box.put(_wipeKey, attempts);
    }
    await _log('wipe_policy', true, attempts == null ? 'выключено' : '$attempts');
    revision.value++;
  }

  /// Стирает рабочие данные, оставляя настройки и журнал: иначе после
  /// срабатывания было бы не видно, что вообще произошло.
  /// Стирание идёт через [BackupService.clearLocalData]: один и тот же список
  /// боксов и одно и то же знание об их типах. Своя копия здесь однажды
  /// отстала бы от него — и стирала бы не всё.
  static Future<void> _wipeData() async {
    await BackupService.clearLocalData();
    // Токен GitHub даёт доступ к приватному репозиторию. Стереть финансы и
    // оставить ключ от репозитория — половина работы: тот, ради кого стирание
    // и затевалось, унёс бы его вместе с устройством.
    await GitHubAuthService.signOut();
    await _log('wipe', true, 'сработал порог неудачных попыток');
  }

  // ------------------------------------------------------------- биометрия

  static bool get biometricsEnabled {
    try {
      return Hive.box(_box).get(_bioKey) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setBiometricsEnabled(bool value) async {
    await Hive.box(_box).put(_bioKey, value);
    await _log('biometrics', true, value ? 'включена' : 'выключена');
    revision.value++;
  }

  /// Биометрия есть только на телефоне. На десктопе `local_auth` бросает
  /// MissingPluginException, поэтому туда даже не заходим.
  static Future<bool> get isBiometricAvailable async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return false;
    try {
      return await _auth.canCheckBiometrics ||
          await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateBiometric(String reason) async {
    if (!await isBiometricAvailable) return false;

    // Проверяем, есть ли реально зарегистрированные биометрии
    try {
      final available = await _auth.getAvailableBiometrics();
      if (available.isEmpty) return false;
    } catch (_) {
      return false;
    }

    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );
      await _log('unlock_biometric', ok);
      if (ok) {
        await Hive.box(_box).put(_failKey, 0);
        unlock();
      }
      return ok;
    } on PlatformException catch (e) {
      await _log('unlock_biometric', false, e.code.toString());
      return false;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------- область и таймаут

  static ShieldScope get scope {
    try {
      return Hive.box(_box).get(_scopeKey) == 'app'
          ? ShieldScope.wholeApp
          : ShieldScope.keysOnly;
    } catch (_) {
      return ShieldScope.keysOnly;
    }
  }

  static Future<void> setScope(ShieldScope value) async {
    await Hive.box(_box)
        .put(_scopeKey, value == ShieldScope.wholeApp ? 'app' : 'keys');
    await _log('scope', true,
        value == ShieldScope.wholeApp ? 'всё приложение' : 'только ключи');
    revision.value++;
  }

  /// Через сколько минут бездействия закрываться. 0 — не закрываться.
  static int get timeoutMinutes {
    try {
      return (Hive.box(_box).get(_timeoutKey) as num?)?.toInt() ?? 5;
    } catch (_) {
      return 5;
    }
  }

  static Future<void> setTimeoutMinutes(int minutes) async {
    await Hive.box(_box).put(_timeoutKey, minutes);
    await _log('timeout', true, '$minutes мин.');
    revision.value++;
  }

  // ------------------------------------------------------------- блокировка

  /// Нужна ли блокировка прямо сейчас (вызывается при старте).
  static bool get shouldLockOnStart =>
      isConfigured && scope == ShieldScope.wholeApp;

  static void lock() {
    if (!isConfigured) return;
    locked.value = true;
  }

  static void unlock() {
    locked.value = false;
    _lastActivity = DateTime.now();
  }

  /// Отмечает активность пользователя — от неё считается таймаут.
  static void touch() => _lastActivity = DateTime.now();

  /// Пора ли закрыться по бездействию.
  static bool get shouldAutoLock {
    if (!isConfigured || scope != ShieldScope.wholeApp) return false;
    if (locked.value) return false;
    final minutes = timeoutMinutes;
    if (minutes <= 0) return false;
    final last = _lastActivity;
    if (last == null) return false;
    return DateTime.now().difference(last).inMinutes >= minutes;
  }

  /// Проверяет таймаут и закрывает приложение, если пора.
  static void checkAutoLock() {
    if (shouldAutoLock) {
      lock();
      _log('auto_lock', true, 'бездействие');
    }
  }

  // ----------------------------------------------------------------- журнал

  static Future<void> _log(String kind, bool success, [String? detail]) async {
    try {
      final box = Hive.box(_box);
      final raw = box.get(_logKey);
      final list = <String>[
        if (raw is List) ...raw.map((e) => '$e'),
      ];
      list.insert(
        0,
        jsonEncode(ShieldEvent(
          at: DateTime.now(),
          kind: kind,
          success: success,
          detail: detail,
        ).toJson()),
      );
      if (list.length > _logLimit) list.removeRange(_logLimit, list.length);
      await box.put(_logKey, list);
    } catch (_) {
      // Журнал — вспомогательная вещь: его отказ не должен ломать вход.
    }
  }

  static List<ShieldEvent> get log {
    try {
      final raw = Hive.box(_box).get(_logKey);
      if (raw is! List) return const [];
      final out = <ShieldEvent>[];
      for (final item in raw) {
        try {
          final e = ShieldEvent.fromJson(
              jsonDecode('$item') as Map<String, dynamic>);
          if (e != null) out.add(e);
        } catch (_) {
          continue;
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> clearLog() async {
    await Hive.box(_box).delete(_logKey);
    revision.value++;
  }

  // ------------------------------------------------------------ оценка и сброс

  /// Стойкость пароля от 0 до 4 — по длине и разнообразию символов.
  ///
  /// Намеренно простая эвристика: точную энтропию по словарю здесь считать
  /// нечем, а завышенная оценка хуже отсутствия оценки.
  static int passwordStrength(String password) {
    if (password.length < 4) return 0;
    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[a-zA-Zа-яА-Я]').hasMatch(password) &&
        RegExp(r'\d').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[^\w\s]').hasMatch(password)) score++;
    return score.clamp(0, 4);
  }

  static ShieldAssessment assess() {
    final good = <String>[];
    final advice = <String>[];
    var score = 0;

    if (isConfigured) {
      score += 40;
      good.add('Пароль задан и хранится только как производный ключ');
    } else {
      advice.add('Задайте пароль — без него остальное не работает');
    }

    if (scope == ShieldScope.wholeApp) {
      score += 25;
      good.add('Закрыто всё приложение, а не только ключи');
    } else if (isConfigured) {
      advice.add('Закройте всё приложение, а не только ключи Firebase');
    }

    if (biometricsEnabled) {
      score += 15;
      good.add('Вход по отпечатку или лицу включён');
    } else if (isConfigured) {
      advice.add('Включите биометрию — быстрее, чем пароль, и не менее надёжно');
    }

    final t = timeoutMinutes;
    if (isConfigured && t > 0 && t <= 15) {
      score += 20;
      good.add('Автоблокировка через $t мин. бездействия');
    } else if (isConfigured) {
      advice.add('Включите автоблокировку — оставленное устройство открыто');
    }

    final fails = failedAttempts;
    if (fails > 0) {
      advice.add('Есть неудачные попытки входа ($fails) — проверьте журнал');
    }

    return ShieldAssessment(
      score: score.clamp(0, 100),
      good: good,
      advice: advice,
    );
  }

  /// Полностью снимает защиту. Требует текущий пароль — иначе снять её мог
  /// бы кто угодно, у кого открыт экран.
  static Future<bool> disable(String currentPassword) async {
    if (!_verifyRaw(currentPassword)) {
      await _log('disable', false);
      return false;
    }
    final box = Hive.box(_box);
    for (final key in [
      _hashKey,
      _saltKey,
      _iterKey,
      _bioKey,
      _failKey,
      _legacyHashKey,
      _legacySaltKey,
      _legacyBioKey,
    ]) {
      await box.delete(key);
    }
    await _log('disable', true);
    unlock();
    revision.value++;
    return true;
  }
}
