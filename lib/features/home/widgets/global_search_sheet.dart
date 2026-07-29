import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/window_controls.dart';
import '../../knowledge/models/article_model.dart';
import '../../knowledge/services/knowledge_service.dart';
import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_service.dart';
import '../../treasury/models/account_model.dart';
import '../../treasury/models/transaction_model.dart';
import '../../treasury/services/account_service.dart';
import '../../treasury/services/treasury_service.dart';
import '../services/global_search_service.dart';

/// Поиск по всему приложению.
///
/// Данные читаются один раз при открытии, а не на каждое нажатие клавиши:
/// иначе каждый символ дёргал бы Hive заново, и на большой базе поле начало
/// бы заикаться.
class GlobalSearchSheet extends StatefulWidget {
  const GlobalSearchSheet({super.key});

  static Future<void> show(BuildContext context) => showDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.55),
        builder: (_) => const GlobalSearchSheet(),
      );

  @override
  State<GlobalSearchSheet> createState() => _GlobalSearchSheetState();
}

class _GlobalSearchSheetState extends State<GlobalSearchSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  List<SearchHit> _hits = const [];
  bool _loading = true;

  List<TransactionModel> _transactions = const [];
  List<TaskModel> _tasks = const [];
  List<ArticleModel> _articles = const [];
  List<AccountModel> _accounts = const [];

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final transactions = await TreasuryService().getAllTransactions();
    final tasks = await TaskService().getAll();
    final articles = await KnowledgeService.getAll();
    final accounts = await AccountService.getAll();
    if (!mounted) return;
    setState(() {
      _transactions = transactions;
      _tasks = tasks;
      _articles = articles;
      _accounts = accounts;
      _loading = false;
    });
    _run(_ctrl.text);
  }

  void _run(String query) {
    setState(() {
      _hits = GlobalSearchService.search(
        query: query,
        transactions: _transactions,
        tasks: _tasks,
        articles: _articles,
        accounts: _accounts,
        russian: _ru,
      );
    });
  }

  void _open(SearchHit hit) {
    Navigator.pop(context);
    Navigator.pushNamed(context, hit.route);
  }

  IconData _icon(SearchKind kind) => switch (kind) {
        SearchKind.transaction => Icons.receipt_long,
        SearchKind.task => Icons.check_circle_outline,
        SearchKind.article => Icons.menu_book_outlined,
        SearchKind.account => Icons.account_balance_wallet_outlined,
        SearchKind.module => Icons.grid_view,
      };

  Color _color(SearchKind kind) => switch (kind) {
        SearchKind.transaction => AppTheme.accentGreen,
        SearchKind.task => AppTheme.primary,
        SearchKind.article => AppTheme.textSecondary,
        SearchKind.account => AppTheme.accentOrange,
        SearchKind.module => AppTheme.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    final short = _ctrl.text.trim().length < 2;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.fromLTRB(20, kTitleBarHeight + 24, 20, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                autofocus: true,
                onChanged: _run,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: _ru
                      ? 'Операции, задачи, статьи, счета, разделы…'
                      : 'Operations, tasks, articles, accounts, sections…',
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: AppTheme.textMuted),
                  suffixIcon: _ctrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close,
                              size: 16, color: AppTheme.textMuted),
                          onPressed: () {
                            _ctrl.clear();
                            _run('');
                            _focus.requestFocus();
                          },
                        ),
                ),
              ),
            ),
            const Divider(height: 1, color: AppTheme.glassBorder),
            Flexible(
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        _ru ? 'Читаю данные…' : 'Reading data…',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textMuted),
                      ),
                    )
                  : short
                      ? _hint()
                      : _hits.isEmpty
                          ? _empty()
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              shrinkWrap: true,
                              itemCount: _hits.length,
                              itemBuilder: (_, i) => _row(_hits[i]),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hint() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _ru ? 'Что можно найти' : 'What you can find',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            ...[
              (
                Icons.receipt_long,
                _ru
                    ? 'Операции — по названию, категории и описанию'
                    : 'Operations — by title, category and description'
              ),
              (
                Icons.check_circle_outline,
                _ru
                    ? 'Задачи — по названию, описанию и тегам'
                    : 'Tasks — by title, description and tags'
              ),
              (
                Icons.menu_book_outlined,
                _ru ? 'Статьи базы знаний' : 'Knowledge base articles'
              ),
              (
                Icons.grid_view,
                _ru
                    ? 'Разделы приложения — «прогноз», «песочница», «защита»'
                    : 'App sections — “forecast”, “sandbox”, “shield”'
              ),
            ].map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(e.$1, size: 15, color: AppTheme.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(e.$2,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textMuted)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _empty() => Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          _ru ? 'Ничего не найдено' : 'Nothing found',
          style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
        ),
      );

  Widget _row(SearchHit hit) => InkWell(
        onTap: () => _open(hit),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Row(
            children: [
              Icon(_icon(hit.kind), size: 17, color: _color(hit.kind)),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textPrimary),
                    ),
                    if (hit.subtitle != null && hit.subtitle!.isNotEmpty)
                      Text(
                        hit.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textMuted),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 16, color: AppTheme.textMuted),
            ],
          ),
        ),
      );
}
