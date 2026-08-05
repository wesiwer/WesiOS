import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/sync/sync_endpoint.dart';
import 'package:wesios/core/widgets/wesi_clock.dart';
import 'package:wesios/features/home/services/alert_service.dart';
import 'package:wesios/features/team/services/portal_account_service.dart';

void main() {
  test('production sync endpoint is fixed to WesiOS HTTPS server', () {
    expect(SyncEndpoint.url, 'https://api.wesi-inc.ru');
    expect(SyncEndpoint.rawUrl, 'https://api.wesi-inc.ru');
  });

  test('portal credential result preserves success and failure state', () {
    const success = PortalCredentialResult.success('ok');
    const failure = PortalCredentialResult.failure('error');
    expect(success.ok, isTrue);
    expect(failure.ok, isFalse);
  });

  test('notification IDs are stable and distinguish changed content', () {
    final first = Alert(
      level: AlertLevel.warning,
      title: 'Test',
      detail: 'One',
      route: '/tasks',
    );
    final same = Alert(
      level: AlertLevel.warning,
      title: 'Test',
      detail: 'One',
      route: '/tasks',
    );
    final changed = Alert(
      level: AlertLevel.warning,
      title: 'Test',
      detail: 'Two',
      route: '/tasks',
    );
    expect(AlertService.idOf(first), AlertService.idOf(same));
    expect(AlertService.idOf(first), isNot(AlertService.idOf(changed)));
  });

  testWidgets('clock and compact month calendar fit a phone header',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 220, child: WesiClock()),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(WesiClock), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
