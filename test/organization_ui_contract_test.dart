import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('Treasury and Analytics visibly surface subtree organization breakdown', () {
    final treasury = source('lib/features/treasury/treasury_screen.dart');
    final analytics = source('lib/features/analytics/analytics_screen.dart');
    expect(treasury, contains('SubtreeFinanceBreakdown'));
    expect(treasury, contains('OrganizationScope.subtree'));
    expect(analytics, contains('SubtreeFinanceBreakdown'));
    expect(analytics, contains('OrganizationContext.revision.addListener'));
  });

  test('organization management exposes edit and granular permission controls', () {
    final screen = source('lib/features/organizations/organizations_screen.dart');
    expect(screen, contains("value: 'edit'"));
    expect(screen, contains('manageOrgSettings'));
    expect(screen, contains('manageMembers'));
    expect(screen, contains('canViewSelfFinance'));
    expect(screen, contains('canViewTeamFinance'));
    expect(screen, contains('OrganizationPermissions.viewFinance'));
  });

  test('My Finance keeps self view plus period dynamics and personal risks', () {
    final screen = source('lib/features/organizations/my_finance_screen.dart');
    expect(screen, contains('EmployeeFinanceView.self'));
    expect(screen, contains('Мои'));
    expect(screen, contains('const [7, 30, 90]'));
    expect(screen, contains('Динамика к предыдущим'));
    expect(screen, contains('Личные риски'));
  });

  test('CRM UI writes stable employee IDs for clients and deals', () {
    final screen = source('lib/features/crm/crm_screen.dart');
    expect(screen, contains('storeEmployeeId: true'));
    expect(screen, contains('ownerEmployeeId: ownerEmployee?.id'));
    expect(screen, contains('responsibleEmployeeId: _responsibleEmployeeId'));
  });

  test('Contacts follows organization context and grants new members to current org', () {
    final screen = source('lib/features/team/contacts_screen.dart');
    expect(screen, contains('OrganizationContext.revision.addListener'));
    expect(screen, contains('OrganizationContext.effectiveOrganizationIds'));
    expect(screen, contains('OrganizationSwitcher(compact: true)'));
    expect(screen, contains('OrganizationAccessService.grant'));
    expect(screen, contains('OrganizationPermissions.manageMembers'));
  });
}
