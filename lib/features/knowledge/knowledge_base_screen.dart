import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../team/services/team_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import 'models/article_model.dart';
import 'services/knowledge_service.dart';
import 'widgets/article_body_view.dart';
import 'screens/article_editor_screen.dart';

/// База знаний с древовидной структурой.
class KnowledgeBaseScreen extends StatefulWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  List<ArticleModel> _articles = [];
  List<ArticleModel> _roots = [];
  ArticleSection? _section;
  String _query = '';
  bool _loading = true;

  /// ID папки, в которую вошли (null = корень).
  String? _currentFolderId;

  /// Раскрытые папки (их ID).
  final Set<String> _expanded = <String>{};

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
    final all = await KnowledgeService.getAll();
    if (!mounted) return;
    setState(() {
      _articles = all;
      _roots = KnowledgeService.getRoots();
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

  /// Открыта ли статья тому, кто сейчас в приложении.
  ///
  /// Права на базу знаний настраиваются вплоть до отдельной статьи, и
  /// применять их надо ЗДЕСЬ, а не только в редакторе прав. Настройка,
  /// которая ни на что не влияет, хуже её отсутствия: владелец считает, что
  /// закрыл раздел, а тот открыт.
  ///
  /// Папка видна, если открыта она сама или хоть что-то внутри неё: иначе
  /// разрешённая статья оказалась бы недостижимой, потому что путь к ней
  /// закрыт.
  bool _isAllowed(ArticleModel a) {
    final p = TeamService.currentPermissions;
    if (p.knowledgeAll) return true;
    if (p.allowsArticle(a.id)) return true;
    if (!a.isFolder) return false;
    return KnowledgeService.getSubtree(a.id).any((c) => p.allowsArticle(c.id));
  }

  /// Статьи для текущего вида (поиск, папка, или корень).
  List<ArticleModel> _visibleArticles() {
    final Iterable<ArticleModel> source;
    if (_query.isNotEmpty) {
      source = _articles.where((a) => a.matches(_query));
    } else if (_currentFolderId != null) {
      source = KnowledgeService.getChildren(_currentFolderId!)
          .where((a) => _section == null || a.section == _section);
    } else {
      source = _roots.where((a) => _section == null || a.section == _section);
    }
    return source.where(_isAllowed).toList();
  }

  /// Хлебные крошки: путь от корня до текущей папки.
  List<ArticleModel> _breadcrumb() {
    if (_currentFolderId == null) return [];
    return KnowledgeService.getBreadcrumb(_currentFolderId!);
  }

  void _enterFolder(ArticleModel folder) {
    setState(() => _currentFolderId = folder.id);
  }

  void _goToRoot() {
    setState(() => _currentFolderId = null);
  }

  void _goToBreadcrumb(int index) {
    final crumbs = _breadcrumb();
    if (index < 0 || index >= crumbs.length) {
      setState(() => _currentFolderId = null);
      return;
    }
    setState(() => _currentFolderId = crumbs[index].id);
  }

  void _toggleExpand(String folderId) {
    setState(() {
      if (_expanded.contains(folderId)) {
        _expanded.remove(folderId);
      } else {
        _expanded.add(folderId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleArticles();
    final crumb = _breadcrumb();

    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.accent,
        onPressed: _create,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(_ru ? 'Статья' : 'Article', style: const TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(8, kTitleBarInset + 8, 16, 0),
              child: Row(
                children: [
                  if (_currentFolderId != null)
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                      onPressed: () {
                        final crumbs = _breadcrumb();
                        if (crumbs.length > 1) {
                          _goToBreadcrumb(crumbs.length - 2);
                        } else {
                          _goToRoot();
                        }
                      },
                    )
                  else
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  Expanded(child: WesiTitle(_ru ? 'База знаний' : 'Knowledge Base', size: 22)),
                ],
              ),
            ),
            // Search
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                height: 40,
                child: TextField(
                  style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                  onChanged: (v) { setState(() => _query = v); },
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
            // Section chips
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
            const SizedBox(height: 8),
            // Breadcrumb
            if (crumb.isNotEmpty) _buildBreadcrumb(crumb),
            // Content
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: AppTheme.accent.withOpacity(0.5)))
                  : visible.isEmpty
                      ? _empty()
                      : _query.isNotEmpty
                          ? _searchList(visible)
                          : _treeList(visible),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(ArticleSection? s, String label) {
    final sel = s == _section;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () { setState(() => _section = s); },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? AppTheme.accent.withOpacity(0.16) : AppTheme.surface.withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? AppTheme.accent.withOpacity(0.5) : AppTheme.glassBorder),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w400, color: sel ? AppTheme.accent : AppTheme.textSecondary)),
        ),
      ),
    );
  }

  Widget _buildBreadcrumb(List<ArticleModel> crumbs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            GestureDetector(
              onTap: _goToRoot,
              child: Text(
                _ru ? 'Корень' : 'Root',
                style: TextStyle(fontSize: 12, color: AppTheme.accent, fontWeight: FontWeight.w600),
              ),
            ),
            ...crumbs.asMap().entries.expand((entry) {
              final i = entry.key;
              final a = entry.value;
              return [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.chevron_right, size: 14, color: AppTheme.textMuted),
                ),
                GestureDetector(
                  onTap: () => _goToBreadcrumb(i),
                  child: Text(
                    a.title,
                    style: TextStyle(
                      fontSize: 12,
                      color: i == crumbs.length - 1 ? AppTheme.textPrimary : AppTheme.accent,
                      fontWeight: i == crumbs.length - 1 ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
              ];
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_currentFolderId != null ? Icons.folder_open_outlined : Icons.menu_book, size: 34, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              Text(
                _query.isEmpty
                    ? (_currentFolderId != null
                        ? (_ru ? 'Папка пуста' : 'Folder is empty')
                        : (_ru ? 'Здесь пока пусто' : 'Nothing here yet'))
                    : (_ru ? 'Ничего не найдено' : 'Nothing found'),
                style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                _currentFolderId != null
                    ? (_ru ? 'Добавьте статью или подпапку.' : 'Add an article or subfolder.')
                    : (_ru ? 'Запишите регламент, инструкцию или разбор.' : 'Write down a playbook or a guide.'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      );

  /// Плоский список для поиска (без дерева, просто тайлы).
  Widget _searchList(List<ArticleModel> items) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: items.length,
      itemBuilder: (context, i) => _tile(items[i], level: 0, isSearch: true),
    );
  }

  /// Древовидный список с expand/collapse.
  Widget _treeList(List<ArticleModel> items) {
    final sorted = [...items]..sort((a, b) {
      if (a.isFolder && !b.isFolder) return -1;
      if (!a.isFolder && b.isFolder) return 1;
      if (a.pinned && !b.pinned) return -1;
      if (!a.pinned && b.pinned) return 1;
      return a.title.compareTo(b.title);
    });

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: sorted.length,
      itemBuilder: (context, i) => _treeTile(sorted[i], level: 0),
    );
  }

  /// Рекурсивный тайл дерева: папка → expand/collapse → дочерние.
  ///
  /// Глубина ограничена: петля в данных (A внутри B, B внутри A) раскрывала
  /// бы вложенность бесконечно и роняла бы экран переполнением стека.
  /// Ограничение стоит здесь, а не только в проверке при выборе родителя,
  /// потому что петлю на диске мог оставить прежний билд.
  static const int _maxTreeDepth = 12;

  Widget _treeTile(ArticleModel a, {required int level}) {
    if (level > _maxTreeDepth) return const SizedBox.shrink();
    final isExpanded = _expanded.contains(a.id);
    final children = isExpanded ? KnowledgeService.getChildren(a.id) : <ArticleModel>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tile(a, level: level, isSearch: false),
        if (isExpanded && children.isNotEmpty)
          ...children.map((child) => _treeTile(child, level: level + 1)),
      ],
    );
  }

  Widget _tile(ArticleModel a, {required int level, required bool isSearch}) {
    final isFolder = a.isFolder;
    final hasChildren = KnowledgeService.hasChildren(a.id);
    final isExpanded = _expanded.contains(a.id);
    final indent = level * 20.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (isFolder) {
              if (isSearch) {
                _enterFolder(a);
              } else {
                if (hasChildren) {
                  _toggleExpand(a.id);
                } else {
                  _enterFolder(a);
                }
              }
            } else {
              _open(a);
            }
          },
          child: Container(
            margin: EdgeInsets.only(left: indent),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.36),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: a.pinned ? AppTheme.accent.withOpacity(0.4) : AppTheme.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isFolder
                          ? (isExpanded ? Icons.folder_open : Icons.folder)
                          : _sectionIcon(a.section),
                      size: 18,
                      color: isFolder ? AppTheme.accent : AppTheme.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                      ),
                    ),
                    if (a.builtIn)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.textMuted.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _ru ? 'встроенная' : 'built-in',
                          style: TextStyle(fontSize: 9, color: AppTheme.textMuted),
                        ),
                      ),
                    if (isFolder && hasChildren && !isSearch)
                      IconButton(
                        icon: Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                          color: AppTheme.textMuted,
                        ),
                        onPressed: () => _toggleExpand(a.id),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.only(left: 8),
                      ),
                    if (!isFolder || level == 0)
                      IconButton(
                        icon: Icon(
                          a.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                          size: 15,
                          color: a.pinned ? AppTheme.accent : AppTheme.textMuted,
                        ),
                        onPressed: () => KnowledgeService.togglePin(a),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.only(left: 8),
                      ),
                  ],
                ),
                if (!isFolder) ...[
                  const SizedBox(height: 6),
                  Text(
                    a.excerpt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
                if (a.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: a.tags.map((t) => Text('#$t', style: TextStyle(fontSize: 10, color: AppTheme.textMuted))).toList(),
                  ),
                ],
                if (isFolder && hasChildren && !isExpanded && !isSearch) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${KnowledgeService.getChildren(a.id).length} ${_ru ? 'элементов' : 'items'}',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
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
    final result = await ArticleEditorScreen.open(
      context,
      initialParentId: _currentFolderId,
    );
    if (result != null) await _load();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ArticleScreen — просмотр статьи с хлебными крошками и дочерними статьями
// ═══════════════════════════════════════════════════════════════════════════

class ArticleScreen extends StatefulWidget {
  final ArticleModel article;
  const ArticleScreen({super.key, required this.article});

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  late ArticleModel _article = widget.article;
  List<ArticleModel> _children = [];
  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  void _loadChildren() {
    setState(() {
      _children = KnowledgeService.getChildren(_article.id);
    });
  }

  Future<void> _edit() async {
    final result = await ArticleEditorScreen.open(context, initial: _article);
    if (result != null) {
      setState(() => _article = result);
      _loadChildren();
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_ru ? 'Удалить статью?' : 'Delete article?', style: TextStyle(fontSize: 17, color: AppTheme.textPrimary)),
        content: Text(_article.title, style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(WesiLocale.get('cancel'), style: TextStyle(color: AppTheme.textMuted))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(_ru ? 'Удалить' : 'Delete', style: TextStyle(color: AppTheme.accentRed))),
        ],
      ),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_ru ? 'Переход: $route' : 'Navigate: $route'), backgroundColor: AppTheme.surface, behavior: SnackBarBehavior.floating),
    );
  }

  List<ArticleModel> _breadcrumb() {
    return KnowledgeService.getBreadcrumb(_article.id);
  }

  @override
  Widget build(BuildContext context) {
    final crumb = _breadcrumb();
    final isFolder = _article.isFolder;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(8, kTitleBarInset + 8, 8, 0),
              child: Row(
                children: [
                  IconButton(icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary), onPressed: () => Navigator.pop(context)),
                  const Spacer(),
                  IconButton(icon: Icon(Icons.edit_outlined, size: 19, color: AppTheme.textMuted), onPressed: _edit),
                  if (!_article.builtIn)
                    IconButton(icon: Icon(Icons.delete_outline, size: 19, color: AppTheme.textMuted), onPressed: _delete),
                  SizedBox(width: kHasCustomTitleBar ? 140 : 0),
                ],
              ),
            ),
            // Breadcrumb
            if (crumb.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: crumb.asMap().entries.expand((entry) {
                      final i = entry.key;
                      final a = entry.value;
                      return [
                        if (i > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(Icons.chevron_right, size: 14, color: AppTheme.textMuted),
                          ),
                        GestureDetector(
                          onTap: i < crumb.length - 1
                              ? () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(builder: (_) => ArticleScreen(article: a)),
                                  );
                                }
                              : null,
                          child: Text(
                            a.title,
                            style: TextStyle(
                              fontSize: 12,
                              color: i == crumb.length - 1 ? AppTheme.textMuted : AppTheme.accent,
                              fontWeight: i == crumb.length - 1 ? FontWeight.w400 : FontWeight.w600,
                            ),
                          ),
                        ),
                      ];
                    }).toList(),
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  // Title with folder icon
                  Row(
                    children: [
                      if (isFolder)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Icon(Icons.folder, size: 28, color: AppTheme.accent),
                        ),
                      Expanded(
                        child: Text(
                          _article.title,
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (!isFolder || _article.body.isNotEmpty)
                    ArticleBodyView(article: _article, onInternalRoute: _onInternalRoute),
                  if (isFolder && _children.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Divider(color: AppTheme.glassBorder, height: 1),
                    const SizedBox(height: 16),
                    Text(
                      _ru ? 'Содержимое папки' : 'Folder contents',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    ..._children.map((child) => _childTile(child)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _childTile(ArticleModel child) {
    final isFolder = child.isFolder;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ArticleScreen(article: child)),
            ).then((_) => _loadChildren());
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Row(
              children: [
                Icon(
                  isFolder ? Icons.folder : Icons.article_outlined,
                  size: 18,
                  color: isFolder ? AppTheme.accent : AppTheme.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        child.title,
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                      if (!isFolder)
                        Text(
                          child.excerpt,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
