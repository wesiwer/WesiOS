import 'package:flutter/material.dart';

import '../../../core/services/currency_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../team/services/team_service.dart';
import '../../treasury/models/account_model.dart';
import '../../treasury/services/account_service.dart';
import '../../treasury/services/treasury_service.dart';
import '../models/organization_access_grant.dart';
import '../models/organization_model.dart';
import '../services/organization_access_service.dart';
import '../services/organization_context.dart';
import '../services/organization_service.dart';

class _AccountBalanceRow {
  final AccountModel account;
  final double balance;
  const _AccountBalanceRow(this.account, this.balance);
}

class _OrganizationBalanceRow {
  final OrganizationModel organization;
  final double balance;
  final List<_AccountBalanceRow> accounts;

  const _OrganizationBalanceRow({
    required this.organization,
    required this.balance,
    required this.accounts,
  });
}

/// Canonical subtree breakdown semantics:
/// Organization -> Accounts. Transactions remain available through Treasury
/// operations/account filtering; employee rows belong exclusively to My Finance.
class SubtreeFinanceBreakdown extends StatefulWidget {
  const SubtreeFinanceBreakdown({super.key});

  @override
  State<SubtreeFinanceBreakdown> createState() => _SubtreeFinanceBreakdownState();
}

class _SubtreeFinanceBreakdownState extends State<SubtreeFinanceBreakdown> {
  Future<List<_OrganizationBalanceRow>>? _future;

  @override
  void initState() {
    super.initState();
    OrganizationContext.revision.addListener(_reload);
    AccountService.revision.addListener(_reload);
    TreasuryService.revision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    OrganizationContext.revision.removeListener(_reload);
    AccountService.revision.removeListener(_reload);
    TreasuryService.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  Future<List<_OrganizationBalanceRow>> _load() async {
    if (OrganizationContext.scope != OrganizationScope.subtree) return const [];
    var ids = await OrganizationContext.effectiveOrganizationIds();
    if (TeamService.current != null) {
      final financeIds = await OrganizationAccessService.organizationIdsFor(
        OrganizationPermissions.viewFinance,
      );
      ids = ids.intersection(financeIds);
    }
    if (ids.length <= 1) return const [];

    final transactions = await TreasuryService().getAllTransactions();
    final summaries = await AccountService.summaries(
      transactions,
      organizationIds: ids,
    );
    final organizations = {
      for (final org in await OrganizationService.all()) org.id: org,
    };
    final byOrg = <String, List<_AccountBalanceRow>>{};
    for (final summary in summaries) {
      final orgId = summary.account.effectiveOrganizationId;
      if (!ids.contains(orgId)) continue;
      (byOrg[orgId] ??= []).add(
        _AccountBalanceRow(summary.account, summary.balance),
      );
    }

    final rows = <_OrganizationBalanceRow>[];
    for (final id in ids) {
      final org = organizations[id];
      if (org == null) continue;
      final accounts = byOrg[id] ?? <_AccountBalanceRow>[];
      accounts.sort((a, b) => a.account.createdAt.compareTo(b.account.createdAt));
      rows.add(_OrganizationBalanceRow(
        organization: org,
        balance: accounts.fold(0, (sum, row) => sum + row.balance),
        accounts: accounts,
      ));
    }
    rows.sort((a, b) {
      if (a.organization.id == OrganizationContext.currentOrganizationId) return -1;
      if (b.organization.id == OrganizationContext.currentOrganizationId) return 1;
      final order = a.organization.sortOrder.compareTo(b.organization.sortOrder);
      return order != 0
          ? order
          : a.organization.name.compareTo(b.organization.name);
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    if (OrganizationContext.scope != OrganizationScope.subtree) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<List<_OrganizationBalanceRow>>(
      future: _future,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <_OrganizationBalanceRow>[];
        if (snapshot.connectionState != ConnectionState.done && rows.isEmpty) {
          return const SizedBox.shrink();
        }
        if (rows.length <= 1) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.account_tree_outlined,
                      size: 18, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Организации → счета',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Персональные строки сотрудников находятся только в «Мои финансы». Операции открываются через фильтр счёта/список операций.',
                style: TextStyle(
                    color: AppTheme.textMuted, fontSize: 10.5, height: 1.35),
              ),
              const SizedBox(height: 10),
              for (final row in rows) _row(row),
              const SizedBox(height: 8),
              Text(
                'Внутренние межорганизационные переводы видны локально в узлах, но исключаются из консолидированных gross KPI и forecast поддерева.',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  height: 1.35,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(_OrganizationBalanceRow row) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 22, bottom: 6),
        title: Text(
          row.organization.name,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        trailing: Text(
          CurrencyService.format(row.balance),
          style: TextStyle(
            color: row.balance >= 0 ? AppTheme.accentGreen : AppTheme.accentRed,
            fontWeight: FontWeight.w800,
          ),
        ),
        children: row.accounts.isEmpty
            ? [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Счетов нет',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                ),
              ]
            : [
                for (final account in row.accounts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${account.account.name} • ${account.account.currency}',
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 11.5),
                          ),
                        ),
                        Text(
                          CurrencyService.format(account.balance),
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
      );
}
