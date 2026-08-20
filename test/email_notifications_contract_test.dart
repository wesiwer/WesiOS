import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('email notification channel is wired end to end', () {
    final watcher = File(
      'lib/core/notifications/notification_watcher.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/features/settings/notification_settings_screen.dart',
    ).readAsStringSync();
    final client = File(
      'lib/core/services/email_notification_service.dart',
    ).readAsStringSync();
    final hook = File(
      'server/pb_hooks/wesi_email_notifications.pb.js',
    ).readAsStringSync();

    expect(
      watcher,
      contains('EmailNotificationService.enqueue(notification)'),
    );
    expect(watcher, contains('EmailNotificationService.flush()'));
    expect(
      watcher,
      contains('SyncEndpoint.revision.addListener(_onEndpointChanged)'),
    );
    expect(
      watcher,
      contains('SyncEndpoint.revision.removeListener(_onEndpointChanged)'),
    );

    expect(settings, contains('EmailNotificationService.enabled'));
    expect(settings, contains('EmailNotificationService.setEnabled'));
    expect(
      settings,
      contains('Все уведомления на почту из карточки сотрудника'),
    );

    expect(client, contains('notify_email_enabled'));
    expect(client, contains('wesios_email_notification_outbox_v1'));
    expect(client, contains('/api/wesi/notifications/email'));
    expect(client, contains('X-WesiOS-Session'));
    expect(client, contains('static String? _scope()'));

    final enqueueStart = client.indexOf('static Future<void> enqueue');
    final flushStart = client.indexOf('static Future<void> flush');
    expect(enqueueStart, greaterThanOrEqualTo(0));
    expect(flushStart, greaterThan(enqueueStart));
    final enqueueBlock = client.substring(enqueueStart, flushStart);
    expect(enqueueBlock, contains('final scope = _scope();'));
    expect(
      enqueueBlock,
      isNot(contains('final auth = _auth();')),
      reason: 'expired sessions must still persist notifications in outbox',
    );

    expect(hook, contains('/api/wesi/notifications/email'));
    expect(hook, contains('requireWesiSession(e)'));
    expect(hook, contains("rid={:rid} && deleted=false"));
    expect(hook, contains("session:"));
    expect(hook, contains(r'$apis.requireAuth'));
    expect(hook, contains("coll='employees'"));
    expect(hook, contains('employeePayload.email'));
    expect(hook, contains('sendMail(e.app, email'));
    expect(hook, contains('__wesios_email_notifications__'));
    expect(
      hook,
      isNot(contains('body.email')),
      reason: 'recipient must come from the employee card, not the client',
    );
  });
}
