import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Договорённости безопасности сервера, которые легко потерять правкой.
///
/// Каждая из них однажды была нарушена, и ни одну нельзя увидеть глазами в
/// работающем приложении: снаружи всё выглядит исправно и тогда, и сейчас.
void main() {
  String hook(String name) =>
      File('server/pb_hooks/$name').readAsStringSync();

  test('хэш пароля не покидает сервер ни для кого', () {
    // Зачистка стояла под `!ctx.isOwner`, и владелец получал хэши и соли
    // всех сотрудников: на его устройстве оказывалась готовая база для
    // офлайн-перебора, а локальное хранилище приложения не шифруется.
    final read = hook('wesi_sync_read.pb.js');
    final scrub = RegExp(
      r'if \(collection === "employees" && p && typeof p === "object"\) \{',
    );
    expect(scrub.hasMatch(read), isTrue,
        reason: 'безусловная зачистка полей пароля исчезла');

    // Она обязана стоять после всех проверок доступа, иначе ветка для
    // не-владельца снова окажется единственным местом, где это делается.
    expect(read.indexOf('passwordHash": ""'),
        lessThan(read.lastIndexOf('items.push(')),
        reason: 'зачистка должна выполняться до отдачи ответа');
  });

  test('клиент не отправляет и не принимает поля пароля', () {
    final codec = File('lib/core/sync/sync_codec.dart').readAsStringSync();
    expect(codec.contains("'passwordHash': value.passwordHash"), isFalse,
        reason: 'хэш снова уходит в синхронизацию');
    expect(codec.contains("passwordHash: _str(fields['passwordHash'])"), isFalse,
        reason: 'чужой хэш снова принимается в локальное хранилище');
  });

  test('в фильтрах нет склейки строк', () {
    // Сейчас все значения проверены до подстановки, но защита держится на
    // том, что проверка стоит выше по коду — в трёх десятках мест. Одна
    // забытая валидация превращает это в подмену условия фильтра.
    final concat = RegExp(r'''"[a-z_]+='" \+|rid='[a-z-]+:" \+''');
    final offenders = <String>[];
    for (final file in Directory('server/pb_hooks').listSync()) {
      if (file is! File || !file.path.endsWith('.js')) continue;
      if (concat.hasMatch(file.readAsStringSync())) {
        offenders.add(file.path.split('/').last);
      }
    }
    expect(offenders, isEmpty,
        reason: 'значение подставляется в строку фильтра вместо параметра: '
            '${offenders.join(', ')}');
  });

  test('заголовки безопасности выставляются на каждый ответ', () {
    final security = hook('wesi_security.pb.js');
    for (final header in const [
      'Strict-Transport-Security',
      'Content-Security-Policy',
      'Referrer-Policy',
      'Permissions-Policy',
    ]) {
      expect(security.contains(header), isTrue, reason: 'нет $header');
    }
    // Страница портала верстается со вшитыми CSS и JS, поэтому inline там
    // неизбежен. А всё остальное — JSON и файлы — не выполняет ничего, и
    // послабление туда попасть не должно.
    expect(security.contains("default-src 'none'"), isTrue,
        reason: 'для API нет жёсткой политики');
  });

  test('прямой вход по паролю в PocketBase закрыт', () {
    expect(hook('wesi_security.pb.js').contains('auth-with-password'), isTrue,
        reason: 'перехват прямого пароль-входа исчез');
  });
}
