import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account changes that arrive during rebind are queued, not discarded', () {
    final source =
        File('lib/core/sync/sync_feature_extensions.dart').readAsStringSync();

    final listenerStart = source.indexOf('static void _onTeamRevision()');
    final requestStart = source.indexOf('static void _requestRebind()');
    expect(listenerStart, greaterThanOrEqualTo(0));
    expect(requestStart, greaterThan(listenerStart));

    final listener = source.substring(listenerStart, requestStart);
    expect(listener, isNot(contains('if (_rebinding ||')),
        reason:
            'identity changes must not be dropped merely because an old rebind is active');
    expect(listener, contains('_requestRebind();'));
    expect(source, contains('_rebindRequestGeneration++'));
    expect(source, contains('while (true)'));
    expect(
      source,
      contains('handledGeneration == _rebindRequestGeneration'),
      reason: 'the worker must drain changes that arrived across await points',
    );
  });

  test('stale rebind pass cannot start auto sync for a different identity', () {
    final source =
        File('lib/core/sync/sync_feature_extensions.dart').readAsStringSync();

    expect(source, contains('final targetEmployeeId = TeamService.current?.id;'));
    expect(
      source,
      contains('final targetAuthUserId = SyncAccountScope.currentUserId;'),
      reason: 'auth user is part of the private sync identity',
    );

    final passStart = source.indexOf('static Future<void> _performRebindPass()');
    final bindStart = source.indexOf('await _bind(allowLegacy: false);', passStart);
    expect(passStart, greaterThanOrEqualTo(0));
    expect(bindStart, greaterThan(passStart));

    final afterReset = source.substring(passStart, bindStart);
    expect(afterReset, contains('TeamService.current?.id != targetEmployeeId'));
    expect(afterReset, contains('SyncAccountScope.currentUserId != targetAuthUserId'));

    final startAuto = source.indexOf('SyncAuto.start();', bindStart);
    expect(startAuto, greaterThan(bindStart));
    final beforeAuto = source.substring(bindStart, startAuto);
    expect(beforeAuto, contains('_bindingMatchesCurrent()'),
        reason:
            'private binding must still match both employee and auth-user before full/auto sync');
    expect(beforeAuto, contains('TeamService.current?.id == targetEmployeeId'));
    expect(beforeAuto, contains('SyncAccountScope.currentUserId == targetAuthUserId'));
  });
}
