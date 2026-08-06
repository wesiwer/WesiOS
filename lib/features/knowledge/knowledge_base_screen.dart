import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import '../team/services/team_service.dart';
import 'models/article_model.dart';
import 'screens/article_editor_screen.dart';
import 'services/knowledge_service.dart';
import 'widgets/article_body_view.dart';

/// База знаний: папки, поиск, разделы и явное состояние ошибки.
class KnowledgeBaseScreen extends StatefulWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  List<ArticleModel> _articles = const [];
  ArticleSection? _section;
  String _query = '';
  String? _folderId;
  bool _loading = true;
  String? _error;
  int _loadEpoch = 0;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    KnowledgeService.revision.addListener(_reloadFromRevision);
    _load();
  }

  @override
  void dispose() {
    KnowledgeService.revision.removeListener(_reloadFromRevision);
    super.dispose();
  }

  void _reloadFromRevision() => _load(showSpinner: false);

  Future<void> _load({bool showSpinner = true}) async {
    final epoch = ++_loadEpoch;
    if (mounted && showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      await KnowledgeService.seed().timeout(const Duration(seconds: 15));
      final articles = await KnowledgeService.getAll()
          .timeout(const Duration(seconds: 15));
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _articles = articles;
        _loading = false;
        _error = null;
      });
    } on TimeoutException {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _loading = false;
        _error = _ru
            ? 'База знаний не ответила за 15 секунд. Повторите загрузку.'
            : 'Knowledge Base did not respond within 15 seconds.';
      });
    } catch (_) {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _loading = false;
        _error = _ru
            ? 'Не удалось открыть локальную базу знаний.'
            : 'Could not open the local Knowledge Base.';
      });
    }
  }

  bool _isAllowed(ArticleModel article) {
    final permissions = TeamService.currentPermissions;
    if (permissions.knowledgeAll || permissions.allowsArticle(article.id)) {
      return true;
    }
    if (!article.isFolder) return false;
    return _descendants(article.id)
        .any((child) => permissions.allowsArticle(child.id));
  }

  List<ArticleModel> _descendants(String rootId) {
    final result = <ArticleModel>[];
    final seen = <String>{rootId};
    var parents = <String>{rootId};
    while (parents.isNotEmpty) {
      final next = <String>{};
      for (final article in _articles) {
        if (article.parentId != null &&
            parents.contains(article.parentId) &&
            seen.add(article.id)) {
          result.add(article);
          next.add(article.id);
        }
      }
      parents = next;
    }
    return result;
  }

  List<ArticleModel> get _visible {
    Iterable<ArticleModel> source = _articles;
    final q = _query.trim().toLowerCase();

    if (q.isNotEmpty) {
      source = source.where((a) => a.matches(q));
    } else if (_section != null) {
      source = source.where(
        (a) => !a.isFolder && a.section == _section,
      );
    } else {
      source = source.where((a) => a.parentId == _folderId);
    }

    final list = source.where(_isAllowed).toList()
      ..sort(KnowledgeService.compare);
    return list;
  }

  ArticleModel? get _folder {
    final id = _folderId;
    if (id == null) return null;
    for (final article in _articles) {
      if (article.id == id) return article;
    }
    return null;
  }

  void _goBack() {
    final folder = _folder;
    if (folder == null) {
      Navigator.pop(context);
    } else {
      setState(() => _folderId = folder.parentId);
    }
  }

  Future<void> _create() async {
    await ArticleEditorScreen.open(
      context,
      initialParentId: _query.isEmpty && _section == null ? _folderId : null,
    );
    await _load(showSpinner: false);
  }

  Future<void> _open(ArticleModel article) async {
    if (article.isFolder) {
      setState(() {
        _folderId = article.id;
        _query = '';
        _section = null;
      });
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ArticleScreen(article: article)),
    );
    await _load(showSpinner: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: AppTheme.accent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          _ru ? 'Статья' : 'Article',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            _searchField(),
            const SizedBox(height: 12),
            _sectionChips(),
            if (_folder != null && _query.isEmpty && _section == null)
              _folderPath(),
            const SizedBox(height: 8),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: EdgeInsets.fromLTRB(8, kTitleBarInset + 8, 16, 0),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
              onPressed: _goBack,
            ),
            Expanded(
              child: WesiTitle(
                _folder?.title ?? (_ru ? 'База знаний' : 'Knowledge Base'),
                size: 22,
              ),
            ),
          ],
        ),
      );

  Widget _searchField() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: SizedBox(
          height: 42,
          child: TextField(
            onChanged: (value) => setState(() => _query = value),
            style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon:
                  Icon(Icons.search, size: 18, color: AppTheme.textMuted),
              hintText: _ru
                  ? 'Поиск по заголовку, тексту и тегам'
                  : 'Search titles, text and tags',
              hintStyle: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              filled: true,
              fillColor: AppTheme.surface.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      );

  Widget _sectionChips() => SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _chip(null, _ru ? 'Все' : 'All'),
            for (final section in ArticleSection.values)
              _chip(section, section.label(_ru)),
          ],
        ),
      );

  Widget _chip(ArticleSection? section, String label) {
    final selected = section == _section;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() {
          _section = section;
          _query = '';
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accent.withOpacity(0.16)
                : AppTheme.surface.withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppTheme.accent.withOpacity(0.5)
                  : AppTheme.glassBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? AppTheme.accent : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _folderPath() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          _ru ? 'Папка: ${_folder!.title}' : 'Folder: ${_folder!.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
      );

  Widget _content() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: AppTheme.accent),
      );
    }
    if (_error != null) return _errorView();
    final visible = _visible;
    if (visible.isEmpty) return _emptyView();
    return RefreshIndicator(
      color: AppTheme.accent,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        itemCount: visible.length,
        itemBuilder: (context, index) => _tile(visible[index]),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 38, color: AppTheme.accentRed),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(_ru ? 'Повторить' : 'Retry'),
              ),
            ],
          ),
        ),
      );

  Widget _emptyView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined,
                  size: 38, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              Text(
                _query.isNotEmpty
                    ? (_ru ? 'Ничего не найдено' : 'Nothing found')
                    : (_ru ? 'Здесь пока пусто' : 'Nothing here yet'),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _tile(ArticleModel article) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _open(article),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surface.withOpacity(0.4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: article.pinned
                      ? AppTheme.accent.withOpacity(0.4)
                      : AppTheme.glassBorder,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    article.isFolder
                        ? Icons.folder_outlined
                        : Icons.article_outlined,
                    color: AppTheme.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (!article.isFolder && article.excerpt.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            article.excerpt,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!article.isFolder)
                    IconButton(
                      tooltip: _ru ? 'Закрепить' : 'Pin',
                      onPressed: () => KnowledgeService.togglePin(article),
                      icon: Icon(
                        article.pinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        size: 17,
                        color: article.pinned
                            ? AppTheme.accent
                            : AppTheme.textMuted,
                      ),
                    )
                  else
                    Icon(Icons.chevron_right, color: AppTheme.textMuted),
                ],
              ),
            ),
          ),
        ),
      );
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
    final updated = await ArticleEditorScreen.open(context, initial: _article);
    if (updated != null && mounted) setState(() => _article = updated);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(_ru ? 'Удалить статью?' : 'Delete article?'),
        content: Text(_article.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_ru ? 'Отмена' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              _ru ? 'Удалить' : 'Delete',
              style: TextStyle(color: AppTheme.accentRed),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await KnowledgeService.delete(_article.id);
    if (mounted) Navigator.pop(context);
  }

  void _route(String route) {
    if (!route.startsWith('article:')) return;
    final id = route.substring('article:'.length);
    KnowledgeService.getById(id).then((article) {
      if (article != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ArticleScreen(article: article)),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8, kTitleBarInset + 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _edit,
                    icon: Icon(Icons.edit_outlined,
                        color: AppTheme.textMuted),
                  ),
                  if (!_article.builtIn)
                    IconButton(
                      onPressed: _delete,
                      icon: Icon(Icons.delete_outline,
                          color: AppTheme.accentRed),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  Text(
                    _article.title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ArticleBodyView(
                    article: _article,
                    onInternalRoute: _route,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
