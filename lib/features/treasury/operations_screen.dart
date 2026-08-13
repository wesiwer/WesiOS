import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/services/currency_service.dart';
import '../../core/widgets/window_controls.dart';
import '../organizations/services/organization_context.dart';
import '../organizations/widgets/organization_switcher.dart';
import 'services/treasury_service.dart';
import 'models/transaction_model.dart';
import 'widgets/add_transaction_dialog.dart';
import 'widgets/category_pie.dart';
import '../../core/widgets/wesi_wordmark.dart';

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
  String _sortBy = 'date';

  @override
  void initState() {
    super.initState();
    OrganizationContext.revision.addListener(_reload);
    _loadData();
  }

  @override
  void dispose() {
    OrganizationContext.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _loadData();

  Future<void> _loadData() async {
    final txs = await _service.getAllTransactions();
    if (!mounted) return;
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
          (tx.category?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
              false);
      final matchesCategory =
          _filterCategory == null || tx.category == _filterCategory;
      return matchesSearch && matchesCategory;
    }).toList();

    switch (_sortBy) {
      case 'date':
        _filtered.sort((a, b) => b.date.compareTo(a.date));
        break;
      case 'amount':
        _filtered.sort((a, b) => b.amount.compareTo(a.amount));
        break;
      case 'category':
        _filtered
            .sort((a, b) => (a.category ?? '').compareTo(b.category ?? ''));
        break;
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

  Future<void> _editTx(TransactionModel tx) async {
    if (tx.interOrgTransferId != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Межорганизационная проводка изменяется только через связанную операцию перевода.'),
          ),
        );
      }
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AddTransactionDialog(
        type: tx.type,
        symbol: CurrencyService.symbol,
        initial: tx,
      ),
    );
    if (result != null) {
      final reportingAmount = result['amount'] as double;
      final editedDate = result['date'] as DateTime? ?? tx.date;
      // An edit is a new monetary observation in the currency currently shown
      // by the dialog. Rebuild the normalized money metadata instead of
      // carrying stale original/base values from the old amount.
      final updated = TransactionModel(
        id: tx.id,
        title: result['title'] as String,
        amount: reportingAmount,
        type: tx.type,
        date: editedDate,
        category: result['category'] as String?,
        description: result['description'] as String?,
        isRecurring: result['isRecurring'] as bool? ?? false,
        recurringPeriod: result['isRecurring'] == true
            ? result['recurringPeriod'] as RecurringPeriod?
            : null,
        isAnomaly: tx.isAnomaly,
        zScore: tx.zScore,
        accountId: tx.accountId,
        organizationId: tx.organizationId,
        projectId: tx.projectId,
        counterpartyId: tx.counterpartyId,
        source: tx.source,
        createdBy: tx.createdBy,
        updatedBy: tx.updatedBy,
        updatedAt: tx.updatedAt,
        ownerEmployeeId: result['ownerEmployeeId'] as String?,
        interOrgTransferId: tx.interOrgTransferId,
        createdByEmployeeId: tx.createdByEmployeeId,
        originalAmount: CurrencyService.fromRub(reportingAmount),
        originalCurrency: CurrencyService.current.toUpperCase(),
        organizationBaseAmount: null,
        organizationBaseCurrency: tx.organizationBaseCurrency,
        fxRateToReporting: CurrencyService.rateToRub(CurrencyService.current),
        fxRateAt: editedDate,
        fxSource: 'CurrencyService',
      );
      await _service.updateTransaction(updated, reason: 'manual edit');
      await _loadData();
    }
  }

  Set<String> get _categories => _transactions
      .map((t) => t.category ?? WesiLocale.get('uncategorized'))
      .toSet();

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

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: WesiTitle(WesiLocale.get('operations'), size: 18),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: OrganizationSwitcher(compact: true)),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.sort, color: AppTheme.textSecondary),
            onSelected: (v) {
              setState(() {
                _sortBy = v;
                _applyFilters();
              });
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'date', child: Text(WesiLocale.get('sort_by_date'))),
              PopupMenuItem(
                  value: 'amount',
                  child: Text(WesiLocale.get('sort_by_amount'))),
              PopupMenuItem(
                  value: 'category',
                  child: Text(WesiLocale.get('sort_by_category'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) {
                setState(() {
                  _searchQuery = v;
                  _applyFilters();
                });
              },
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: WesiLocale.get('search_operations'),
                hintStyle: TextStyle(color: AppTheme.textMuted),
                prefixIcon: Icon(Icons.search, color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surface.withOpacity(0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.glassBorder),
                ),
              ),
            ),
          ),
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
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      WesiLocale.get('no_transactions'),
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      CategoryPieSection(transactions: _filtered),
                      const SizedBox(height: 20),
                      ..._transactionRows(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _transactionRows() {
    if (_filtered.isEmpty) return const [];
    if (_sortBy != 'date') return _filtered.map(_txItem).toList();

    final rows = <Widget>[];
    DateTime? previousDay;
    for (final tx in _filtered) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (previousDay != day) {
        rows.add(_dateHeader(day));
        previousDay = day;
      }
      rows.add(_txItem(tx));
    }
    return rows;
  }

  Widget _dateHeader(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final label = day == today
        ? (WesiLocale.isRussian ? 'Сегодня' : 'Today')
        : day == yesterday
            ? (WesiLocale.isRussian ? 'Вчера' : 'Yesterday')
            : _formatDate(day);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: AppTheme.glassBorder)),
        ],
      ),
    );
  }

  Widget _txItem(TransactionModel tx) {
    final isIncome = tx.type == TransactionType.income;
    final linked = tx.interOrgTransferId != null;
    return Dismissible(
      key: Key(tx.id),
      direction: linked ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppTheme.accentRed.withOpacity(0.3),
        child: Icon(Icons.delete, color: AppTheme.accentRed),
      ),
      onDismissed: linked ? null : (_) => _deleteTx(tx.id),
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
              linked
                  ? Icons.swap_horiz_rounded
                  : isIncome
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
              color: linked
                  ? AppTheme.accent
                  : isIncome
                      ? AppTheme.accentGreen
                      : AppTheme.accentRed,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.title,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    '${tx.category ?? WesiLocale.get('uncategorized')} · ${_formatDate(tx.date)} · ${_formatTime(tx.date)}${linked ? ' · inter-org' : ''}',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              '${isIncome ? '+' : '-'}${CurrencyService.formatExactSmart(tx.amount)}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isIncome ? AppTheme.accentGreen : AppTheme.accentRed,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: linked ? null : () => _editTx(tx),
              child: Icon(Icons.edit,
                  size: 18,
                  color: linked ? AppTheme.textMuted.withOpacity(.35) : AppTheme.textMuted),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: linked ? null : () => _confirmDelete(tx),
              child: Icon(Icons.delete_outline,
                  size: 18,
                  color: linked ? AppTheme.textMuted.withOpacity(.35) : AppTheme.accentRed),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.fromLTRB(40, kTitleBarHeight + 24, 40, 24),
        title: Text(ru ? 'Удалить операцию?' : 'Delete operation?',
            style: TextStyle(fontSize: 17, color: AppTheme.textPrimary)),
        content: Text(
          ru
              ? '«${tx.title}» будет удалена безвозвратно.'
              : '"${tx.title}" will be permanently removed.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(WesiLocale.get('cancel'),
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ru ? 'Удалить' : 'Delete',
                style: TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
    if (ok == true) await _deleteTx(tx.id);
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  String _formatTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
