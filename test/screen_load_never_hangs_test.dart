import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Загрузка экрана обязана заканчиваться — успехом или понятным отказом.
///
/// Поломка была одинаковой в дюжине экранов: `_load()` шёл цепочкой `await`
/// без страховки, и одно исключение в середине оставляло `_loading`
/// включённым навсегда. Снаружи это вечный спиннер — самое бесполезное
/// состояние из возможных: работать нельзя, причина неизвестна, и даже
/// непонятно, ждать ещё или нет.
///
/// Проверка идёт по исходникам, а не через интерфейс: поднимать дюжину
/// экранов с настоящими Hive-коробками и подменёнными сбоями дороже и
/// хрупче, чем прочитать код. Правило простое и проверяемое глазами: если в
/// функции есть `_loading = false` и есть `await`, то должен быть и `catch`.
void main() {
  test('ни один экран не остаётся в вечной загрузке', () {
    final offenders = <String>[];
    final root = Directory('lib/features');

    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (!source.contains('_loading = false')) continue;

      final functions = _asyncFunctions(source);
      for (final function in functions) {
        if (!function.body.contains('_loading = false')) continue;
        if (!function.body.contains('await ')) continue;
        if (function.body.contains('catch')) continue;
        // Тело могло быть вынесено, а страховка остаться в вызывающем: это
        // обычный и правильный приём, и объявлять его поломкой нельзя.
        final guardedByCaller = functions.any((caller) =>
            caller.name != function.name &&
            caller.body.contains('${function.name}(') &&
            caller.body.contains('catch'));
        if (guardedByCaller) continue;
        offenders.add('${entity.path}: ${function.name}()');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'здесь загрузка может оборваться исключением и оставить экран '
          'в вечном спиннере:\n  ${offenders.join('\n  ')}',
    );
  });
}

class _AsyncFunction {
  final String name;
  final String body;
  const _AsyncFunction(this.name, this.body);
}

/// Все `Future<...> _имя(...) async { ... }` вместе с телами.
///
/// Границы тела ищутся счётом скобок, а не регулярным выражением: вложенные
/// замыкания в теле — обычное дело, и по первой закрывающей скобке функция
/// обрывалась бы на середине.
List<_AsyncFunction> _asyncFunctions(String source) {
  final result = <_AsyncFunction>[];
  final header = RegExp(r'Future<[^>]*>\s+(_\w+)\([^)]*\)\s*(?:async\s*)\{');
  for (final match in header.allMatches(source)) {
    final name = match.group(1)!;
    var depth = 0;
    var index = match.end - 1;
    while (index < source.length) {
      final char = source[index];
      if (char == '{') depth++;
      if (char == '}') {
        depth--;
        if (depth == 0) break;
      }
      index++;
    }
    result.add(_AsyncFunction(name, source.substring(match.end - 1, index)));
  }
  return result;
}
