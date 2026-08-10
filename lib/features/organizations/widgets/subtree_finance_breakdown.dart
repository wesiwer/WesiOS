import 'package:flutter/material.dart';

import '../../../core/services/currency_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../treasury/services/account_service.dart';
import '../../treasury/services/treasury_service.dart';
import '../models/organization_model.dart';
import '../services/organization_context.dart';
import '../services/organization_service.dart';

class _OrganizationBalanceRow {
  final OrganizationModel organization;
  final double balance;
  final double income;
  final double expense;

  const _OrganizationBalanceRow({
    required this.organization,
    required this.balance,
    required this.income,
    required this.expense,
  });
}

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
    final ids = await OrganizationContext.effectiveOrganizationIds();
    if (ids.length <= 1) return const [];
    final transactions = await TreasuryService().getAllTransactions();
    final summaries = await AccountService.summaries(transactions);
    final organizations = {
      for (final org in await OrganizationService.all()) org.id: org,
    };
    final balance = <String, double>{};
    final income = <String, double>{};
    final expense = <String, double>{};
    for (final summary in summaries) {
      final id = summary.account.effectiveOrganizationId;
      if (!ids.contains(id)) continue;
      balance[id] = (balance[id] ?? 0) + summary.balance;
      income[id] = (income[id] ?? 0) + summary.income;
      expense[id] = (expense[id] ?? 0) + summary.expense;
    }
    final rows = <_OrganizationBalanceRow>[];
    for (final id in ids) {
      final org = organizations[id];
      if (org == null) continue;
      rows.add(_OrganizationBalanceRow(
        organization: org,
        balance: balance[id] ?? 0,
        income: income[id] ?? 0,
        expense: expense[id] ?? 0,
      ));
    }
    rows.sort((a, b) {
      if (a.organization.id == OrganizationContext.currentOrganizationId) return -1;
      if (b.organization.id == OrganizationContext.currentOrganizationId) return 1;
      final byOrder = a.organization.sortOrder.compareTo(b.organization.sortOrder);
      return byOrder != 0
          ? byOrder
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
                  Icon(Icons.account_tree_outlined, size: 18, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Text(
                    'По организациям',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          row.organization.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          CurrencyService.format(row.balance),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: row.balance >= 0
                                ? AppTheme.accentGreen
                                : AppTheme.accentRed,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Межорганизационные переводы отражаются в каждом узле, но не удваивают консолидированный прогноз и KPI поддерева.',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
