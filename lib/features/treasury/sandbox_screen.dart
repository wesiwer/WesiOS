import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/window_controls.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/services/currency_service.dart';
import '../../core/widgets/currency_picker.dart';
import 'services/sandbox_service.dart';
import 'models/transaction_model.dart';
import 'sandbox_forecast_screen.dart';
import 'widgets/add_transaction_dialog.dart';

/// Кастомный title bar с кнопками окна существует только на десктопе —
/// на мобильных резервировать под него место не нужно.
bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

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
  String _currentScenario = '';
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

  /// Открывает выбор из ВСЕХ поддерживаемых валют.
  ///
  /// Раньше здесь был жёсткий переключатель rub↔usd, из-за чего в песочнице
  /// были доступны только рубль и доллар, хотя `CurrencyService` знает
  /// восемь валют.
  Future<void> _toggleCurrency() async {
    final picked = await CurrencyPicker.show(context);
    if (picked == null) return;
    await CurrencyService.set(picked);
    if (mounted) setState(() => _currency = picked);
  }

  Future<void> _runScenario(String scenario) async {
    setState(() => _isLoading = true);
    switch (scenario) {
      case 'startup':
        await _service.generateStartupScenario();
        _currentScenario = 'Startup';
        break;
      case 'freelancer':
        await _service.generateFreelancerScenario();
        _currentScenario = 'Freelancer';
        break;
      case 'crisis':
        await _service.generateCrisisScenario();
        _currentScenario = 'Crisis';
        break;
      case 'clone':
        await _service.cloneFromReal();
        _currentScenario = 'Clone';
        break;
      case 'clear':
        await _service.clearAll();
        _currentScenario = '';
        break;
    }
    await _loadData();
  }

  Future<void> _addTransaction(TransactionType type) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) =>
          AddTransactionDialog(type: type, symbol: _sym),
    );
    if (result != null) {
      final tx = TransactionModel(
        id: 'sandbox_${DateTime.now().millisecondsSinceEpoch}',
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

  /// Идентично Operations screen у Treasury: предзаполненный диалог,
  /// сохранение по тому же id — не delete+add с новым id.
  Future<void> _editTransaction(TransactionModel tx) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AddTransactionDialog(
        type: tx.type,
        symbol: _sym,
        initial: tx,
      ),
    );
    if (result != null) {
      final updated = TransactionModel(
        id: tx.id,
        title: result['title'],
        amount: result['amount'],
        type: tx.type,
        date: tx.date,
        category: result['category'],
        description: result['description'],
        isRecurring: result['isRecurring'] ?? false,
        recurringPeriod: result['recurringPeriod'],
        isAnomaly: tx.isAnomaly,
        zScore: tx.zScore,
      );
      await _service.addTransaction(updated);
      await _loadData();
    }
  }

  Future<void> _deleteTransaction(String id) async {
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

    return Scaffold(
      backgroundColor: AppTheme.background,
      // SafeArea — иначе на телефоне оранжевый баннер «РЕЖИМ ПЕСОЧНИЦЫ»
      // залезал под статус-бар с часами, вырезом камеры и значками связи.
      // Экран строит Column напрямую, без AppBar, поэтому системные отступы
      // сам никто не учитывал.
      body: SafeArea(
        child: Column(
          children: [
            // На десктопе сверху висит кастомный title bar с кнопками окна —
            // на мобильных его нет, поэтому отступ только для десктопа.
            if (_isDesktop) const SizedBox(height: kTitleBarHeight),
            _banner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      WesiLocale.get('wesi_sandbox_title'),
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _toggleCurrency,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        // Место под кнопки окна резервируем только там, где
                        // они есть — на телефоне этот отступ просто съедал
                        // ширину экрана.
                        margin: EdgeInsets.only(right: _isDesktop ? 140 : 0),
                        decoration: BoxDecoration(
                          color: AppTheme.surface.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.glassBorder),
                        ),
                        child: Text('$_sym ${_currency.toUpperCase()}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.accentOrange)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _scenarios(),
                const SizedBox(height: 20),
                _balanceCard(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _action(
                        Icons.add_circle,
                        WesiLocale.isRussian ? 'Продажа' : 'Sale',
                        AppTheme.accentGreen,
                        () => _addTransaction(TransactionType.income),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _action(
                        Icons.remove_circle,
                        WesiLocale.isRussian ? 'Траты' : 'Expense',
                        AppTheme.accentRed,
                        () => _addTransaction(TransactionType.expense),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Прогноз песочницы отдельным экраном: там же конструктор
                // собственных сценариев «Что если?» с автоматическими
                // графиками. Данные — только песочницы, Treasury не трогает.
                const SandboxForecastButton(),
                const SizedBox(height: 20),
                Text(
                  '${WesiLocale.get('sandbox_transactions')} (${_transactions.length})',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 12),
                ..._transactions.take(20).map(_tx),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }

  /// Баннер БЕЗ слова «Сценарий:»
  Widget _banner() {
    final parts = <String>[
      if (_currentScenario.isNotEmpty) _currentScenario,
      WesiLocale.get('data_isolated'),
      WesiLocale.get('no_impact'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF4D3D00).withOpacity(0.8),
            const Color(0xFF2D1F00).withOpacity(0.6)
          ],
        ),
        border: Border(
            bottom: BorderSide(color: AppTheme.accentOrange.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accentOrange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: AppTheme.accentOrange.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.science,
                    size: 14, color: AppTheme.accentOrange),
                const SizedBox(width: 6),
                Text(
                  WesiLocale.get('sandbox_mode'),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accentOrange,
                      letterSpacing: 1.2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              parts.join(' • '),
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textMuted.withOpacity(0.85)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 18, color: AppTheme.textMuted),
            onPressed: () => _runScenario('clear'),
            tooltip: WesiLocale.get('clear_sandbox'),
          ),
        ],
      ),
    );
  }

  Widget _scenarios() {
    final list = [
      ('startup', 'Startup', Icons.rocket_launch, 'Seed + burn'),
      ('freelancer', 'Freelancer', Icons.laptop_mac, 'Irregular income'),
      ('crisis', 'Crisis', Icons.warning, 'Anomalies + chaos'),
      ('clone', 'Clone Real', Icons.copy_all, 'Copy real Treasury'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: list
            .map((s) => Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => _runScenario(s.$1),
                    child: Container(
                      width: 150,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppTheme.accentOrange.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(s.$3,
                              size: 22, color: AppTheme.accentOrange),
                          const SizedBox(height: 8),
                          Text(s.$2,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary)),
                          Text(s.$4,
                              style: const TextStyle(
                                  fontSize: 10, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _balanceCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accentOrange.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(WesiLocale.get('sandbox_balance'),
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Text(
            '$_sym${_balance.toStringAsFixed(2)}',
            style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary),
          ),
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

  Widget _action(
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

  Widget _tx(TransactionModel tx) {
    final isIncome = tx.type == TransactionType.income;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(
        children: [
          Icon(isIncome ? Icons.arrow_upward : Icons.arrow_downward,
              color: isIncome ? AppTheme.accentGreen : AppTheme.accentRed,
              size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tx.title,
                style: const TextStyle(color: AppTheme.textPrimary)),
          ),
          Text(
            '${isIncome ? '+' : '-'}$_sym${tx.amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isIncome ? AppTheme.accentGreen : AppTheme.accentRed,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _editTransaction(tx),
            child: const Icon(Icons.edit,
                size: 16, color: AppTheme.textMuted),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _deleteTransaction(tx.id),
            child: const Icon(Icons.close,
                size: 16, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
