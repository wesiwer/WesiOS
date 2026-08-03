import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/team/models/team_permissions.dart';

void main() {
  group('что закрыто по умолчанию', () {
    test('пустой набор не открывает ни один настраиваемый модуль', () {
      const p = TeamPermissions();
      for (final m in TeamModules.all) {
        expect(p.allows(m), isFalse, reason: m);
      }
    });

    test('главная, настройки и профиль открыты всегда', () {
      const p = TeamPermissions();
      for (final m in TeamModules.always) {
        expect(p.allows(m), isTrue, reason: m);
      }
    });

    test('новому сотруднику открыты задачи и ничего сверх', () {
      const p = TeamPermissions.employeeDefault;
      expect(p.allows(TeamModules.tasks), isTrue);
      for (final m in TeamModules.all) {
        if (m == TeamModules.tasks) continue;
        expect(p.allows(m), isFalse, reason: m);
      }
    });

    test('сотрудник по умолчанию не управляет людьми и не видит чужого', () {
      const p = TeamPermissions.employeeDefault;
      expect(p.canManageTeam, isFalse);
      expect(p.canSeeOthersStats, isFalse);
      expect(p.canSeeNotes, isFalse);
    });

    test('владельцу открыто всё', () {
      final p = TeamPermissions.owner;
      for (final m in TeamModules.all) {
        expect(p.allows(m), isTrue, reason: m);
      }
      expect(p.canManageTeam, isTrue);
      expect(p.canSeeOthersStats, isTrue);
      expect(p.canSeeNotes, isTrue);
      expect(p.knowledgeAll, isTrue);
    });
  });

  group('переключение модулей', () {
    test('включение открывает ровно один модуль', () {
      final p = const TeamPermissions().withModule(TeamModules.treasury, true);
      expect(p.allows(TeamModules.treasury), isTrue);
      expect(p.allows(TeamModules.forecast), isFalse);
    });

    test('выключение закрывает обратно', () {
      final p = const TeamPermissions()
          .withModule(TeamModules.treasury, true)
          .withModule(TeamModules.treasury, false);
      expect(p.allows(TeamModules.treasury), isFalse);
    });

    test('повторное включение не плодит дублей', () {
      final p = const TeamPermissions()
          .withModule(TeamModules.tasks, true)
          .withModule(TeamModules.tasks, true);
      expect(p.moduleList.where((m) => m == TeamModules.tasks).length, 1);
    });

    test('«всегда открытые» нельзя отобрать', () {
      final p = const TeamPermissions().withModule('settings', false);
      expect(p.allows('settings'), isTrue);
    });
  });

  group('база знаний по разделам', () {
    test('без доступа не открыта ни одна статья', () {
      const p = TeamPermissions();
      expect(p.allowsArticle('article-1'), isFalse);
    });

    test('открытая статья видна, соседняя — нет', () {
      final p = const TeamPermissions().withArticle('article-1', true);
      expect(p.allowsArticle('article-1'), isTrue);
      expect(p.allowsArticle('article-2'), isFalse);
    });

    test('«вся база» открывает и то, чего ещё нет', () {
      // Смысл флага: новая статья не должна оказываться закрытой для всех,
      // пока владелец про неё не вспомнит.
      const p = TeamPermissions(knowledgeAll: true);
      expect(p.allowsArticle('статья-которой-не-было'), isTrue);
    });

    test('выбор отдельной статьи снимает «всю базу»', () {
      // Иначе получилось бы противоречие: и «всё открыто», и список из
      // одного пункта. Явный выбор важнее общего флага.
      final p =
          const TeamPermissions(knowledgeAll: true).withArticle('a', true);
      expect(p.knowledgeAll, isFalse);
      expect(p.allowsArticle('a'), isTrue);
      expect(p.allowsArticle('b'), isFalse);
    });
  });

  group('перенос в JSON и обратно', () {
    test('набор переживает круг', () {
      final before = const TeamPermissions()
          .withModule(TeamModules.treasury, true)
          .withModule(TeamModules.knowledge, true)
          .withArticle('a1', true)
          .copyWith(canSeeNotes: true);

      final after = TeamPermissions.fromJson(before.toJson());

      expect(after.modules, before.modules);
      expect(after.knowledgeIds, before.knowledgeIds);
      expect(after.canSeeNotes, isTrue);
      expect(after.canManageTeam, isFalse);
    });

    test('битый JSON читается как «ничего не открыто»', () {
      final p = TeamPermissions.fromJson(const {});
      expect(p.modules, isEmpty);
      expect(p.knowledgeAll, isFalse);
      expect(p.canManageTeam, isFalse);
    });

    test('неизвестные значения не открывают лишнего', () {
      final p = TeamPermissions.fromJson(const {
        'canManageTeam': 'да',
        'knowledgeAll': 1,
      });
      // Истиной считается только настоящее true — строка «да» не в счёт.
      expect(p.canManageTeam, isFalse);
      expect(p.knowledgeAll, isFalse);
    });
  });

  group('группировка для экрана прав', () {
    test('каждый модуль попал ровно в одну группу', () {
      final seen = <String>[];
      for (final list in TeamModules.groups.values) {
        seen.addAll(list);
      }
      expect(seen.toSet().length, seen.length, reason: 'модуль в двух группах');
      expect(seen.toSet(), TeamModules.all.toSet(),
          reason: 'модуль потерялся или лишний');
    });

    test('у каждого модуля есть название на обоих языках', () {
      for (final m in TeamModules.all) {
        expect(TeamModules.labelRu(m), isNot(equals(m)), reason: m);
        expect(TeamModules.labelEn(m), isNot(equals(m)), reason: m);
      }
    });
  });
}
