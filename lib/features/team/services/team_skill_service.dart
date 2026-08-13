import 'dart:math';

import 'package:hive/hive.dart';

import '../models/employee_model.dart';

/// Один навык справочника.
///
/// [aliases] — не украшение. Движок задач ищет исполнителя по словам вроде
/// «битмейкер» или «beatmaker», а в карточке человека написано
/// «Битмейкинг». Без явного списка синонимов совпадения не будет: строки
/// разные, и никакое сравнение по буквам не обязано их сроднить. Поэтому
/// синонимы перечислены руками — это единственный способ сделать
/// совпадение объяснимым, а не случайным.
class TeamSkill {
  final String name;
  final List<String> aliases;

  const TeamSkill(this.name, {this.aliases = const []});
}

/// Группа навыков одной области работы.
class TeamSkillCategory {
  final String name;
  final List<TeamSkill> skills;

  const TeamSkillCategory(this.name, this.skills);
}

class TeamSkillService {
  TeamSkillService._();

  static const String boxName = 'wesios_team_skills_v1';

  /// Справочник навыков по областям работы.
  ///
  /// Раньше это был плоский список из двадцати двух строк вперемешку на двух
  /// языках: «Битмейкинг», «Sound design», «QA», «Outreach». Выбирать из
  /// такого нельзя — половину названий надо сначала перевести, а потом
  /// догадаться, чем «Контент» отличается от «Копирайтинга». Здесь всё
  /// по-русски и разложено по областям, а английские названия остались
  /// синонимами: они по-прежнему находятся поиском и по-прежнему совпадают
  /// с ролями в шаблонах задач.
  static const List<TeamSkillCategory> catalog = [
    TeamSkillCategory('Музыка и звук', [
      TeamSkill('Битмейкинг',
          aliases: ['битмейкер', 'beatmaker', 'бит', 'beat', 'биты']),
      TeamSkill('Музыкальный продакшн',
          aliases: ['продакшн', 'production', 'продюсер', 'producer']),
      TeamSkill('Аранжировка', aliases: ['аранжировщик', 'arrangement']),
      TeamSkill('Сведение', aliases: ['микс', 'mixing', 'звукорежиссёр']),
      TeamSkill('Мастеринг', aliases: ['mastering', 'мастер']),
      TeamSkill('Звуковой дизайн',
          aliases: ['sound design', 'саунд-дизайн', 'sfx']),
      TeamSkill('Запись вокала',
          aliases: ['вокал', 'запись', 'recording', 'студия']),
    ]),
    TeamSkillCategory('Дизайн и видео', [
      TeamSkill('Графический дизайн',
          aliases: ['дизайнер', 'design', 'графика']),
      TeamSkill('Обложки и афиши',
          aliases: ['обложка', 'cover', 'артворк', 'artwork']),
      TeamSkill('Анимация и моушен',
          aliases: ['motion design', 'моушен', 'аниматор', 'анимация']),
      TeamSkill('Монтаж видео',
          aliases: ['монтаж', 'видеомонтаж', 'video', 'монтажёр']),
      TeamSkill('Съёмка', aliases: ['оператор', 'видеограф', 'фото']),
    ]),
    TeamSkillCategory('Продвижение', [
      TeamSkill('Соцсети', aliases: ['smm', 'сммщик', 'социальные сети']),
      TeamSkill('Реклама и продвижение',
          aliases: ['маркетинг', 'marketing', 'маркетолог', 'таргет', 'ads']),
      TeamSkill('Работа с блогерами',
          aliases: ['блогеры', 'инфлюенсеры', 'influencer', 'коллаборации']),
      TeamSkill('Контент-план',
          aliases: ['контент', 'content', 'контент-менеджер']),
      TeamSkill('Тексты и копирайтинг',
          aliases: ['копирайтинг', 'копирайтер', 'copywriting', 'тексты']),
    ]),
    TeamSkillCategory('Продажи и клиенты', [
      TeamSkill('Продажи', aliases: ['sales', 'продажник', 'менеджер']),
      TeamSkill('Переговоры', aliases: ['переговорщик', 'negotiation']),
      TeamSkill('Поиск клиентов',
          aliases: ['outreach', 'лидогенерация', 'холодные', 'лиды']),
      TeamSkill('Ведение клиентов',
          aliases: ['работа с клиентами', 'аккаунт', 'account', 'crm']),
      TeamSkill('Работа с площадками',
          aliases: ['дистрибуция', 'площадки', 'битстор', 'beatstars']),
    ]),
    TeamSkillCategory('Деньги и учёт', [
      TeamSkill('Финансовый учёт',
          aliases: ['финансы', 'finance', 'бухгалтер', 'касса']),
      TeamSkill('Планирование бюджета',
          aliases: ['бюджет', 'budget', 'планирование']),
      TeamSkill('Налоги и документы',
          aliases: ['налоги', 'договоры', 'документы', 'юрист']),
      TeamSkill('Аналитика и отчёты',
          aliases: ['аналитика', 'analytics', 'аналитик', 'отчёты']),
    ]),
    TeamSkillCategory('Организация работы', [
      TeamSkill('Управление проектами',
          aliases: ['project management', 'проект', 'pm', 'проджект']),
      TeamSkill('Постановка задач',
          aliases: ['задачи', 'планирование работы', 'координация']),
      TeamSkill('Операционное управление',
          aliases: ['операционка', 'операционный', 'coo', 'руководитель']),
      TeamSkill('Найм и обучение',
          aliases: ['найм', 'hr', 'обучение', 'рекрутинг']),
    ]),
    TeamSkillCategory('Технологии', [
      TeamSkill('Разработка',
          aliases: ['разработчик', 'программист', 'developer', 'код']),
      TeamSkill('Мобильные приложения',
          aliases: ['flutter', 'мобильн', 'android', 'ios', 'приложение']),
      TeamSkill('Тестирование', aliases: ['qa', 'тестировщик', 'testing']),
      TeamSkill('Серверы и инфраструктура',
          aliases: ['devops', 'сервер', 'админ', 'инфраструктура']),
    ]),
  ];

  /// Названия из первой версии справочника и их нынешние имена.
  ///
  /// Навыки у сотрудников хранятся строками, и переименование справочника
  /// само по себе оставило бы в карточках висеть «Outreach» и «QA» — уже не
  /// выбираемые, но всё ещё записанные. Здесь старое имя приводится к
  /// новому при чтении карточки, поэтому ничей выбор не теряется.
  static const Map<String, String> renamed = {
    'продакшн': 'Музыкальный продакшн',
    'sound design': 'Звуковой дизайн',
    'motion design': 'Анимация и моушен',
    'контент': 'Контент-план',
    'smm': 'Соцсети',
    'маркетинг': 'Реклама и продвижение',
    'outreach': 'Поиск клиентов',
    'работа с клиентами': 'Ведение клиентов',
    'аналитика': 'Аналитика и отчёты',
    'финансы': 'Финансовый учёт',
    'project management': 'Управление проектами',
    'flutter': 'Мобильные приложения',
    'qa': 'Тестирование',
    'копирайтинг': 'Тексты и копирайтинг',
  };

  /// Какие навыки предполагает должность.
  ///
  /// Ключ ищется в должности как подстрока, поэтому «Ведущий битмейкер» и
  /// «битмейкер-стажёр» одинаково находят «битмейк». Это подстановка, а не
  /// приговор: человек остаётся волен снять лишнее и добавить своё.
  static const Map<String, List<String>> _byPosition = {
    'битмейк': ['Битмейкинг', 'Музыкальный продакшн', 'Сведение'],
    'beatmak': ['Битмейкинг', 'Музыкальный продакшн', 'Сведение'],
    'продюсер': ['Музыкальный продакшн', 'Аранжировка', 'Битмейкинг'],
    'producer': ['Музыкальный продакшн', 'Аранжировка', 'Битмейкинг'],
    'звукореж': ['Сведение', 'Мастеринг', 'Звуковой дизайн'],
    'саунд': ['Звуковой дизайн', 'Сведение'],
    'вокал': ['Запись вокала'],
    'аранжир': ['Аранжировка', 'Музыкальный продакшн'],
    'дизайнер': ['Графический дизайн', 'Обложки и афиши'],
    'моушен': ['Анимация и моушен', 'Монтаж видео'],
    'аниматор': ['Анимация и моушен'],
    'монтаж': ['Монтаж видео', 'Съёмка'],
    'видеограф': ['Съёмка', 'Монтаж видео'],
    'smm': ['Соцсети', 'Контент-план', 'Реклама и продвижение'],
    'маркетолог': ['Реклама и продвижение', 'Аналитика и отчёты', 'Соцсети'],
    'маркетинг': ['Реклама и продвижение', 'Соцсети'],
    'таргет': ['Реклама и продвижение', 'Аналитика и отчёты'],
    'контент': ['Контент-план', 'Соцсети'],
    'копирайт': ['Тексты и копирайтинг', 'Контент-план'],
    'редактор': ['Тексты и копирайтинг', 'Контент-план'],
    'продаж': ['Продажи', 'Переговоры', 'Поиск клиентов'],
    'sales': ['Продажи', 'Переговоры', 'Поиск клиентов'],
    'аккаунт': ['Ведение клиентов', 'Переговоры'],
    'клиент': ['Ведение клиентов', 'Переговоры'],
    'бухгалтер': ['Финансовый учёт', 'Налоги и документы'],
    'финанс': ['Финансовый учёт', 'Планирование бюджета'],
    'юрист': ['Налоги и документы'],
    'аналитик': ['Аналитика и отчёты'],
    'проджект': ['Управление проектами', 'Постановка задач'],
    'проект': ['Управление проектами', 'Постановка задач'],
    'project': ['Управление проектами', 'Постановка задач'],
    'операционн': ['Операционное управление', 'Постановка задач'],
    'руководител': ['Операционное управление', 'Управление проектами'],
    'директор': ['Операционное управление', 'Планирование бюджета'],
    'основател': ['Операционное управление', 'Планирование бюджета'],
    'hr': ['Найм и обучение'],
    'разработчик': ['Разработка', 'Тестирование'],
    'программист': ['Разработка', 'Тестирование'],
    'developer': ['Разработка', 'Тестирование'],
    'flutter': ['Мобильные приложения', 'Разработка'],
    'мобильн': ['Мобильные приложения', 'Разработка'],
    'тестировщик': ['Тестирование'],
    'devops': ['Серверы и инфраструктура', 'Разработка'],
    'систем': ['Серверы и инфраструктура'],
  };

  /// Навыки, которые следуют из должности. Пустой список — если должность
  /// системе незнакома: выдумывать в этом случае нечего.
  static List<String> forPosition(String position) {
    final needle = _normalize(position);
    if (needle.isEmpty) return const [];
    final result = <String>{};
    for (final entry in _byPosition.entries) {
      if (needle.contains(entry.key)) result.addAll(entry.value);
    }
    return result.toList();
  }

  /// Приводит навык к нынешнему имени справочника.
  static String canonical(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return value;
    final renamedTo = renamed[value.toLowerCase()];
    if (renamedTo != null) return renamedTo;
    for (final skill in _flat) {
      if (skill.name.toLowerCase() == value.toLowerCase()) return skill.name;
    }
    return value;
  }

  /// Список навыков сотрудника в нынешних именах, без повторов.
  static List<String> canonicalAll(Iterable<String> raw) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in raw) {
      final name = canonical(item);
      if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
      result.add(name);
    }
    return result;
  }

  static List<TeamSkill> get _flat =>
      [for (final category in catalog) ...category.skills];

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

  /// Навыки, добавленные руками. Справочник их не содержит, но выбирать их
  /// можно наравне со встроенными.
  static List<String> get custom {
    final known = {for (final skill in _flat) skill.name.toLowerCase()};
    final result = <String>[];
    final box = _box();
    if (box == null) return result;
    for (final value in box.values) {
      final name = canonical(value?.toString().trim() ?? '');
      if (name.isEmpty) continue;
      if (known.contains(name.toLowerCase())) continue;
      if (result.any((item) => item.toLowerCase() == name.toLowerCase())) {
        continue;
      }
      result.add(name);
    }
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  static List<String> get all => [
        for (final skill in _flat) skill.name,
        ...custom,
      ];

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
      // Навык сравнивается вместе со своими синонимами: в карточке написано
      // «Битмейкинг», а шаблон задачи ищет «битмейкера», и без синонима эти
      // два слова остались бы чужими друг другу.
      for (final variant in _variantsOf(rawSkill)) {
        final skill = _normalize(variant);
        if (skill.isEmpty) continue;
        for (final needle in needles) {
          if (skill == needle) return 1;
          if (skill.contains(needle) || needle.contains(skill)) {
            best = max(best, .92);
            continue;
          }
          final skillParts =
              skill.split(' ').where((p) => p.length >= 3).toSet();
          final needleParts =
              needle.split(' ').where((p) => p.length >= 3).toSet();
          if (skillParts.intersection(needleParts).isNotEmpty) {
            best = max(best, .82);
          }
        }
      }
    }
    return best;
  }

  /// Само имя навыка плюс все его синонимы из справочника.
  static List<String> _variantsOf(String raw) {
    final name = canonical(raw);
    for (final skill in _flat) {
      if (skill.name.toLowerCase() == name.toLowerCase()) {
        return [skill.name, ...skill.aliases];
      }
    }
    return [name];
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
