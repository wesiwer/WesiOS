import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/sync/sync_account_scope.dart';

void main() {
  group('SyncAccountScope', () {
    test('different auth users never share a private box', () {
      final a = SyncAccountScope.forUser('wesios_private', 'user_a');
      final b = SyncAccountScope.forUser('wesios_private', 'user_b');

      expect(a, isNot(b));
      expect(a, contains('__acct_user_a'));
      expect(b, contains('__acct_user_b'));
    });

    test('same auth user is deterministic across calls', () {
      expect(
        SyncAccountScope.forUser('wesios_private', 'abc123'),
        SyncAccountScope.forUser('wesios_private', 'abc123'),
      );
    });

    test('signed-out state never falls back to legacy unscoped box', () {
      final anonymous = SyncAccountScope.forUser('wesios_private', null);
      expect(anonymous, 'wesios_private__acct_anonymous');
      expect(anonymous, isNot('wesios_private'));
    });

    test('unsafe characters cannot escape Hive namespace', () {
      final value = SyncAccountScope.forUser('private box', 'user/a:b c');
      expect(value, 'private_box__acct_user_a_b_c');
    });
  });
}
