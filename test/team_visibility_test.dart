import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/team/models/team_permissions.dart';

/// Требование: закрытый раздел человек не видит вовсе — ни во вкладках, ни в
/// меню. Не серым, не с замком, а просто нет.
///
/// Здесь проверяется решающая часть — какой набор вкладок и пунктов
/// полагается человеку. Сама отрисовка берёт этот же набор, поэтому если
/// набор верный, то и на экране лишнего не появится.
void main() {
  /// Повторяет правило из HomeScreen._tabs.
  List<String> tabsFor(TeamPermissions p) => [
        'home',
        if (p.allows(TeamModules.tasks)) 'tasks',
        if (p.allows(TeamModules.treasury)) 'treasury',
        if (p.allows(TeamModules.analytics)) 'analytics',
        'more',
      ];

  group('нижние вкладки', () {
    test('новый сотрудник видит главную, задачи и «Ещё»', () {
      expect(tabsFor(TeamPermissions.employeeDefault),
          ['home', 'tasks', 'more']);
    });

    test('финансы и аналитика не показываются, пока не открыты', () {
      final tabs = tabsFor(TeamPermissions.employeeDefault);
      expect(tabs.contains('treasury'), isFalse);
      expect(tabs.contains('analytics'), isFalse);
    });

    test('владелец видит все пять', () {
      expect(tabsFor(TeamPermissions.owner).length, 5);
    });

    test('открыли финансы — вкладка появилась на своём месте', () {
      final p = TeamPermissions.employeeDefault
          .withModule(TeamModules.treasury, true);
      expect(tabsFor(p), ['home', 'tasks', 'treasury', 'more']);
    });

    test('человек без единого права всё равно не заперт', () {
      // Главная и «Ещё» есть всегда: иначе после входа некуда попасть и
      // нечем сменить себе пароль.
      const p = TeamPermissions();
      expect(tabsFor(p), ['home', 'more']);
    });

    test('порядок вкладок не зависит от набора прав', () {
      // Иначе у разных людей одна и та же вкладка оказывалась бы на разных
      // местах, и объяснить что-то по телефону стало бы невозможно.
      final full = tabsFor(TeamPermissions.owner);
      final partial = tabsFor(TeamPermissions.employeeDefault
          .withModule(TeamModules.analytics, true));
      final expected = full.where((t) => partial.contains(t)).toList();
      expect(partial, expected);
    });
  });

  group('пункты меню «Ещё»', () {
    /// Повторяет фильтрацию из MoreTab.
    List<String> menuFor(TeamPermissions p) => [
          for (final m in TeamModules.all)
            if (p.allows(m)) m,
        ];

    test('новому сотруднику видны только задачи', () {
      expect(menuFor(TeamPermissions.employeeDefault), [TeamModules.tasks]);
    });

    test('Wesi Shield и Ключи закрыты по умолчанию', () {
      final menu = menuFor(TeamPermissions.employeeDefault);
      expect(menu.contains(TeamModules.shield), isFalse);
      expect(menu.contains(TeamModules.keys), isFalse);
    });

    test('контакты и чаты тоже закрыты по умолчанию', () {
      final menu = menuFor(TeamPermissions.employeeDefault);
      expect(menu.contains(TeamModules.contacts), isFalse);
      expect(menu.contains(TeamModules.chats), isFalse);
    });

    test('владельцу видно всё', () {
      expect(menuFor(TeamPermissions.owner).toSet(), TeamModules.all.toSet());
    });

    test('выданное право добавляет ровно один пункт', () {
      final before = menuFor(TeamPermissions.employeeDefault).length;
      final after = menuFor(TeamPermissions.employeeDefault
              .withModule(TeamModules.knowledge, true))
          .length;
      expect(after, before + 1);
    });
  });

  group('управление людьми', () {
    test('кнопка «добавить сотрудника» скрыта без права', () {
      expect(TeamPermissions.employeeDefault.canManageTeam, isFalse);
    });

    test('право можно выдать отдельно от доступа к контактам', () {
      // Управлять составом и видеть список — разные вещи: заместитель может
      // заводить людей, не получая при этом чужих заметок.
      final p = TeamPermissions.employeeDefault.copyWith(canManageTeam: true);
      expect(p.canManageTeam, isTrue);
      expect(p.canSeeNotes, isFalse);
    });

    test('скрытые заметки закрыты, даже когда контакты открыты', () {
      final p = TeamPermissions.employeeDefault
          .withModule(TeamModules.contacts, true);
      expect(p.allows(TeamModules.contacts), isTrue);
      expect(p.canSeeNotes, isFalse);
    });
  });
}
