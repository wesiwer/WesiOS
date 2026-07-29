import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/services/currency_service.dart';
import '../../core/widgets/window_controls.dart';
import 'services/treasury_service.dart';
import 'models/transaction_model.dart';
import 'widgets/add_transaction_dialog.dart';
import 'widgets/category_pie.dart';

/// Экран всех операций — полный список транзакций с edit/delete
class OperationsScreen extends StatefulWidget {
  const OperationsScreen({super.key});

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  final TreasuryService _service = TreasuryService();
  List<TransactionModel> _transactions = [];
  List<TransactionModel> _filtered = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _filterCategory;
  String _sortBy = 'date'; // date, amount, category

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final txs = await _service.getAllTransactions();
    setState(() {
      _transactions = txs;
      _applyFilters();
      _isLoading = false;
    });
  }

  void _applyFilters() {
    _filtered = _transactions.where((tx) {
      final matchesSearch = _searchQuery.isEmpty ||
          tx.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (tx.category?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
      final matchesCategory = _filterCategory == null || tx.category == _filterCategory;
      return matchesSearch && matchesCategory;
    }).toList();

    // Sort
    switch (_sortBy) {
      case 'date':
        _filtered.sort((a, b) => b.date.compareTo(a.date));
        break;
      case 'amount':
        _filtered.sort((a, b) => b.amount.compareTo(a.amount));
        break;
      case 'category':
        _filtered.sort((a, b) => (a.category ?? '').compareTo(b.category ?? ''));
        break;
    }
  }

  Future<void> _deleteTx(String id) async {
    await _service.deleteTransaction(id);
    await _loadData();
  }

  Future<void> _editTx(TransactionModel tx) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AddTransactionDialog(
        type: tx.type,
        symbol: CurrencyService.symbol,
        initial: tx,
      ),
    );
    if (result != null) {
      // Тот же id — box.put перезаписывает запись, а не плодит дубли.
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

  Set<String> get _categories {
    return _transactions.map((t) => t.category ?? WesiLocale.get('uncategorized')).toSet();
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
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: Text(WesiLocale.get('operations')),
        actions: [
          // Sort button
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: AppTheme.textSecondary),
            onSelected: (v) {
              setState(() {
                _sortBy = v;
                _applyFilters();
              });
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'date', child: Text(WesiLocale.get('sort_by_date'))),
              PopupMenuItem(value: 'amount', child: Text(WesiLocale.get('sort_by_amount'))),
              PopupMenuItem(value: 'category', child: Text(WesiLocale.get('sort_by_category'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) {
                setState(() {
                  _searchQuery = v;
                  _applyFilters();
                });
              },
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: WesiLocale.get('search_operations'),
                hintStyle: const TextStyle(color: AppTheme.textMuted),
                prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surface.withOpacity(0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.glassBorder),
                ),
              ),
            ),
          ),
          // Category filter chips
          if (_categories.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  FilterChip(
                    selected: _filterCategory == null,
                    onSelected: (_) => setState(() {
                      _filterCategory = null;
                      _applyFilters();
                    }),
                    label: Text(WesiLocale.get('all')),
                  ),
                  const SizedBox(width: 8),
                  ..._categories.map((cat) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: _filterCategory == cat,
                      onSelected: (_) => setState(() {
                        _filterCategory = cat;
                        _applyFilters();
                      }),
                      label: Text(cat),
                    ),
                  )),
                ],
              ),
            ),
          const SizedBox(height: 8),
          // Transactions list
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      WesiLocale.get('no_transactions'),
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Диаграммы считаются по ОТФИЛЬТРОВАННОМУ списку —
                      // так поиск и фильтр по категории меняют и структуру,
                      // а не только перечень строк ниже.
                      CategoryPieSection(transactions: _filtered),
                      const SizedBox(height: 20),
                      ..._filtered.map(_txItem),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _txItem(TransactionModel tx) {
    final isIncome = tx.type == TransactionType.income;
    final sym = CurrencyService.symbol;
    return Dismissible(
      key: Key(tx.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppTheme.accentRed.withOpacity(0.3),
        child: const Icon(Icons.delete, color: AppTheme.accentRed),
      ),
      onDismissed: (_) => _deleteTx(tx.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(
          children: [
            Icon(
              isIncome ? Icons.arrow_upward : Icons.arrow_downward,
              color: isIncome ? AppTheme.accentGreen : AppTheme.accentRed,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.title,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    '${tx.category ?? WesiLocale.get('uncategorized')} · ${_formatDate(tx.date)}',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              '${isIncome ? '+' : '-'}$sym${CurrencyService.fromRub(tx.amount).toStringAsFixed(0)}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isIncome ? AppTheme.accentGreen : AppTheme.accentRed,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _editTx(tx),
              child: const Icon(Icons.edit, size: 18, color: AppTheme.textMuted),
            ),
            const SizedBox(width: 12),
            // Явная кнопка удаления. Свайп (Dismissible) остаётся, но на
            // десктопе он неочевиден, а на телефоне о нём надо догадаться —
            // из-за этого удалять операции получалось только во вкладке
            // «Финансы».
            GestureDetector(
              onTap: () => _confirmDelete(tx),
              child: const Icon(Icons.delete_outline,
                  size: 18, color: AppTheme.accentRed),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(TransactionModel tx) async {
    final ru = WesiLocale.isRussian;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding:
            const EdgeInsets.fromLTRB(40, kTitleBarHeight + 24, 40, 24),
        title: Text(ru ? 'Удалить операцию?' : 'Delete operation?',
            style: const TextStyle(
                fontSize: 17, color: AppTheme.textPrimary)),
        content: Text(
          ru
              ? '«${tx.title}» будет удалена безвозвратно.'
              : '"${tx.title}" will be permanently removed.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(WesiLocale.get('cancel'),
                style: const TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ru ? 'Удалить' : 'Delete',
                style: const TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
    if (ok == true) await _deleteTx(tx.id);
  }

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }
}
