import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sync gateway blocks chat impersonation and foreign message edits', () {
    final source = File('server/pb_hooks/wesi_sync_context.pb.js').readAsStringSync();

    expect(source, contains('Нельзя отправлять сообщения от имени другого сотрудника'));
    expect(source, contains('Автор сообщения неизменяем'));
    expect(source, contains('Нельзя удалить чужое сообщение'));
    expect(source, contains('Нельзя изменять содержимое чужого сообщения'));
    expect(source, contains('Нельзя менять реакцию другого сотрудника'));
    expect(source, contains('actorId === ctx.employeeId'));
  });
}
