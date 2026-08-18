import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/routes/app_router.dart';

void main() {
  group('Wesi Telegram deep links', () {
    test('custom-scheme host form resolves to route', () {
      expect(
        AppRouter.routeNameFor('wesios://tasks?organizationId=org_wesi_beats'),
        '/tasks',
      );
      expect(
        AppRouter.routeNameFor(
          'wesios://treasury/forecast?organizationId=org_wesi_beats',
        ),
        '/treasury/forecast',
      );
    });

    test('custom-scheme path form resolves to same route', () {
      expect(
        AppRouter.routeNameFor('wesios:///tasks?organizationId=org_wesi_beats'),
        '/tasks',
      );
      expect(
        AppRouter.routeNameFor('wesios:///treasury/forecast'),
        '/treasury/forecast',
      );
    });

    test('ordinary navigator routes remain unchanged', () {
      expect(AppRouter.routeNameFor('/profile/telegram'), '/profile/telegram');
      expect(AppRouter.routeNameFor('/home'), '/home');
    });
  });
}
