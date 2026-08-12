import 'package:hive/hive.dart';

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
    final existing = all.where((item) =>
        item.toLowerCase() == value.toLowerCase()).firstOrNull;
    if (existing != null) return existing;
    await Hive.box<dynamic>(boxName).put(_key(value), value);
    return value;
  }

  static String _key(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
