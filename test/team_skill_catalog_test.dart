import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/services/team_skill_service.dart';

/// Справочник навыков: понятный, русский и разложенный по областям.
///
/// Первая версия была плоским списком из двадцати двух строк на двух языках
/// сразу: «Битмейкинг», «Sound design», «Outreach», «QA», «Motion design».
/// Выбирать из такого нельзя — половину названий надо сначала перевести, а
/// потом догадаться, чем «Контент» отличается от «Копирайтинга».
///
/// Переименование справочника — это ещё и правка данных: навыки хранятся
/// строками в карточках людей, и небрежное переименование оставило бы в них
/// записи, которые уже нельзя ни выбрать, ни снять. Поэтому здесь
/// проверяется и то, что старый выбор переживает переезд.
void main() {
  EmployeeModel person(List<String> skills) => EmployeeModel(
        id: 'e1',
        login: 'e1',
        fullName: 'Человек',
        position: '',
        skills: skills,
        createdAt: DateTime(2026, 1, 1),
      );

  group('справочник', () {
    test('навыки разложены по областям, а не свалены в кучу', () {
      expect(TeamSkillService.catalog.length, greaterThanOrEqualTo(5));
      for (final category in TeamSkillService.catalog) {
        expect(category.skills, isNotEmpty,
            reason: 'пустая область «${category.name}» бесполезна');
      }
    });

    test('все названия по-русски', () {
      // Ровно та претензия, с которой всё началось: в списке рядом стояли
      // «Битмейкинг» и «Sound design», и второе приходилось переводить.
      final latin = RegExp(r'[A-Za-z]');
      for (final category in TeamSkillService.catalog) {
        expect(latin.hasMatch(category.name), isFalse,
            reason: 'область «${category.name}» не по-русски');
        for (final skill in category.skills) {
          expect(latin.hasMatch(skill.name), isFalse,
              reason: 'навык «${skill.name}» не по-русски');
        }
      }
    });

    test('названия не повторяются между областями', () {
      final seen = <String>{};
      for (final category in TeamSkillService.catalog) {
        for (final skill in category.skills) {
          expect(seen.add(skill.name.toLowerCase()), isTrue,
              reason: '«${skill.name}» встречается дважды');
        }
      }
    });

    test('английские названия остались синонимами, а не пропали', () {
      // Убрать «Sound design» из выбора — правильно. Потерять само слово —
      // нет: по нему ищут, и им подписаны роли в шаблонах задач.
      final aliases = <String>{
        for (final category in TeamSkillService.catalog)
          for (final skill in category.skills)
            ...skill.aliases.map((a) => a.toLowerCase()),
      };
      for (final word in ['sound design', 'motion design', 'smm', 'qa',
        'outreach', 'flutter', 'project management']) {
        expect(aliases, contains(word), reason: 'потеряно слово «$word»');
      }
    });
  });

  group('старый выбор переживает переименование', () {
    test('каждое имя из первой версии находит нынешнее', () {
      const old = [
        'Битмейкинг', 'Продакшн', 'Сведение', 'Мастеринг', 'Sound design',
        'Графический дизайн', 'Motion design', 'Монтаж видео', 'Контент',
        'SMM', 'Маркетинг', 'Продажи', 'Outreach', 'Работа с клиентами',
        'Аналитика', 'Финансы', 'Операционное управление',
        'Project management', 'Разработка', 'Flutter', 'QA', 'Копирайтинг',
      ];
      final known = TeamSkillService.all.map((s) => s.toLowerCase()).toSet();

      for (final name in old) {
        final now = TeamSkillService.canonical(name);
        expect(known, contains(now.toLowerCase()),
            reason: '«$name» превратился в «$now», которого нет в справочнике');
      }
    });

    test('повторы после переименования схлопываются', () {
      // «SMM» и «Соцсети» — теперь одно и то же. Оставить обе записи значило
      // бы показать человеку одну и ту же фишку дважды.
      final result = TeamSkillService.canonicalAll(['SMM', 'Соцсети', 'QA']);
      expect(result, ['Соцсети', 'Тестирование']);
    });

    test('незнакомое имя остаётся как есть', () {
      expect(TeamSkillService.canonical('Игра на балалайке'),
          'Игра на балалайке');
    });
  });

  group('навыки из должности', () {
    test('битмейкер получает музыкальные навыки', () {
      final skills = TeamSkillService.forPosition('Битмейкер');
      expect(skills, contains('Битмейкинг'));
      expect(skills, contains('Сведение'));
      expect(skills, isNot(contains('Финансовый учёт')));
    });

    test('должность узнаётся внутри длинного названия', () {
      // «Ведущий битмейкер», «битмейкер-стажёр», «Senior битмейкер» — это
      // одна и та же работа, и разбирать их по отдельности бессмысленно.
      for (final title in [
        'Ведущий битмейкер',
        'битмейкер-стажёр',
        'БИТМЕЙКЕР',
      ]) {
        expect(TeamSkillService.forPosition(title), contains('Битмейкинг'),
            reason: 'не узнана должность «$title»');
      }
    });

    test('разные должности дают разные навыки', () {
      final designer = TeamSkillService.forPosition('Графический дизайнер');
      final accountant = TeamSkillService.forPosition('Бухгалтер');

      expect(designer, contains('Графический дизайн'));
      expect(accountant, contains('Финансовый учёт'));
      expect(designer.toSet().intersection(accountant.toSet()), isEmpty);
    });

    test('незнакомая должность не выдумывает навыков', () {
      // Молчание честнее догадки: подставить «Продажи» человеку с должностью
      // «Смотритель маяка» — значит соврать движку назначения задач.
      expect(TeamSkillService.forPosition('Смотритель маяка'), isEmpty);
      expect(TeamSkillService.forPosition(''), isEmpty);
    });

    test('подставленные навыки существуют в справочнике', () {
      final known = TeamSkillService.all.toSet();
      for (final title in [
        'Битмейкер', 'Продюсер', 'Звукорежиссёр', 'Дизайнер', 'Моушен-дизайнер',
        'Видеомонтажёр', 'SMM-менеджер', 'Маркетолог', 'Копирайтер',
        'Менеджер по продажам', 'Аккаунт-менеджер', 'Бухгалтер', 'Аналитик',
        'Проджект-менеджер', 'Операционный директор', 'Разработчик',
        'Flutter-разработчик', 'Тестировщик', 'DevOps',
      ]) {
        for (final skill in TeamSkillService.forPosition(title)) {
          expect(known, contains(skill),
              reason: '«$title» подставляет несуществующий навык «$skill»');
        }
      }
    });
  });

  group('совпадение навыка с задачей', () {
    test('русский навык находится по английской роли из шаблона', () {
      // Это была настоящая дыра: в карточке «Битмейкинг», в шаблоне задачи
      // роль «beatmaker», и совпадения не возникало — строки просто разные.
      // Из-за этого явно указанный навык не давал человеку ничего.
      final fit = TeamSkillService.fitForTask(
        person(['Битмейкинг']),
        roleAliases: const ['beatmaker'],
        taskKeywords: const [],
      );
      expect(fit, greaterThan(.5));
    });

    test('русская роль тоже находится', () {
      final fit = TeamSkillService.fitForTask(
        person(['Битмейкинг']),
        roleAliases: const ['битмейкер'],
        taskKeywords: const [],
      );
      expect(fit, greaterThan(.5));
    });

    test('старое имя навыка в карточке продолжает работать', () {
      final fit = TeamSkillService.fitForTask(
        person(['Sound design']),
        roleAliases: const ['звуковой дизайн'],
        taskKeywords: const [],
      );
      expect(fit, greaterThan(.5));
    });

    test('чужая роль не совпадает', () {
      final fit = TeamSkillService.fitForTask(
        person(['Битмейкинг']),
        roleAliases: const ['бухгалтер'],
        taskKeywords: const [],
      );
      expect(fit, 0);
    });

    test('без навыков совпадения нет', () {
      expect(
        TeamSkillService.fitForTask(
          person(const []),
          roleAliases: const ['beatmaker'],
          taskKeywords: const [],
        ),
        0,
      );
    });
  });
}
