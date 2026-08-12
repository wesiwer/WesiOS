import 'dart:math';

import 'package:hive/hive.dart';

import '../models/employee_model.dart';

class TeamSkillService {
  TeamSkillService._();

  static const String boxName = 'wesios_team_skills_v1';

  static const List<String> defaults = [
    'Битмейкинг',
    'Продакшн',
    'Сведение',
    'Мастеринг',
    'Sound design',
    'Графический дизайн',
    'Motion design',
    'Монтаж видео',
    'Контент',
    'SMM',
    'Маркетинг',
    'Продажи',
    'Outreach',
    'Работа с клиентами',
    'Аналитика',
    'Финансы',
    'Операционное управление',
    'Project management',
    'Разработка',
    'Flutter',
    'QA',
    'Копирайтинг',
  ];

  static Box<dynamic>? _box() {
    try {
      return Hive.box<dynamic>(boxName);
    } catch (_) {
      return null;
    }
  }

  static Future<void> ensureOpen() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<dynamic>(boxName);
    }
  }

  static List<String> get all {
    final result = <String>{...defaults};
    final box = _box();
    if (box != null) {
      for (final value in box.values) {
        final name = value?.toString().trim() ?? '';
        if (name.isNotEmpty) result.add(name);
      }
    }
    final list = result.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  static Future<String?> add(String raw) async {
    final value = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.length < 2) return null;
    await ensureOpen();
    final existing = all
        .where((item) => item.toLowerCase() == value.toLowerCase())
        .firstOrNull;
    if (existing != null) return existing;
    await Hive.box<dynamic>(boxName).put(_key(value), value);
    return value;
  }

  /// Returns a bounded compatibility score between an employee's explicit
  /// skills and the task's role aliases / keywords. Explicit skills are a
  /// strong signal, but historical success may still override them in Wesi AI.
  static double fitForTask(
    EmployeeModel employee, {
    required List<String> roleAliases,
    required List<String> taskKeywords,
  }) {
    if (employee.skills.isEmpty) return 0;
    final needles = <String>{
      ...roleAliases.map(_normalize),
      ...taskKeywords.map(_normalize),
    }..removeWhere((value) => value.isEmpty);
    if (needles.isEmpty) return 0;

    var best = 0.0;
    for (final rawSkill in employee.skills) {
      final skill = _normalize(rawSkill);
      if (skill.isEmpty) continue;
      for (final needle in needles) {
        if (skill == needle) return 1;
        if (skill.contains(needle) || needle.contains(skill)) {
          best = max(best, .92);
          continue;
        }
        final skillParts = skill.split(' ').where((p) => p.length >= 3).toSet();
        final needleParts =
            needle.split(' ').where((p) => p.length >= 3).toSet();
        if (skillParts.intersection(needleParts).isNotEmpty) {
          best = max(best, .82);
        }
      }
    }
    return best;
  }

  static String _key(String value) => _normalize(value).replaceAll(' ', '_');

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .trim();
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
