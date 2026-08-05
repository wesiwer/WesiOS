import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('team admin status and archive stay owner-only', () {
    final contacts = File('lib/features/team/contacts_screen.dart').readAsStringSync();
    final service = File('lib/features/team/services/employee_admin_service.dart')
        .readAsStringSync();
    final archive =
        File('lib/features/team/deleted_employees_screen.dart').readAsStringSync();

    expect(contacts, contains('TeamService.isOwnerSession'));
    expect(contacts, contains('В процессе активации'));
    expect(contacts, contains('Активирован'));
    expect(service, contains("'deletedAt'"));
    expect(service, contains("'reason'"));
    expect(service, isNot(contains('passwordHash')));
    expect(archive, contains('Раздел доступен только владельцу'));
  });
}
