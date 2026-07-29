import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/wesi_tooltip.dart';
import '../../core/widgets/window_controls.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/services/currency_service.dart';
import '../../core/widgets/currency_picker.dart';
import '../../core/services/exchange_rate_service.dart';
import 'services/treasury_service.dart';
import 'models/transaction_model.dart';
import 'widgets/accounts_bar.dart';
import 'services/account_service.dart';
import 'models/account_model.dart';
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

  /// Выбранный счёт. null — «все счета».
  String? _accountId = AccountService.selectedId;

  /// Операции выбранного счёта: на них считается и баланс, и разрезы.
  List<TransactionModel> get _visible =>
      AccountService.filter(_transactions, _accountId);

  String get _sym => CurrencyService.symbol;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final txs = await _service.getAllTransactions();
    final anomalies = await _service.detectAnomalies();
    await AccountService.ensureMain();
    if (!mounted) return;
    setState(() {
      _transactions = txs;
      _anomalies = anomalies;
      _currency = CurrencyService.current;
      _isLoading = false;
    });
    await _recalc();
  }

  /// Баланс и разрезы считаются по ВЫБРАННОМУ счёту, а не по всей базе:
  /// иначе переключение счёта меняло бы только список операций, а цифры
  /// сверху оставались бы общими и противоречили ему.
  Future<void> _recalc() async {
    final visible = _visible;
    var income = 0.0;
    var expense = 0.0;
    for (final t in visible) {
      if (t.type == TransactionType.income) {
        income += t.amount;
      } else {
        expense += t.amount;
      }
    }

    // Начальные остатки счетов — часть баланса, но не часть оборота.
    final summaries = await AccountService.summaries(_transactions);
    var opening = 0.0;
    for (final s in summaries) {
      if (_accountId == null || s.account.id == _accountId) {
        opening += s.account.openingBalance;
      }
    }

    if (!mounted) return;
    setState(() {
      _balance = opening + income - expense;
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

  /// Выбор валюты списком (флаг, страна, название, курс) вместо перебора
  /// по кругу — по одному коду было непонятно, о какой стране речь.
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
      final tx = TransactionModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: result['title'],
        amount: result['amount'],
        type: type,
        date: DateTime.now(),
        category: result['category'],
        description: result['description'],
        isRecurring: result['isRecurring'] ?? false,
        recurringPeriod: result['recurringPeriod'],
        // В режиме «Все счета» операция уходит на основной — иначе её
        // некуда положить, а спрашивать счёт ради каждой траты навязчиво.
        accountId: _accountId ?? AccountModel.mainId,
      );
      await _service.addTransaction(tx);
      await _loadData();
    }
  }

  Future<void> _deleteTx(String id) async {
    await _service.deleteTransaction(id);
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(
              color: AppTheme.accentOrange.withOpacity(0.5)),
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentOrange,
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
          const SizedBox(height: 16),
          HoverButton(
            onTap: () => Navigator.pushNamed(context, '/treasury/forecast'),
            padding: const EdgeInsets.all(20),
            backgroundColor: AppTheme.surface,
            child: Row(
              children: [
                const Icon(Icons.trending_up, color: AppTheme.accentOrange),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    WesiLocale.get('forecast_p10_p50_p90'),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
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
                const Icon(Icons.science, color: AppTheme.accentOrange),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    WesiLocale.get('wesi_sandbox_title'),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    size: 16, color: AppTheme.textMuted),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                WesiLocale.get('recent_transactions'),
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/treasury/operations'),
                child: Text(
                  WesiLocale.isRussian ? 'Все операции →' : 'All operations →',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.accentOrange,
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
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 12),
          Text(
            '$_sym${shown.toStringAsFixed(2)}',
            style: const TextStyle(
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
                  AppTheme.accentOrange,
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
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }

  /// Реальный курс + дата ЦБ, а не только символ валюты.
  /// Подписан на revision — курс приезжает уже после старта приложения.
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
                  ? AppTheme.accentOrange.withOpacity(0.8)
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
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
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
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.textPrimary)),
                Text(tx.category ?? WesiLocale.get('uncategorized'),
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textMuted)),
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
            child: const Icon(Icons.delete_outline,
                size: 18, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
