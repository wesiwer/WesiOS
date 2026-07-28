import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/wesi_tooltip.dart';
import '../../core/widgets/wesi_context_menu.dart';
import '../../core/localization/wesi_locale.dart';
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _service.generateDemoData();
    final txs = await _service.getAllTransactions();
    final balance = await _service.getCurrentBalance();
    final breakdown = await _service.getBalanceBreakdown();
    final anomalies = await _service.detectAnomalies();

    setState(() {
      _transactions = txs;
      _balance = balance;
      _breakdown = breakdown;
      _anomalies = anomalies;
      _isLoading = false;
    });
  }

  Future<void> _addTransaction(TransactionType type) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AddTransactionDialog(type: type),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.accentOrange.withOpacity(0.5)),
              const SizedBox(height: 16),
              Text(WesiLocale.get('loading_treasury'), style: const TextStyle(color: AppTheme.textMuted)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppTheme.background.withOpacity(0.9),
            elevation: 0,
            pinned: true,
            expandedHeight: 140,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                WesiLocale.get('wesi_treasury_title'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppTheme.carbonDark.withOpacity(0.6), AppTheme.background],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildBalanceCard(),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: WesiTooltip(
                        message: WesiLocale.get('record_income'),
                        child: _buildActionButton(
                          icon: Icons.add_circle,
                          label: WesiLocale.get('total_income'),
                          color: AppTheme.accentGreen,
                          onTap: () => _addTransaction(TransactionType.income),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: WesiTooltip(
                        message: WesiLocale.get('record_expense'),
                        child: _buildActionButton(
                          icon: Icons.remove_circle,
                          label: WesiLocale.get('total_expenses'),
                          color: AppTheme.accentRed,
                          onTap: () => _addTransaction(TransactionType.expense),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                WesiContextMenu(
                  title: WesiLocale.get('wesi_forecast_title'),
                  description: WesiLocale.get('wesi_forecast_desc'),
                  purpose: WesiLocale.get('wesi_forecast_purpose'),
                  children: [
                    HoverButton(
                      onTap: () => Navigator.pushNamed(context, '/treasury/forecast'),
                      padding: const EdgeInsets.all(20),
                      backgroundColor: AppTheme.surface,
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppTheme.accentOrange.withOpacity(0.3), AppTheme.accentOrange.withOpacity(0.1)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.accentOrange.withOpacity(0.3)),
                            ),
                            child: const Icon(Icons.trending_up, color: AppTheme.accentOrange),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  WesiLocale.get('forecast_p10_p50_p90'),
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  WesiLocale.get('monte_carlo_analysis'),
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textMuted),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _buildStatCard(
                      WesiLocale.get('total_income'),
                      '\$${_breakdown['income']?.toStringAsFixed(0) ?? '0'}',
                      AppTheme.accentGreen,
                      Icons.arrow_upward,
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      WesiLocale.get('total_expenses'),
                      '\$${_breakdown['expense']?.toStringAsFixed(0) ?? '0'}',
                      AppTheme.accentRed,
                      Icons.arrow_downward,
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      WesiLocale.get('net'),
                      '\$${_breakdown['net']?.toStringAsFixed(0) ?? '0'}',
                      _breakdown['net'] != null && _breakdown['net']! >= 0 ? AppTheme.accentGreen : AppTheme.accentRed,
                      Icons.account_balance,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (_anomalies.isNotEmpty) ...[
                  _buildAnomaliesCard(),
                  const SizedBox(height: 24),
                ],
                _buildSectionTitle(WesiLocale.get('recent_transactions')),
                const SizedBox(height: 12),
                ..._transactions.take(10).map((tx) => _buildTransactionItem(tx)),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.carbonDark.withOpacity(0.8), AppTheme.surface.withOpacity(0.5)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _balance >= 0 ? AppTheme.accentGreen.withOpacity(0.2) : AppTheme.accentRed.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (_balance >= 0 ? AppTheme.accentGreen : AppTheme.accentRed).withOpacity(0.05),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            WesiLocale.get('current_balance'),
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            '\$${_balance.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: _balance >= 0 ? AppTheme.textPrimary : AppTheme.accentRed,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (_breakdown['net'] != null && _breakdown['net']! >= 0
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFFF87171)).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_breakdown['net'] != null && _breakdown['net']! >= 0 ? '+' : ''}${_breakdown['net']?.toStringAsFixed(1) ?? '0'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _breakdown['net'] != null && _breakdown['net']! >= 0
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFFF87171),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                WesiLocale.get('net').toLowerCase(),
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return HoverButton(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16),
      backgroundColor: AppTheme.surface.withOpacity(0.3),
      hoverColor: color.withOpacity(0.1),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.glassBorder, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildAnomaliesCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.accentRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accentRed.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: AppTheme.accentRed.withOpacity(0.8), size: 18),
              const SizedBox(width: 8),
              Text(
                '${WesiLocale.get('anomalies_detected')}: ${_anomalies.length}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.accentRed.withOpacity(0.9)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._anomalies.map((a) => Padding(
            padding: const EdgeInsets.only(left: 26, top: 4),
            child: Text(
              '${a.title}: \$${a.amount.toStringAsFixed(0)} (Z: ${a.zScore?.toStringAsFixed(1)})',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withOpacity(0.8)),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(TransactionModel tx) {
    final isIncome = tx.type == TransactionType.income;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tx.isAnomaly ? AppTheme.accentRed.withOpacity(0.05) : AppTheme.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: tx.isAnomaly ? AppTheme.accentRed.withOpacity(0.2) : AppTheme.glassBorder,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isIncome ? AppTheme.accentGreen.withOpacity(0.15) : AppTheme.accentRed.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(isIncome ? Icons.arrow_upward : Icons.arrow_downward,
                color: isIncome ? AppTheme.accentGreen : AppTheme.accentRed, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(tx.category ?? WesiLocale.get('uncategorized'), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isIncome ? '+' : '-'}\$${tx.amount.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isIncome ? AppTheme.accentGreen : AppTheme.accentRed),
              ),
              if (tx.isAnomaly)
                Text(
                  WesiLocale.get('anomaly'),
                  style: TextStyle(fontSize: 9, color: AppTheme.accentRed.withOpacity(0.7), fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary, letterSpacing: 0.3),
    );
  }
}

class _AddTransactionDialog extends StatefulWidget {
  final TransactionType type;
  const _AddTransactionDialog({required this.type});

  @override
  State<_AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<_AddTransactionDialog> {
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = 'Other';
  bool _isRecurring = false;
  RecurringPeriod? _recurringPeriod;

  final List<String> _categories = [
    'Software', 'Marketing', 'Office', 'Salaries',
    'Freelance', 'Investments', 'Infrastructure', 'Other'
  ];

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.type == TransactionType.income;
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
            Text(
              isIncome ? WesiLocale.get('total_income') : WesiLocale.get('total_expenses'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: WesiLocale.get('title'),
                hintText: isIncome ? 'e.g. Client Payment' : 'e.g. Office Supplies',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: WesiLocale.get('amount'),
                hintText: '0.00',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 12),
            _buildCategoryDropdown(),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: WesiLocale.get('description_optional'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: _isRecurring,
                  onChanged: (v) => setState(() => _isRecurring = v ?? false),
                  activeColor: AppTheme.accentOrange,
                ),
                Text(
                  WesiLocale.get('recurring_payment'),
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
            if (_isRecurring) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: RecurringPeriod.values.map((p) {
                  final isSelected = _recurringPeriod == p;
                  return ChoiceChip(
                    label: Text(p.name),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _recurringPeriod = p),
                    selectedColor: AppTheme.accentOrange.withOpacity(0.2),
                    labelStyle: TextStyle(
                      color: isSelected ? AppTheme.accentOrange : AppTheme.textSecondary,
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(WesiLocale.get('cancel'), style: const TextStyle(color: AppTheme.textMuted)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: HoverButton(
                    onTap: () {
                      final amount = double.tryParse(_amountCtrl.text);
                      if (_titleCtrl.text.isNotEmpty && amount != null) {
                        Navigator.pop(context, {
                          'title': _titleCtrl.text,
                          'amount': amount,
                          'category': _category,
                          'description': _descCtrl.text,
                          'isRecurring': _isRecurring,
                          'recurringPeriod': _recurringPeriod,
                        });
                      }
                    },
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: isIncome ? AppTheme.accentGreen : AppTheme.accentRed,
                    child: Center(
                      child: Text(
                        WesiLocale.get('save'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
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

  Widget _buildCategoryDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _category,
          isExpanded: true,
          dropdownColor: AppTheme.surface,
          style: const TextStyle(color: AppTheme.textPrimary),
          items: _categories.map((c) => DropdownMenuItem(
            value: c,
            child: Text(c, style: const TextStyle(color: AppTheme.textPrimary)),
          )).toList(),
          onChanged: (v) => setState(() => _category = v ?? 'Other'),
        ),
      ),
    );
  }
}
