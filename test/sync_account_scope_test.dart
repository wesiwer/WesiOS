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
    test('shield and vault storage follow auth user, not employee id', () {
      final shieldA = SyncFeatureExtensions.shieldBoxName('auth_a');
      final shieldB = SyncFeatureExtensions.shieldBoxName('auth_b');
      final vaultA = SyncFeatureExtensions.vaultBoxName('auth_a');
      final vaultB = SyncFeatureExtensions.vaultBoxName('auth_b');

      expect(shieldA, 'wesios_profile_sync_v1__acct_auth_a');
      expect(shieldB, 'wesios_profile_sync_v1__acct_auth_b');
      expect(vaultA, 'wesios_vault_sync_v1__acct_auth_a');
      expect(vaultB, 'wesios_vault_sync_v1__acct_auth_b');
      expect(shieldA, isNot(shieldB));
      expect(vaultA, isNot(vaultB));
    });

    test('private wire record id still belongs to business employee', () {
      expect(
        SyncFeatureExtensions.privateRecordId('shield_hash', 'employee_42'),
        'employee_42::shield_hash',
        reason:
            'server validates private keyed rid by ctx.employeeId even though owner scope is e.auth.id',
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
      expect(source, contains('_privateSettingsAuthOwnerKey'),
          reason:
              'legacy Shield/Vault projection may only be claimed once by an auth-user namespace');
    });

    test('new client no longer registers overloaded profile_private', () {
      final source =
          File('lib/core/sync/sync_feature_extensions.dart').readAsStringSync();
      expect(source, contains("SyncCodec.byName('shield_private')"));
      expect(source, contains("String get name => 'shield_private';"));
      expect(source, isNot(contains("SyncCodec.byName('profile_private')")));
      expect(source, isNot(contains("String get name => 'profile_private';")));
    });
  });
}
