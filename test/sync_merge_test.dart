import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/sync/sync_merge.dart';

void main() {
  final t0 = DateTime(2026, 7, 1, 12);
  final t1 = DateTime(2026, 7, 2, 12);
  final t2 = DateTime(2026, 7, 3, 12);

  SyncRecord rec(String id, DateTime at, {String value = 'v'}) =>
      SyncRecord(id: id, updatedAt: at, fields: {'value': value});

  SyncRecord tomb(String id, DateTime at) =>
      SyncRecord(id: id, updatedAt: at, deleted: true);

  Map<String, SyncRecord> map(List<SyncRecord> rs) =>
      {for (final r in rs) r.id: r};

  group('пустые стороны', () {
    test('обе пусты — делать нечего', () {
      final plan = SyncMerge.merge(local: const {}, remote: const {});
      expect(plan.isEmpty, isTrue);
      expect(plan.merged, isEmpty);
    });

    test('пусто в облаке — всё локальное уходит наверх', () {
      final plan = SyncMerge.merge(
        local: map([rec('a', t0), rec('b', t0)]),
        remote: const {},
      );
      expect(plan.toUpload.map((r) => r.id).toSet(), {'a', 'b'});
      expect(plan.toApplyLocally, isEmpty);
    });

    test('пусто локально — всё облачное приходит вниз', () {
      final plan = SyncMerge.merge(
        local: const {},
        remote: map([rec('a', t0)]),
      );
      expect(plan.toApplyLocally.single.id, 'a');
      expect(plan.toUpload, isEmpty);
    });
  });

  group('кто победил', () {
    test('более поздняя правка побеждает — локальная', () {
      final plan = SyncMerge.merge(
        local: map([rec('a', t2, value: 'новое')]),
        remote: map([rec('a', t0, value: 'старое')]),
      );
      expect(plan.merged['a']!.fields['value'], 'новое');
      expect(plan.toUpload.single.id, 'a');
      expect(plan.toApplyLocally, isEmpty);
    });

    test('более поздняя правка побеждает — облачная', () {
      final plan = SyncMerge.merge(
        local: map([rec('a', t0, value: 'старое')]),
        remote: map([rec('a', t2, value: 'новое')]),
      );
      expect(plan.merged['a']!.fields['value'], 'новое');
      expect(plan.toApplyLocally.single.id, 'a');
      expect(plan.toUpload, isEmpty);
    });

    test('одинаковые по времени записи не гоняются туда-сюда', () {
      final plan = SyncMerge.merge(
        local: map([rec('a', t1)]),
        remote: map([rec('a', t1)]),
      );
      expect(plan.isEmpty, isTrue);
    });

    test('одинаковое время, но разные payload сходятся к серверной версии', () {
      final plan = SyncMerge.merge(
        local: map([rec('a', t1, value: 'локально')]),
        remote: map([rec('a', t1, value: 'сервер')]),
      );

      expect(plan.merged['a']!.fields['value'], 'сервер');
      expect(plan.toUpload, isEmpty);
      expect(plan.toApplyLocally.single.id, 'a');
      expect(plan.toApplyLocally.single.fields['value'], 'сервер');
    });

    test('порядок ключей payload не создаёт ложный конфликт', () {
      final local = SyncRecord(
        id: 'a',
        updatedAt: t1,
        fields: {
          'outer': {'b': 2, 'a': 1},
          'list': [
            {'y': 2, 'x': 1}
          ],
        },
      );
      final remote = SyncRecord(
        id: 'a',
        updatedAt: t1,
        fields: {
          'list': [
            {'x': 1, 'y': 2}
          ],
          'outer': {'a': 1, 'b': 2},
        },
      );

      final plan = SyncMerge.merge(
        local: {'a': local},
        remote: {'a': remote},
      );
      expect(plan.isEmpty, isTrue);
    });
  });

  group('удаления не воскресают', () {
    test('удалили в облаке — удаление приезжает к нам', () {
      // Без надгробий эта запись выглядела бы как «есть у меня, нет у них»,
      // и мы бы выгрузили её обратно.
      final plan = SyncMerge.merge(
        local: map([rec('a', t0)]),
        remote: map([tomb('a', t2)]),
      );
      expect(plan.merged['a']!.deleted, isTrue);
      expect(plan.toApplyLocally.single.deleted, isTrue);
      expect(plan.alive, isEmpty);
    });

    test('удалили у нас — удаление уезжает наверх', () {
      final plan = SyncMerge.merge(
        local: map([tomb('a', t2)]),
        remote: map([rec('a', t0)]),
      );
      expect(plan.toUpload.single.deleted, isTrue);
      expect(plan.alive, isEmpty);
    });

    test('правка ПОСЛЕ удаления возвращает запись — это осознанное решение',
        () {
      // Человек мог удалить и тут же создать заново на другом устройстве.
      // Время правки позже времени удаления, значит правка и побеждает.
      final plan = SyncMerge.merge(
        local: map([tomb('a', t0)]),
        remote: map([rec('a', t2, value: 'заново')]),
      );
      expect(plan.merged['a']!.deleted, isFalse);
      expect(plan.merged['a']!.fields['value'], 'заново');
    });

    test('надгробие, которого нет у другой стороны, всё равно доезжает', () {
      final plan = SyncMerge.merge(
        local: const {},
        remote: map([tomb('a', t0)]),
      );
      expect(plan.toApplyLocally.single.deleted, isTrue);
    });

    test('при совпадении времени удаление важнее правки', () {
      // Часы устройств расходятся, и совпадение до миллисекунды — скорее
      // случайность. Воскресить стёртое хуже, чем потерять правку той же
      // миллисекунды: первое подрывает доверие к удалению вообще.
      final a = SyncMerge.merge(
        local: map([tomb('x', t1)]),
        remote: map([rec('x', t1)]),
      );
      expect(a.merged['x']!.deleted, isTrue);

      final b = SyncMerge.merge(
        local: map([rec('x', t1)]),
        remote: map([tomb('x', t1)]),
      );
      expect(b.merged['x']!.deleted, isTrue);
    });
  });

  group('слияние по записям, а не по документу', () {
    test('правки разных записей на разных устройствах обе выживают', () {
      // Главная причина, по которой слияние идёт по записям: иначе правка
      // одной операции на телефоне стёрла бы правку другой на ноутбуке.
      final plan = SyncMerge.merge(
        local: map([rec('a', t2, value: 'правка на ноутбуке'), rec('b', t0)]),
        remote: map([rec('a', t0), rec('b', t2, value: 'правка на телефоне')]),
      );

      expect(plan.merged['a']!.fields['value'], 'правка на ноутбуке');
      expect(plan.merged['b']!.fields['value'], 'правка на телефоне');
      expect(plan.toUpload.map((r) => r.id), ['a']);
      expect(plan.toApplyLocally.map((r) => r.id), ['b']);
    });

    test('после слияния обе стороны приходят к одному состоянию', () {
      final local = map([rec('a', t2), rec('b', t0), tomb('c', t1)]);
      final remote = map([rec('a', t0), rec('b', t2), rec('c', t0)]);

      final first = SyncMerge.merge(local: local, remote: remote);
      // Прогоняем ещё раз уже слитое — второй проход не должен ничего менять.
      final second =
          SyncMerge.merge(local: first.merged, remote: first.merged);

      expect(second.isEmpty, isTrue);
      expect(second.merged.length, first.merged.length);
      expect(first.alive.map((r) => r.id), ['a', 'b']);
    });

    test('порядок сторон не меняет итог', () {
      final local = map([rec('a', t2), tomb('b', t1)]);
      final remote = map([rec('a', t0), rec('b', t0)]);

      final direct = SyncMerge.merge(local: local, remote: remote);
      final swapped = SyncMerge.merge(local: remote, remote: local);

      expect(
        direct.merged.map((k, v) => MapEntry(k, v.deleted)),
        swapped.merged.map((k, v) => MapEntry(k, v.deleted)),
      );
    });
  });

  group('уборка надгробий', () {
    test('свежие надгробия остаются', () {
      final now = DateTime(2026, 7, 10);
      final kept = SyncMerge.pruneTombstones(
        map([tomb('a', DateTime(2026, 7, 1))]),
        now,
      );
      expect(kept.containsKey('a'), isTrue);
    });

    test('старые выбрасываются', () {
      final now = DateTime(2027, 7, 10);
      final kept = SyncMerge.pruneTombstones(
        map([tomb('a', DateTime(2026, 7, 1))]),
        now,
      );
      expect(kept, isEmpty);
    });

    test('живые записи не трогаются, сколько бы им ни было лет', () {
      // Уборка касается только надгробий: операция трёхлетней давности —
      // это данные, а не мусор.
      final now = DateTime(2030, 1, 1);
      final kept = SyncMerge.pruneTombstones(
        map([rec('a', DateTime(2026, 7, 1))]),
        now,
      );
      expect(kept.containsKey('a'), isTrue);
    });
  });
}
