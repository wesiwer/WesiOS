import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import 'models/article_model.dart';
import 'services/knowledge_service.dart';
import 'widgets/article_body_view.dart';
import 'screens/article_editor_screen.dart';

/// База знаний. Jitter fixed in KnowledgeService.seed (idempotent + preserve updatedAt).
class KnowledgeBaseScreen extends StatefulWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  List<ArticleModel> _articles = [];
  ArticleSection? _section;
  String _query = '';
  bool _loading = true;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    _load();
    KnowledgeService.revision.addListener(_load);
  }

  @override
  void dispose() {
    KnowledgeService.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    await KnowledgeService.seed();
    final list = await KnowledgeService.search(query: _query, section: _section);
    if (!mounted) return;
    setState(() {
      _articles = list;
      _loading = false;
    });
  }

  String _sectionLabel(ArticleSection s) => switch (s) {
        ArticleSection.about => _ru ? 'О программе' : 'About',
        ArticleSection.playbook => _ru ? 'Регламенты' : 'Playbooks',
        ArticleSection.guide => _ru ? 'Инструкции' : 'Guides',
        ArticleSection.finance => _ru ? 'Финансы' : 'Finance',
        ArticleSection.personal => _ru ? 'Личное' : 'Personal',
      };

  IconData _sectionIcon(ArticleSection s) => switch (s) {
        ArticleSection.about => Icons.info_outline,
        ArticleSection.playbook => Icons.rule_folder_outlined,
        ArticleSection.guide => Icons.school_outlined,
        ArticleSection.finance => Icons.account_balance_wallet_outlined,
        ArticleSection.personal => Icons.person_outline,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.accentOrange,
        onPressed: _create,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(_ru ? 'Статья' : 'Article', style: const TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8, kTitleBarInset + 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(child: WesiTitle(_ru ? 'База знаний' : 'Knowledge Base', size: 22)),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                height: 40,
                child: TextField(
                  style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                  onChanged: (v) { _query = v; _load(); },
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18, color: AppTheme.textMuted),
                    hintText: _ru ? 'Поиск по заголовку, тексту и тегам' : 'Search titles, text and tags',
                    hintStyle: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    filled: true,
                    fillColor: AppTheme.surface.withOpacity(0.5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _chip(null, _ru ? 'Все' : 'All'),
                  ...ArticleSection.values.map((s) => _chip(s, _sectionLabel(s))),
                ],
              ),
            ),
            SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: AppTheme.accentOrange.withOpacity(0.5)))
                  : _articles.isEmpty
                      ? _empty()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          itemCount: _articles.length,
                          itemBuilder: (context, i) => _tile(_articles[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(ArticleSection? s, String label) {
    final sel = s == _section;
    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () { setState(() => _section = s); _load(); },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? AppTheme.accentOrange.withOpacity(0.16) : AppTheme.surface.withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? AppTheme.accentOrange.withOpacity(0.5) : AppTheme.glassBorder),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w400, color: sel ? AppTheme.accentOrange : AppTheme.textSecondary)),
        ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book, size: 34, color: AppTheme.textMuted),
              SizedBox(height: 12),
              Text(_query.isEmpty ? (_ru ? 'Здесь пока пусто' : 'Nothing here yet') : (_ru ? 'Ничего не найдено' : 'Nothing found'), style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              SizedBox(height: 6),
              Text(_ru ? 'Запишите регламент, инструкцию или разбор.' : 'Write down a playbook or a guide.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            ],
          ),
        ),
      );

  Widget _tile(ArticleModel a) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _open(a),
          child: Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.36),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: a.pinned ? AppTheme.accentOrange.withOpacity(0.4) : AppTheme.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_sectionIcon(a.section), size: 15, color: AppTheme.accentOrange),
                    SizedBox(width: 8),
                    Expanded(child: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary))),
                    if (a.builtIn) Container(padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: AppTheme.textMuted.withOpacity(0.14), borderRadius: BorderRadius.circular(6)), child: Text(_ru ? 'встроенная' : 'built-in', style: TextStyle(fontSize: 9, color: AppTheme.textMuted))),
                    IconButton(icon: Icon(a.pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 15, color: a.pinned ? AppTheme.accentOrange : AppTheme.textMuted), onPressed: () => KnowledgeService.togglePin(a), constraints: BoxConstraints(), padding: EdgeInsets.only(left: 8)),
                  ],
                ),
                SizedBox(height: 6),
                Text(a.excerpt, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                if (a.tags.isNotEmpty) ...[SizedBox(height: 8), Wrap(spacing: 6, children: a.tags.map((t) => Text('#$t', style: TextStyle(fontSize: 10, color: AppTheme.textMuted))).toList())],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(ArticleModel a) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleScreen(article: a)));
    await _load();
  }

  Future<void> _create() async {
    final result = await ArticleEditorScreen.open(context);
    if (result != null) await _load();
  }
}

class ArticleScreen extends StatefulWidget {
  final ArticleModel article;
  const ArticleScreen({super.key, required this.article});
  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  late ArticleModel _article = widget.article;
  bool get _ru => WesiLocale.isRussian;

  Future<void> _edit() async {
    final result = await ArticleEditorScreen.open(context, initial: _article);
    if (result != null) {
      setState(() => _article = result);
      await _load();
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(_ru ? 'Удалить статью?' : 'Delete article?', style: TextStyle(fontSize: 17, color: AppTheme.textPrimary)),
      content: Text(_article.title, style: TextStyle(color: AppTheme.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(WesiLocale.get('cancel'), style: TextStyle(color: AppTheme.textMuted))),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(_ru ? 'Удалить' : 'Delete', style: TextStyle(color: AppTheme.accentRed))),
      ],
    ));
    if (ok != true) return;
    await KnowledgeService.delete(_article.id);
    if (mounted) Navigator.pop(context);
  }

  void _onInternalRoute(String route) {
    if (route.startsWith('article:')) {
      final id = route.substring('article:'.length);
      KnowledgeService.getById(id).then((a) {
        if (a != null && mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleScreen(article: a)));
        }
      });
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_ru ? 'Переход: $route' : 'Navigate: $route'), backgroundColor: AppTheme.surface, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8, kTitleBarInset + 8, 8, 0),
              child: Row(
                children: [
                  IconButton(icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary), onPressed: () => Navigator.pop(context)),
                  Spacer(),
                  IconButton(icon: Icon(Icons.edit_outlined, size: 19, color: AppTheme.textMuted), onPressed: _edit),
                  if (!_article.builtIn) IconButton(icon: Icon(Icons.delete_outline, size: 19, color: AppTheme.textMuted), onPressed: _delete),
                  SizedBox(width: kHasCustomTitleBar ? 140 : 0),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  Text(_article.title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                  const SizedBox(height: 14),
                  ArticleBodyView(article: _article, onInternalRoute: _onInternalRoute),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
