import 'dart:math';

import 'package:hive/hive.dart';

import 'credentials_generator.dart';

/// Учёт логинов: какие свободны, какие заняты.
///
/// Занятость хранится отдельным списком, а не выводится из списка
/// сотрудников. Причина в удалении: когда человека убирают, его логин обязан
/// вернуться в свободные — и обязан вернуться ОДИН раз, а не «каждый раз,
/// когда кто-то посчитает заново». Явный список делает это событие видимым
/// и проверяемым.
class LoginPoolService {
  LoginPoolService._();

  static const String _box = 'wesios_settings';
  static const String _takenKey = 'team_logins_taken';

  static Box<dynamic>? _open() {
    try {
      return Hive.box(_box);
    } catch (_) {
      return null;
    }
  }

  /// Занятые логины.
  static Set<String> get taken {
    final raw = _open()?.get(_takenKey);
    if (raw is! List) return {};
    return raw.whereType<String>().toSet();
  }

  /// Свободные логины из словаря — то, что можно предложить.
  static List<String> get free {
    final busy = taken;
    return CredentialsGenerator.words
        .where((w) => !busy.contains(w))
        .toList();
  }

  static int get freeCount => free.length;

  static bool isTaken(String login) =>
      taken.contains(CredentialsGenerator.normalize(login));

  /// Предлагает свободный логин, ничего не занимая.
  ///
  /// Занятие — отдельным вызовом [reserve] и только после того, как
  /// сотрудник действительно создан. Иначе закрытое на полпути окно съедало
  /// бы логины навсегда.
  static String? suggest({Random? random}) =>
      CredentialsGenerator.pick(taken, random: random);

  /// Помечает логин занятым. false — уже занят кем-то.
  static Future<bool> reserve(String login) async {
    final normalized = CredentialsGenerator.normalize(login);
    final busy = taken;
    if (busy.contains(normalized)) return false;
    busy.add(normalized);
    await _open()?.put(_takenKey, busy.toList()..sort());
    return true;
  }

  /// Возвращает логин в свободные — когда сотрудника убрали.
  static Future<void> release(String login) async {
    final normalized = CredentialsGenerator.normalize(login);
    final busy = taken;
    if (!busy.remove(normalized)) return;
    await _open()?.put(_takenKey, busy.toList()..sort());
  }

  /// Приводит список занятых в соответствие с реальными сотрудниками.
  ///
  /// Нужно после восстановления из резервной копии или сбоя: там список
  /// занятых и список людей могли разъехаться, и тогда либо логин нельзя
  /// выдать, хотя он ничей, либо наоборот — выдаётся дважды.
  static Future<void> reconcile(Iterable<String> activeLogins) async {
    final actual = activeLogins
        .map(CredentialsGenerator.normalize)
        .where((l) => l.isNotEmpty)
        .toSet();
    await _open()?.put(_takenKey, actual.toList()..sort());
  }

  /// Только для тестов и полного сброса.
  static Future<void> clear() async => _open()?.delete(_takenKey);
}
