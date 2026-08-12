import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/wesi_tooltip.dart';
import '../../core/widgets/window_controls.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/services/currency_service.dart';
import '../../core/widgets/currency_picker.dart';
import '../../core/services/exchange_rate_service.dart';
import '../organizations/services/organization_context.dart';
import '../organizations/widgets/organization_switcher.dart';
import '../organizations/widgets/subtree_finance_breakdown.dart';
import 'services/treasury_service.dart';
import 'models/transaction_model.dart';
import 'widgets/accounts_bar.dart';
import 'services/account_service.dart';
import 'widgets/add_transaction_dialog.dart';
import '../../core/widgets/wesi_wordmark.dart';

class TreasuryScreen extends StatefulWidget {
  const TreasuryScreen({super.key});

  @override
  State<TreasuryScreen> createState() => _TreasuryScreenState();
}

class _TreasuryScreenState extends State<TreasuryScreen> {
  final TreasuryService _service = TreasuryService();
  List<TransactionModel> _transactions = [];
  double _balance = 0;
  Map<String, double> _breakdown = {};
  List<TransactionModel> _anomalies = [];
  bool _isLoading = true;
  String _currency = CurrencyService.current;

  String? _accountId = AccountService.selectedId;

  List<TransactionModel> get _visible =>
      AccountService.filter(_transactions, _accountId);

  String get _sym => CurrencyService.symbol;

  @override
  void initState() {
    super.initState();
    OrganizationContext.revision.addListener(_onOrganizationContextChanged);
    _loadData();
  }

  @override
  void dispose() {
    OrganizationContext.revision.removeListener(_onOrganizationContextChanged);
    super.dispose();
  }

  void _onOrganizationContextChanged() {
    _accountId = AccountService.selectedId;
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    await OrganizationContext.initialize();
    final txs = await _service.getAllTransactions();
    final anomalies = await _service.detectAnomalies();
    await AccountService.ensureMain();
    if (!mounted) return;
    setState(() {
      _transactions = txs;
      _anomalies = anomalies;
      _currency = CurrencyService.current;
      _accountId = AccountService.selectedId;
      _isLoading = false;
    });
    await _recalc();
  }

  Future<void> _recalc() async {
    final visible = _visible;
    // In subtree aggregate mode, internal organization legs remain visible in
    // operation history but must not inflate gross income/expense KPIs.
    final forTotals = OrganizationContext.scope == OrganizationScope.subtree &&
            _accountId == null
        ? TreasuryService.eliminateInternalTransfers(visible)
        : visible;
    var income = 0.0;
    var expense = 0.0;
    for (final t in forTotals) {
      if (t.isRecurring) continue;
      if (t.type == TransactionType.income) {
        income += t.amount;
      } else {
        expense += t.amount;
      }
    }

    final summaries = await AccountService.summaries(_transactions);
    var opening = 0.0;
    for (final s in summaries) {
      if (_accountId == null || s.account.id == _accountId) {
        opening += s.account.openingBalance;
      }
    }

    if (!mounted) return;
    setState(() {
      _balance = opening +
          visible.where((t) => !t.isRecurring).fold<double>(
              0,
              (sum, t) => sum +
                  (t.type == TransactionType.income ? t.amount : -t.amount));
      _breakdown = {
        'income': income,
        'expense': expense,
        'net': income - expense,
      };
    });
  }

  Future<void> _selectAccount(String? id) async {
    setState(() => _accountId = id);
    await AccountService.select(id);
    await _recalc();
  }

  Future<void> _cycleCurrency() async {
    final picked = await CurrencyPicker.show(context);
    if (picked == null) return;
    await CurrencyService.set(picked);
    if (mounted) setState(() => _currency = picked);
  }

  Future<void> _addTransaction(TransactionType type) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AddTransactionDialog(type: type, symbol: _sym),
    );
    if (result != null) {
      final main = await AccountService.ensureMain();
      final reportingAmount = result['amount'] as double;
      final tx = TransactionModel(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: result['title'] as String,
        amount: reportingAmount,
        type: type,
        date: result['date'] as DateTime? ?? DateTime.now(),
        category: result['category'] as String?,
        description: result['description'] as String?,
        isRecurring: result['isRecurring'] as bool? ?? false,
        recurringPeriod: result['recurringPeriod'] as RecurringPeriod?,
        accountId: _accountId ?? main.id,
        organizationId: OrganizationContext.currentOrganizationId,
        ownerEmployeeId: result['ownerEmployeeId'] as String?,
        originalAmount: CurrencyService.fromRub(reportingAmount),
        originalCurrency: CurrencyService.current.toUpperCase(),
        fxRateToReporting: CurrencyService.rateToRub(CurrencyService.current),
        fxRateAt: result['date'] as DateTime? ?? DateTime.now(),
        fxSource: 'CurrencyService',
      );
      await _service.addTransaction(tx);
      await _loadData();
    }
  }

  Future<void> _deleteTx(String id) async {
    try {
      await _service.deleteTransaction(id);
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(
              color: AppTheme.accent.withOpacity(0.5)),
        ),
      );
    }

    final saleLabel = WesiLocale.isRussian ? 'Доход' : 'Income';
    final expenseLabel = WesiLocale.isRussian ? 'Траты' : 'Expense';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: WesiTitle(WesiLocale.get('wesi_treasury_title'), size: 18),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: OrganizationSwitcher(compact: true)),
          ),
          IconButton(
            tooltip: WesiLocale.isRussian ? 'Мои финансы' : 'My finance',
            onPressed: () => Navigator.pushNamed(context, '/my-finance'),
            icon: const Icon(Icons.person_pin_circle_outlined),
          ),
          IconButton(
            tooltip: WesiLocale.isRussian ? 'Организации' : 'Organizations',
            onPressed: () => Navigator.pushNamed(context, '/organizations'),
            icon: const Icon(Icons.account_tree_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 140),
            child: Center(
              child: GestureDetector(
                onTap: _cycleCurrency,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.glassBorder),
                  ),
                  child: Text(
                    '$_sym ${_currency.toUpperCase()}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(24, kHasCustomTitleBar ? 8 : 24, 24, 32),
        children: [
          AccountsBar(
            transactions: _transactions,
            selectedId: _accountId,
            onSelect: _selectAccount,
          ),
          const SizedBox(height: 16),
          _balanceCard(),
          if (OrganizationContext.scope == OrganizationScope.subtree) ...[
            const SizedBox(height: 16),
            const SubtreeFinanceBreakdown(),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: WesiTooltip(
                  message: WesiLocale.get('record_income'),
                  child: _actionBtn(
                    Icons.add_circle,
                    saleLabel,
                    AppTheme.accentGreen,
                    () => _addTransaction(TransactionType.income),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: WesiTooltip(
                  message: WesiLocale.get('record_expense'),
                  child: _actionBtn(
                    Icons.remove_circle,
                    expenseLabel,
                    AppTheme.accentRed,
                    () => _addTransaction(TransactionType.expense),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          HoverButton(
            onTap: () => Navigator.pushNamed(context, '/organizations/transfer'),
            padding: const EdgeInsets.all(18),
            backgroundColor: AppTheme.surface,
            child: Row(
              children: [
                Icon(Icons.swap_horiz_rounded, color: AppTheme.accent),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    WesiLocale.isRussian
                        ? 'Межорганизационный перевод'
                        : 'Inter-organization transfer',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary),
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    size: 16, color: AppTheme.textMuted),
              ],
            ),
          ),
          const SizedBox(height: 12),
          HoverButton(
            onTap: () => Navigator.pushNamed(context, '/treasury/forecast'),
            padding: const EdgeInsets.all(20),
            backgroundColor: AppTheme.surface,
            child: Row(
              children: [
                Icon(Icons.trending_up, color: AppTheme.accent),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    WesiLocale.get('forecast_p10_p50_p90'),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary),
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    size: 16, color: AppTheme.textMuted),
              ],
            ),
          ),
          const SizedBox(height: 12),
          HoverButton(
            onTap: () => Navigator.pushNamed(context, '/treasury/sandbox'),
            padding: const EdgeInsets.all(20),
            backgroundColor: AppTheme.surface,
            child: Row(
              children: [
                Icon(Icons.science, color: AppTheme.accent),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    WesiLocale.get('wesi_sandbox_title'),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary),
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    size: 16, color: AppTheme.textMuted),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                WesiLocale.get('recent_transactions'),
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () =>
                    Navigator.pushNamed(context, '/treasury/operations'),
                child: Text(
                  WesiLocale.isRussian ? 'Все операции →' : 'All operations →',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._visible.take(20).map(_txItem),
        ],
      ),
    );
  }

  Widget _balanceCard() {
    final shown = CurrencyService.fromRub(_balance);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(WesiLocale.get('current_balance'),
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 12),
          Text(
            '$_sym${shown.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          _rateLine(),
          const SizedBox(height: 14),
          Row(
            children: [
              _miniStat(
                WesiLocale.get('total_income'),
                CurrencyService.format(_breakdown['income'] ?? 0),
                AppTheme.accentGreen,
              ),
              const SizedBox(width: 10),
              _miniStat(
                WesiLocale.get('total_expenses'),
                CurrencyService.format(_breakdown['expense'] ?? 0),
                AppTheme.accentRed,
              ),
              if (_anomalies.isNotEmpty) ...[
                const SizedBox(width: 10),
                _miniStat(
                  WesiLocale.get('anomalies_detected'),
                  '${_anomalies.length}',
                  AppTheme.accent,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(fontSize: 10, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _rateLine() {
    return ValueListenableBuilder<int>(
      valueListenable: ExchangeRateService.revision,
      builder: (context, _, __) {
        final rate = ExchangeRateService.currentRateLabel;
        if (rate == null) return const SizedBox.shrink();
        final date = ExchangeRateService.rateDateLabel;
        final prefix = ExchangeRateService.usingFallback
            ? WesiLocale.get('rate_fallback')
            : '${WesiLocale.get('rate_cbr_on')} ${date ?? ''}'.trim();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '$rate · $prefix',
            style: TextStyle(
              fontSize: 11,
              color: ExchangeRateService.usingFallback
                  ? AppTheme.accent.withOpacity(0.8)
                  : AppTheme.textMuted,
            ),
          ),
        );
      },
    );
  }

  Widget _actionBtn(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return HoverButton(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16),
      backgroundColor: AppTheme.surface.withOpacity(0.3),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _txItem(TransactionModel tx) {
    final isIncome = tx.type == TransactionType.income;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(
        children: [
          Icon(isIncome ? Icons.arrow_upward : Icons.arrow_downward,
              color: isIncome ? AppTheme.accentGreen : AppTheme.accentRed),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.title,
                    style: TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
                Text(tx.category ?? WesiLocale.get('uncategorized'),
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
          ),
          Text(
            '${isIncome ? '+' : '-'}$_sym${CurrencyService.fromRub(tx.amount).toStringAsFixed(0)}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isIncome ? AppTheme.accentGreen : AppTheme.accentRed,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _deleteTx(tx.id),
            child:
                Icon(Icons.delete_outline, size: 18, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
