import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hover_button.dart';
import '../../../core/widgets/wesi_tooltip.dart';
import '../../../core/localization/wesi_locale.dart';
import 'services/sandbox_service.dart';
import 'models/transaction_model.dart';

/// Wesi Sandbox — изолированная среда для тестирования финансовых сценариев.
class SandboxScreen extends StatefulWidget {
  const SandboxScreen({super.key});

  @override
  State<SandboxScreen> createState() => _SandboxScreenState();
}

class _SandboxScreenState extends State<SandboxScreen> {
  final SandboxService _service = SandboxService();
  List<TransactionModel> _transactions = [];
  double _balance = 0;
  Map<String, double> _breakdown = {};
  List<TransactionModel> _anomalies = [];
  bool _isLoading = true;
  String _currentScenario = WesiLocale.get('scenario');

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
      _isLoading = false;
    });
  }

  Future<void> _runScenario(String scenario) async {
    setState(() => _isLoading = true);
    switch (scenario) {
      case 'startup':
        await _service.generateStartupScenario();
        _currentScenario = 'Startup Seed Round';
        break;
      case 'freelancer':
        await _service.generateFreelancerScenario();
        _currentScenario = 'Freelancer Lifestyle';
        break;
      case 'crisis':
        await _service.generateCrisisScenario();
        _currentScenario = 'Crisis Mode';
        break;
      case 'clone':
        await _service.cloneFromReal();
        _currentScenario = 'Cloned from Real Data';
        break;
      case 'clear':
        await _service.clearAll();
        _currentScenario = WesiLocale.get('scenario');
        break;
    }
    await _loadData();
  }

  Future<void> _addTransaction(TransactionType type) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AddSandboxTransactionDialog(type: type),
    );

    if (result != null) {
      final tx = TransactionModel(
        id: 'sandbox_\${DateTime.now().millisecondsSinceEpoch}',
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
      return _buildLoadingScreen();
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildSandboxBanner(),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  backgroundColor: AppTheme.background.withOpacity(0.9),
                  elevation: 0,
                  pinned: true,
                  expandedHeight: 120,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(
                      WesiLocale.get('wesi_sandbox_title'),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2),
                    ),
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [const Color(0xFF2D1F00).withOpacity(0.6), AppTheme.background],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(24),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildScenarioSelector(),
                      const SizedBox(height: 24),
                      _buildBalanceCard(),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: WesiTooltip(
                              message: WesiLocale.get('add_test_income'),
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
                              message: WesiLocale.get('add_test_expense'),
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
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          _buildStatCard(WesiLocale.get('total_income'), '\$${_breakdown['income']?.toStringAsFixed(0) ?? '0'}', AppTheme.accentGreen),
                          const SizedBox(width: 12),
                          _buildStatCard(WesiLocale.get('total_expenses'), '\$${_breakdown['expense']?.toStringAsFixed(0) ?? '0'}', AppTheme.accentRed),
                          const SizedBox(width: 12),
                          _buildStatCard(WesiLocale.get('net'), '\$${_breakdown['net']?.toStringAsFixed(0) ?? '0'}',
                              _breakdown['net'] != null && _breakdown['net']! >= 0 ? AppTheme.accentGreen : AppTheme.accentRed),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (_anomalies.isNotEmpty) ...[
                        _buildAnomaliesCard(),
                        const SizedBox(height: 24),
                      ],
                      _buildSectionTitle('${WesiLocale.get('sandbox_transactions')} (${_transactions.length})'),
                      const SizedBox(height: 12),
                      ..._transactions.take(10).map((tx) => _buildTransactionItem(tx)),
                      const SizedBox(height: 32),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentOrange.withOpacity(0.5)),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              WesiLocale.get('wesi_sandbox_title'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.textPrimary, letterSpacing: 3),
            ),
            const SizedBox(height: 8),
            Text(
              WesiLocale.get('loading_sandbox'),
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSandboxBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF4D3D00).withOpacity(0.8), const Color(0xFF2D1F00).withOpacity(0.6)],
        ),
        border: Border(bottom: BorderSide(color: AppTheme.accentOrange.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accentOrange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.accentOrange.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.science, size: 14, color: AppTheme.accentOrange),
                const SizedBox(width: 6),
                Text(
                  WesiLocale.get('sandbox_mode'),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.accentOrange, letterSpacing: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              '${WesiLocale.get('scenario')}: $_currentScenario • ${WesiLocale.get('data_isolated')} • ${WesiLocale.get('no_impact')}',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted.withOpacity(0.8)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.textMuted),
            onPressed: () => _runScenario('clear'),
            tooltip: WesiLocale.get('clear_sandbox'),
          ),
        ],
      ),
    );
  }

  Widget _buildScenarioSelector() {
    final scenarios = [
      ('startup', 'Startup', Icons.rocket_launch, 'Seed round + burn rate + MRR'),
      ('freelancer', 'Freelancer', Icons.laptop_mac, 'Irregular income + expenses'),
      ('crisis', 'Crisis', Icons.warning, 'Multiple anomalies + emergencies'),
      ('clone', 'Clone Real', Icons.copy_all, 'Copy from real Treasury data'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          WesiLocale.get('quick_scenarios'),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: scenarios.map((s) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _runScenario(s.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 160,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppTheme.surface.withOpacity(0.5), AppTheme.surface.withOpacity(0.2)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.accentOrange.withOpacity(0.2), width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(s.$3, size: 24, color: AppTheme.accentOrange.withOpacity(0.8)),
                        const SizedBox(height: 10),
                        Text(s.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                        const SizedBox(height: 4),
                        Text(s.$4, style: TextStyle(fontSize: 10, color: AppTheme.textMuted.withOpacity(0.8), height: 1.3)),
                      ],
                    ),
                  ),
                ),
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF2D1F00).withOpacity(0.5), AppTheme.surface.withOpacity(0.3)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accentOrange.withOpacity(0.2), width: 1),
        boxShadow: [BoxShadow(color: AppTheme.accentOrange.withOpacity(0.03), blurRadius: 20, spreadRadius: 2)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                WesiLocale.get('sandbox_balance'),
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, letterSpacing: 0.5),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accentOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  WesiLocale.get('test'),
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppTheme.accentOrange.withOpacity(0.8), letterSpacing: 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '\$${_balance.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.5),
          ),
          const SizedBox(height: 8),
          Text(
            '${_transactions.length} ${WesiLocale.isRussian ? 'транзакций' : 'transactions'} ${WesiLocale.isRussian ? 'в песочнице' : 'in sandbox'}',
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
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

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            const SizedBox(height: 6),
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
        color: AppTheme.accentRed.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accentRed.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: AppTheme.accentRed.withOpacity(0.7), size: 16),
              const SizedBox(width: 8),
              Text(
                '${WesiLocale.get('anomalies_detected')}: ${_anomalies.length}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accentRed.withOpacity(0.8)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._anomalies.map((a) => Text(
            '• ${a.title}: \$${a.amount.toStringAsFixed(0)} (Z: ${a.zScore?.toStringAsFixed(1)})',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withOpacity(0.7)),
          )),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(TransactionModel tx) {
    final isIncome = tx.type == TransactionType.income;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tx.isAnomaly ? AppTheme.accentRed.withOpacity(0.04) : AppTheme.surface.withOpacity(0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tx.isAnomaly ? AppTheme.accentRed.withOpacity(0.15) : AppTheme.glassBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isIncome ? AppTheme.accentGreen.withOpacity(0.12) : AppTheme.accentRed.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(isIncome ? Icons.arrow_upward : Icons.arrow_downward,
                color: isIncome ? AppTheme.accentGreen : AppTheme.accentRed, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                Text(tx.category ?? WesiLocale.get('uncategorized'), style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
              ],
            ),
          ),
          Text(
            '${isIncome ? '+' : '-'}\$${tx.amount.toStringAsFixed(0)}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isIncome ? AppTheme.accentGreen : AppTheme.accentRed),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary, letterSpacing: 0.3));
  }
}

class _AddSandboxTransactionDialog extends StatefulWidget {
  final TransactionType type;
  const _AddSandboxTransactionDialog({required this.type});

  @override
  State<_AddSandboxTransactionDialog> createState() => _AddSandboxTransactionDialogState();
}

class _AddSandboxTransactionDialogState extends State<_AddSandboxTransactionDialog> {
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = 'Test';
  final List<String> _categories = ['Test', 'Simulation', 'Scenario', 'Experiment', 'Other'];

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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.science, size: 20, color: AppTheme.accentOrange),
                ),
                const SizedBox(width: 12),
                Text(
                  isIncome ? WesiLocale.get('add_test_income') : WesiLocale.get('add_test_expense'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              WesiLocale.get('only_in_sandbox'),
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: WesiLocale.get('title'),
                hintText: isIncome ? 'e.g. Test Client Payment' : 'e.g. Test Expense',
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
            Container(
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
                  onChanged: (v) => setState(() => _category = v ?? 'Test'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(labelText: WesiLocale.get('description_optional')),
            ),
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
                        });
                      }
                    },
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: isIncome ? AppTheme.accentGreen : AppTheme.accentRed,
                    child: Center(
                      child: Text(
                        WesiLocale.get('add_to_sandbox'),
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
}
