import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import 'models/article_model.dart';
import 'services/knowledge_service.dart';

/// База знаний: регламенты, инструкции, опыт — и встроенный раздел
/// «О программе», описывающий сам WesiOS.
///
/// Встроенные статьи живут в коде и перезаписываются при каждом запуске:
/// справка, отставшая от версии, хуже её отсутствия. Пользовательские
/// статьи хранятся в Hive и не трогаются.
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
    // Гарантируем, что встроенные статьи на месте: экран может открыться
    // раньше, чем отработает фоновый seed при старте.
    await KnowledgeService.seed();
    final list =
        await KnowledgeService.search(query: _query, section: _section);
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
        label: Text(_ru ? 'Статья' : 'Article',
            style: const TextStyle(color: Colors.white)),
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
                    icon: const Icon(Icons.arrow_back,
                        color: AppTheme.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: WesiTitle(_ru ? 'База знаний' : 'Knowledge Base',
                        size: 22),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                height: 40,
                child: TextField(
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textPrimary),
                  onChanged: (v) {
                    _query = v;
                    _load();
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search,
                        size: 18, color: AppTheme.textMuted),
                    hintText: _ru
                        ? 'Поиск по заголовку, тексту и тегам'
                        : 'Search titles, text and tags',
                    hintStyle: const TextStyle(
                        fontSize: 13, color: AppTheme.textMuted),
                    filled: true,
                    fillColor: AppTheme.surface.withOpacity(0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
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
                  ...ArticleSection.values
                      .map((s) => _chip(s, _sectionLabel(s))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.accentOrange.withOpacity(0.5)))
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
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() => _section = s);
          _load();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: sel
                ? AppTheme.accentOrange.withOpacity(0.16)
                : AppTheme.surface.withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: sel
                    ? AppTheme.accentOrange.withOpacity(0.5)
                    : AppTheme.glassBorder),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
              color: sel ? AppTheme.accentOrange : AppTheme.textSecondary,
            ),
          ),
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
              const Icon(Icons.menu_book, size: 34, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              Text(
                _query.isEmpty
                    ? (_ru ? 'Здесь пока пусто' : 'Nothing here yet')
                    : (_ru ? 'Ничего не найдено' : 'Nothing found'),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                _ru
                    ? 'Запишите регламент, инструкцию или разбор — то, что '
                        'иначе придётся вспоминать заново.'
                    : 'Write down a playbook or a guide — something you would '
                        'otherwise have to reconstruct from memory.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      );

  Widget _tile(ArticleModel a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _open(a),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.36),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: a.pinned
                    ? AppTheme.accentOrange.withOpacity(0.4)
                    : AppTheme.glassBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_sectionIcon(a.section),
                        size: 15, color: AppTheme.accentOrange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary),
                      ),
                    ),
                    if (a.builtIn)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.textMuted.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _ru ? 'встроенная' : 'built-in',
                          style: const TextStyle(
                              fontSize: 9, color: AppTheme.textMuted),
                        ),
                      ),
                    IconButton(
                      icon: Icon(
                        a.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                        size: 15,
                        color: a.pinned
                            ? AppTheme.accentOrange
                            : AppTheme.textMuted,
                      ),
                      onPressed: () => KnowledgeService.togglePin(a),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.only(left: 8),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  a.excerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
                if (a.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: a.tags
                        .map((t) => Text('#$t',
                            style: const TextStyle(
                                fontSize: 10, color: AppTheme.textMuted)))
                        .toList(),
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
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ArticleScreen(article: a)),
    );
    await _load();
  }

  Future<void> _create() async {
    final result = await ArticleEditorDialog.show(context);
    if (result == null) return;
    await KnowledgeService.create(
      title: result.title,
      body: result.body,
      section: result.section,
      tags: result.tags,
    );
    await _load();
  }
}

/// Чтение статьи.
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
    final result = await ArticleEditorDialog.show(context, initial: _article);
    if (result == null) return;
    final updated = _article.copyWith(
      title: result.title,
      body: result.body,
      section: result.section,
      tags: result.tags,
      updatedAt: DateTime.now(),
    );
    await KnowledgeService.save(updated);
    if (mounted) setState(() => _article = updated);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_ru ? 'Удалить статью?' : 'Delete article?',
            style: const TextStyle(fontSize: 17, color: AppTheme.textPrimary)),
        content: Text(_article.title,
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(WesiLocale.get('cancel'),
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_ru ? 'Удалить' : 'Delete',
                style: TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await KnowledgeService.delete(_article.id);
    if (mounted) Navigator.pop(context);
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
                  IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: AppTheme.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        size: 19, color: AppTheme.textMuted),
                    onPressed: _edit,
                  ),
                  // Встроенную справку удалить нельзя — восстановить её
                  // было бы нечем.
                  if (!_article.builtIn)
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 19, color: AppTheme.textMuted),
                      onPressed: _delete,
                    ),
                  SizedBox(width: kHasCustomTitleBar ? 140 : 0),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  Text(
                    _article.title,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 14),
                  ..._renderBody(_article.body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Простейший разбор Markdown: заголовки, списки, абзацы.
  ///
  /// Полноценный рендерер здесь избыточен — статьи пишутся обычным текстом,
  /// и важно только, чтобы заголовки и списки читались как заголовки и
  /// списки, а не как строки со звёздочками.
  List<Widget> _renderBody(String body) {
    final widgets = <Widget>[];
    for (final rawLine in body.split('\n')) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 10));
        continue;
      }
      if (line.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(line.substring(3),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentOrange)),
        ));
        continue;
      }
      if (line.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(line.substring(2),
              style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary)),
        ));
        continue;
      }
      if (line.startsWith('- ') || line.startsWith('* ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•', style: TextStyle(color: AppTheme.accentOrange)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_stripMarks(line.substring(2)),
                    style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppTheme.textSecondary)),
              ),
            ],
          ),
        ));
        continue;
      }
      final numbered = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(line);
      if (numbered != null) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${numbered.group(1)}.',
                  style: TextStyle(color: AppTheme.accentOrange)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_stripMarks(numbered.group(2)!),
                    style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppTheme.textSecondary)),
              ),
            ],
          ),
        ));
        continue;
      }
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(_stripMarks(line),
            style: const TextStyle(
                fontSize: 13, height: 1.55, color: AppTheme.textSecondary)),
      ));
    }
    return widgets;
  }

  String _stripMarks(String s) => s.replaceAll('**', '').replaceAll('`', '');
}

/// Результат редактора статьи.
class ArticleEditResult {
  final String title;
  final String body;
  final ArticleSection section;
  final List<String> tags;

  const ArticleEditResult({
    required this.title,
    required this.body,
    required this.section,
    required this.tags,
  });
}

class ArticleEditorDialog extends StatefulWidget {
  final ArticleModel? initial;

  const ArticleEditorDialog({super.key, this.initial});

  static Future<ArticleEditResult?> show(BuildContext context,
      {ArticleModel? initial}) {
    return showDialog<ArticleEditResult>(
      context: context,
      builder: (_) => ArticleEditorDialog(initial: initial),
    );
  }

  @override
  State<ArticleEditorDialog> createState() => _ArticleEditorDialogState();
}

class _ArticleEditorDialogState extends State<ArticleEditorDialog> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  late ArticleSection _section;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    _section = a?.section ?? ArticleSection.playbook;
    if (a != null) {
      _titleCtrl.text = a.title;
      _bodyCtrl.text = a.body;
      _tagsCtrl.text = a.tags.join(', ');
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(
      context,
      ArticleEditResult(
        title: title,
        body: _bodyCtrl.text,
        section: _section,
        tags: _tagsCtrl.text
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList(),
      ),
    );
  }

  String _label(ArticleSection s) => switch (s) {
        ArticleSection.about => _ru ? 'О программе' : 'About',
        ArticleSection.playbook => _ru ? 'Регламенты' : 'Playbooks',
        ArticleSection.guide => _ru ? 'Инструкции' : 'Guides',
        ArticleSection.finance => _ru ? 'Финансы' : 'Finance',
        ArticleSection.personal => _ru ? 'Личное' : 'Personal',
      };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.fromLTRB(30, kTitleBarHeight + 24, 30, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.initial == null
                    ? (_ru ? 'Новая статья' : 'New article')
                    : (_ru ? 'Статья' : 'Article'),
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _titleCtrl,
                autofocus: true,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration:
                    InputDecoration(labelText: _ru ? 'Заголовок' : 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyCtrl,
                maxLines: 10,
                minLines: 6,
                style:
                    const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: _ru ? 'Текст' : 'Body',
                  helperText: _ru
                      ? '# заголовок, ## подзаголовок, - список'
                      : '# heading, ## subheading, - list',
                  helperStyle:
                      const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tagsCtrl,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText:
                      _ru ? 'Теги через запятую' : 'Comma-separated tags',
                ),
              ),
              const SizedBox(height: 16),
              Text(_ru ? 'Раздел' : 'Section',
                  style:
                      const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ArticleSection.values.map((s) {
                  final sel = s == _section;
                  return GestureDetector(
                    onTap: () => setState(() => _section = s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel
                            ? AppTheme.accentOrange.withOpacity(0.18)
                            : AppTheme.background,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                            color: sel
                                ? AppTheme.accentOrange.withOpacity(0.6)
                                : AppTheme.glassBorder),
                      ),
                      child: Text(
                        _label(s),
                        style: TextStyle(
                          fontSize: 12,
                          color: sel
                              ? AppTheme.accentOrange
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(WesiLocale.get('cancel'),
                        style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const Spacer(),
                  HoverButton(
                    onTap: _submit,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    backgroundColor: AppTheme.accentOrange,
                    child: Text(WesiLocale.get('save'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
