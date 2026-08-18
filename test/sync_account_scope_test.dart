import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/sync/sync_account_scope.dart';
import 'package:wesios/core/sync/sync_feature_extensions.dart';

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

  group('feature private boxes', () {
    test('profile and vault storage follows auth user, not employee id', () {
      final profileA = SyncFeatureExtensions.profileBoxName('auth_a');
      final profileB = SyncFeatureExtensions.profileBoxName('auth_b');
      final vaultA = SyncFeatureExtensions.vaultBoxName('auth_a');
      final vaultB = SyncFeatureExtensions.vaultBoxName('auth_b');

      expect(profileA, 'wesios_profile_sync_v1__acct_auth_a');
      expect(profileB, 'wesios_profile_sync_v1__acct_auth_b');
      expect(vaultA, 'wesios_vault_sync_v1__acct_auth_a');
      expect(vaultB, 'wesios_vault_sync_v1__acct_auth_b');
      expect(profileA, isNot(profileB));
      expect(vaultA, isNot(vaultB));
    });

    test('private wire record id still belongs to business employee', () {
      expect(
        SyncFeatureExtensions.privateRecordId('avatar_custom', 'employee_42'),
        'employee_42::avatar_custom',
        reason:
            'server validates rid by ctx.employeeId even though owner scope is e.auth.id',
      );
    });

    test('binding tracks auth user and clears legacy private boxes', () {
      final source =
          File('lib/core/sync/sync_feature_extensions.dart').readAsStringSync();

      expect(source, contains('static String? _boundAuthUserId;'));
      expect(source, contains('SyncAccountScope.currentUserId'));
      expect(source, contains('_migrateLegacyPrivateBox'));
      expect(source, contains('await legacy.clear();'),
          reason:
              'old employee-scoped private data must not remain after migration');
      expect(
        source,
        contains('_boundAuthUserId == authUserId'),
        reason:
            'same employee with a different auth user must force a fresh binding',
      );
    });
  });
}
