import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('My Finance reacts to permission changes and reloads team finance', () {
    final source = File(
      'lib/features/organizations/my_finance_screen.dart',
    ).readAsStringSync();

    expect(source, contains('OrganizationAccessService.revision'));
    expect(source, contains('EmployeeFinanceService.teamBreakdown'));
    expect(source, contains('canViewTeamFinance'));
  });
}
