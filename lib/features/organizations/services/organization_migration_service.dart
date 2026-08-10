import 'package:hive_flutter/hive_flutter.dart';

import '../../treasury/models/account_model.dart';
import '../../treasury/models/transaction_model.dart';
import '../models/organization_model.dart';
import 'organization_access_service.dart';
import 'organization_context.dart';
import 'organization_service.dart';

class OrganizationMigrationService {
  OrganizationMigrationService._();

  static const String logBoxName = 'wesios_org_migration_log';
  static const String migrationKey = 'org_hierarchy_v1';
  static const String accountBoxName = 'wesios_accounts';
  static const String treasuryBoxName = 'wesios_treasury';

  static Future<void> runV1() async {
    await OrganizationService.ensureBaseline(createdBy: 'migration:v1');
    final log = await Hive.openBox<dynamic>(logBoxName);
    final completed = log.get(migrationKey) is Map &&
        (log.get(migrationKey) as Map)['completed'] == true;

    var accountsUpdated = 0;
    var transactionsUpdated = 0;
    if (!completed) {
      final accounts = await Hive.openBox<AccountModel>(accountBoxName);
      for (final key in accounts.keys.toList()) {
        final account = accounts.get(key);
        if (account == null || account.organizationId != null) continue;
        await accounts.put(
          key,
          account.copyWith(organizationId: OrganizationModel.wesiBeatsId),
        );
        accountsUpdated++;
      }

      final treasury = await Hive.openBox<TransactionModel>(treasuryBoxName);
      for (final key in treasury.keys.toList()) {
        final tx = treasury.get(key);
        if (tx == null || tx.organizationId != null) continue;
        await treasury.put(
          key,
          tx.copyWith(organizationId: OrganizationModel.wesiBeatsId),
        );
        transactionsUpdated++;
      }

      await log.put(migrationKey, <String, dynamic>{
        'completed': true,
        'completedAt': DateTime.now().toIso8601String(),
        'rootId': OrganizationModel.rootId,
        'legacyOrganizationId': OrganizationModel.wesiBeatsId,
        'accountsUpdated': accountsUpdated,
        'transactionsUpdated': transactionsUpdated,
      });
    }

    // These are deliberately safe to run every launch: a new employee added
    // after migration still needs a default Wesi Beats grant.
    await OrganizationAccessService.ensureLegacyGrants();
    await OrganizationContext.initialize();
  }
}
