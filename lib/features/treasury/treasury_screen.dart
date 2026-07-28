import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/wesi_tooltip.dart';
import '../../core/widgets/wesi_context_menu.dart';
import '../../core/widgets/window_controls.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/services/currency_service.dart';
import 'services/treasury_service.dart';
import 'models/transaction_model.dart';

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

  String get _sym => CurrencyService.symbol;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final txs = await _service.getAllTransactions();
    final balance = await _service.getCurrentBalance();
    final breakdown = await _service.getBalanceBreakdown();
    final anomalies = await _service.detectAnomalies();
    setState(() {
      _transactions = txs;
      _balance = balance;
      _breakdown = breakdown;
      _anomalies = anomalies;
      _currency = CurrencyService.current;
      _isLoading = false;
    });
  }

  Future<void> _cycleCurrency() async {
    final codes = CurrencyService.codes;
    final i = codes.indexOf(_currency);
    final next = codes[(i + 1) % codes.length];
    await CurrencyService.set(next);
    setState(() => _currency = next);
  }

  Future<void> _addTransaction(TransactionType type) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AddTransactionDialog(type: type, symbol: _sym),
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

    final saleLabel = WesiLocale.isRussian ? 'Продажа' : 'Sale';
    final expenseLabel = WesiLocale.isRussian ? 'Траты' : 'Expense';

    final bodyChildren = <Widget>[
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
      Text(
        WesiLocale.get('recent_transactions'),
        style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary),
      ),
      const SizedBox(height: 12),
      ..._transactions.take(20).map(_txItem),
      const SizedBox(height: 32),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: kTitleBarHeight)),
          'SliverAppBar'(
            backgroundColor: AppTheme.background.withOpacity(0.9),
            elevation: 0,
            pinned: true,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 140),
                child: GestureDetector(
                  onTap: _cycleCurrency,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
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
            ],
            title: Text(
              WesiLocale.get('wesi_treasury_title'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildListDelegate(bodyChildren),
            ),
          ),
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
        ],
      ),
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

class _AddTransactionDialog extends StatefulWidget {
  final TransactionType type;
  final String symbol;
  const _AddTransactionDialog({required this.type, required this.symbol});

  @override
  State<_AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<_AddTransactionDialog> {
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  late String _category;
  bool _isRecurring = false;
  RecurringPeriod? _recurringPeriod;

  List<String> get _categories => WesiLocale.isRussian
      ? [
          'ПО',
          'Маркетинг',
          'Офис',
          'Зарплаты',
          'Фриланс',
          'Инвестиции',
          'Инфраструктура',
          'Прочее'
        ]
      : [
          'Software',
          'Marketing',
          'Office',
          'Salaries',
          'Freelance',
          'Investments',
          'Infrastructure',
          'Other'
        ];

  @override
  void initState() {
    super.initState();
    _category = _categories.last;
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.type == TransactionType.income;
    final title = isIncome
        ? (WesiLocale.isRussian ? 'Продажа' : 'Sale')
        : (WesiLocale.isRussian ? 'Траты' : 'Expense');

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 20),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(labelText: WesiLocale.get('title')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: WesiLocale.get('amount'),
                prefixText: '${widget.symbol} ',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              dropdownColor: AppTheme.surface,
              decoration:
                  InputDecoration(labelText: WesiLocale.get('category')),
              items: _categories
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c,
                            style:
                                const TextStyle(color: AppTheme.textPrimary)),
                      ))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _category = v ?? _categories.last),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                  labelText: WesiLocale.get('description_optional')),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(WesiLocale.get('cancel'),
                        style: const TextStyle(color: AppTheme.textMuted)),
                  ),
                ),
                Expanded(
                  child: HoverButton(
                    onTap: () {
                      final amount = double.tryParse(_amountCtrl.text);
                      if (_titleCtrl.text.isNotEmpty && amount != null) {
                        final rub = CurrencyService.toRub(amount);
                        Navigator.pop(context, {
                          'title': _titleCtrl.text,
                          'amount': rub,
                          'category': _category,
                          'description': _descCtrl.text,
                          'isRecurring': _isRecurring,
                          'recurringPeriod': _recurringPeriod,
                        });
                      }
                    },
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor:
                        isIncome ? AppTheme.accentGreen : AppTheme.accentRed,
                    child: Center(
                      child: Text(WesiLocale.get('save'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
