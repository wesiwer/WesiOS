import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hover_button.dart';
import '../../../core/widgets/window_controls.dart';
import '../models/article_model.dart';
import '../services/knowledge_service.dart';
import 'special_chars.dart';
import 'emoji_data.dart';
import 'article_editor_charts.dart';
import 'article_editor_media.dart';

class _TableEmbed extends CustomBlockEmbed {
  const _TableEmbed(String value) : super('table', value);
}
class _VideoEmbed extends CustomBlockEmbed {
  const _VideoEmbed(String value) : super('video', value);
}
class _AudioEmbed extends CustomBlockEmbed {
  const _AudioEmbed(String value) : super('audio', value);
}
class _ChartEmbed extends CustomBlockEmbed {
  const _ChartEmbed(String value) : super('chart', value);
}

/// Full article rich-editor with special characters, media, charts, folders.
class ArticleEditorScreen extends StatefulWidget {
  final ArticleModel? initial;
  final String? initialParentId;
  const ArticleEditorScreen({super.key, this.initial, this.initialParentId});

  static Future<ArticleModel?> open(BuildContext context, {ArticleModel? initial, String? initialParentId}) {
    return Navigator.push<ArticleModel>(
      context,
      MaterialPageRoute(builder: (_) => ArticleEditorScreen(initial: initial, initialParentId: initialParentId)),
    );
  }

  @override
  State<ArticleEditorScreen> createState() => _ArticleEditorScreenState();
}

class _ArticleEditorScreenState extends State<ArticleEditorScreen> {
  late final QuillController _controller;
  final _titleCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  late ArticleSection _section;
  String? _parentId;
  String? _parentName;
  bool _isFolder = false;
  bool _saving = false;
  bool _emojiVisible = false;
  bool _specialCharsVisible = false;
  bool _insertDrawerOpen = false;
  String _specialCharCategoryId = 'punct';
  bool get _ru => WesiLocale.isRussian;

  /// Снимок статьи на момент открытия — с ним сравниваем при выходе.
  ///
  /// Без этого нажатие «назад» молча выбрасывало всё написанное: сохранение
  /// здесь только по кнопке, а промахнуться по ней легко — она рядом со
  /// стрелкой возврата.
  late String _initialTitle;
  late String _initialTags;
  late String _initialBody;

  String get _currentBody =>
      jsonEncode(_controller.document.toDelta().toJson());

  bool get _hasChanges =>
      _titleCtrl.text != _initialTitle ||
      _tagsCtrl.text != _initialTags ||
      _currentBody != _initialBody;

  /// Спрашивает подтверждение, если есть несохранённые правки.
  /// true — можно уходить.
  Future<bool> _confirmLeave() async {
    if (!_hasChanges) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          _ru ? 'Выйти без сохранения?' : 'Leave without saving?',
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary),
        ),
        content: Text(
          _ru
              ? 'Изменения в статье не сохранены. Если выйти сейчас, они '
                  'пропадут.'
              : 'The article has unsaved changes. Leaving now discards them.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_ru ? 'Остаться' : 'Stay',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_ru ? 'Выйти' : 'Leave',
                style: TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _leave() async {
    if (await _confirmLeave() && mounted) Navigator.pop(context);
  }

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    // «Инструкции» по умолчанию: чаще всего человек записывает сюда порядок
    // действий, который не хочет вспоминать заново.
    _section = a?.section ?? ArticleSection.guide;
    _parentId = a?.parentId ?? widget.initialParentId;
    _isFolder = a?.isFolder ?? false;
    _loadParentName();
    if (a != null) {
      _titleCtrl.text = a.title;
      _tagsCtrl.text = a.tags.join(', ');
      try {
        final json = jsonDecode(a.body);
        final doc = Document.fromJson(json is List ? json : (json['ops'] ?? []));
        _controller = QuillController(document: doc, selection: const TextSelection.collapsed(offset: 0));
      } catch (_) {
        final doc = Document()..insert(0, a.body);
        _controller = QuillController(document: doc, selection: const TextSelection.collapsed(offset: 0));
      }
    } else {
      _controller = QuillController.basic();
    }

    _initialTitle = _titleCtrl.text;
    _initialTags = _tagsCtrl.text;
    _initialBody = _currentBody;
  }

  @override
  void dispose() {
    _controller.dispose();
    _titleCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _showError(_ru ? 'Введите заголовок' : 'Enter a title');
      return;
    }
    if (_controller.document.isEmpty()) {
      _showError(_ru ? 'Статья пуста' : 'Article is empty');
      return;
    }
    setState(() => _saving = true);
    try {
      final body = jsonEncode(_controller.document.toDelta().toJson());
      final tags = _tagsCtrl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
      ArticleModel article;
      if (widget.initial != null) {
        article = widget.initial!.copyWith(
          title: title, body: body, section: _section, tags: tags,
          updatedAt: DateTime.now(), parentId: _parentId, isFolder: _isFolder,
        );
        await KnowledgeService.save(article);
      } else {
        article = await KnowledgeService.create(
          title: title, body: body, section: _section, tags: tags,
          parentId: _parentId, isFolder: _isFolder,
        );
      }
      if (mounted) Navigator.pop(context, article);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.accentRed, behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _pickImageFromDevice() => MediaInsertHelper.pickImageFromDevice(context: context, controller: _controller, isRu: _ru, showError: _showError);
  Future<void> _pickVideoFromDevice() => MediaInsertHelper.pickVideoFromDevice(context: context, controller: _controller, isRu: _ru, showError: _showError);
  Future<void> _insertImageFromUrl() => MediaInsertHelper.insertImageFromUrl(context: context, controller: _controller, isRu: _ru, editorDialog: _editorDialog);
  Future<void> _insertAudioFromUrl() => MediaInsertHelper.insertAudioFromUrl(context: context, controller: _controller, isRu: _ru);
  Future<void> _pickAudioFromDevice() => MediaInsertHelper.pickAudioFromDevice(context: context, controller: _controller, isRu: _ru, showError: _showError);
  Future<void> _insertVideoFromUrl() => MediaInsertHelper.insertVideoFromUrl(context: context, controller: _controller, isRu: _ru, editorDialog: _editorDialog);
  Future<void> _insertLink() => MediaInsertHelper.insertLink(context: context, controller: _controller, isRu: _ru, editorDialog: _editorDialog);
  Future<void> _insertTable() => MediaInsertHelper.insertTable(context: context, controller: _controller, isRu: _ru, editorDialog: _editorDialog);

  Future<void> _insertChart() async {
    final result = await ChartInsertDialog.show(context, isRu: _ru);
    if (result == null) return;
    final index = _controller.selection.start;
    _controller.replaceText(index, 0, '\n', null);
    _controller.document.insert(index + 1, BlockEmbed.custom(_ChartEmbed(jsonEncode(result))));
  }

  void _insertEmoji(String emoji) {
    final index = _controller.selection.start;
    _controller.replaceText(index, 0, emoji, null);
    _controller.moveCursorToPosition(index + emoji.length);
  }

  void _toggleEmoji() {
    setState(() {
      _emojiVisible = !_emojiVisible;
      if (_emojiVisible) {
        _specialCharsVisible = false;
        FocusScope.of(context).unfocus();
      } else {
        _focusEditor();
      }
    });
  }

  void _insertSpecialChar(String ch) {
    final index = _controller.selection.start;
    _controller.replaceText(index, 0, ch, null);
    _controller.moveCursorToPosition(index + ch.length);
  }

  void _toggleSpecialChars() {
    setState(() {
      _specialCharsVisible = !_specialCharsVisible;
      if (_specialCharsVisible) {
        _emojiVisible = false;
        FocusScope.of(context).unfocus();
      } else {
        _focusEditor();
      }
    });
  }

  void _clearFormat() {
    _controller.formatSelection(Attribute.bold);
    _controller.formatSelection(Attribute.italic);
    _controller.formatSelection(Attribute.underline);
    _controller.formatSelection(Attribute.strikeThrough);
    _controller.formatSelection(Attribute.link);
  }

  void _focusEditor() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        final editorFocus = FocusNode();
        editorFocus.requestFocus();
      }
    });
  }

  Widget _editorDialog({required String title, required List<Widget> children, required bool Function() onConfirm}) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              const SizedBox(height: 16),
              ...children,
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: Text(WesiLocale.get('cancel'), style: TextStyle(color: AppTheme.textMuted))),
                  const Spacer(),
                  HoverButton(
                    onTap: () { if (onConfirm()) Navigator.pop(context, true); },
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    backgroundColor: AppTheme.accent,
                    child: Text(_ru ? 'Вставить' : 'Insert', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sectionLabel(ArticleSection s) => s.label(_ru);

  Future<void> _loadParentName() async {
    if (_parentId == null) { setState(() => _parentName = null); return; }
    final all = await KnowledgeService.getAll();
    final parent = all.firstWhere(
      (a) => a.id == _parentId,
      orElse: () => ArticleModel(id: '', title: _ru ? 'Не найдено' : 'Not found', body: '', createdAt: DateTime.now(), updatedAt: DateTime.now()),
    );
    setState(() => _parentName = parent.title);
  }

  Future<void> _selectParent() async {
    final all = await KnowledgeService.getAll();
    // Исключаем не только саму статью, но и ВСЕХ её потомков: иначе папку
    // можно положить внутрь папки, которая лежит в ней же. Такая петля
    // раньше вешала обход дерева (хлебные крошки крутились бесконечно).
    final forbidden = widget.initial == null
        ? const <String>{}
        : KnowledgeService.subtreeIds(widget.initial!.id);
    final folders =
        all.where((a) => a.isFolder && !forbidden.contains(a.id)).toList();
    if (folders.isEmpty) {
      _showError(_ru ? 'Нет папок. Создайте папку сначала.' : 'No folders. Create a folder first.');
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Text(_ru ? 'Выбрать родительскую папку' : 'Select parent folder', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: folders.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return ListTile(
                        leading: Icon(Icons.folder_off, color: AppTheme.textMuted, size: 20),
                        title: Text(_ru ? 'Без папки (корень)' : 'No folder (root)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                        onTap: () => Navigator.pop(context, ''),
                        dense: true,
                      );
                    }
                    final f = folders[i - 1];
                    return ListTile(
                      leading: Icon(Icons.folder, color: AppTheme.accent, size: 20),
                      title: Text(f.title, style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                      subtitle: Text(_sectionLabel(f.section), style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                      onTap: () => Navigator.pop(context, f.id),
                      dense: true,
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextButton(onPressed: () => Navigator.pop(context), child: Text(WesiLocale.get('cancel'), style: TextStyle(color: AppTheme.textMuted))),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) setState(() => _parentId = selected.isEmpty ? null : selected);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // На Android «назад» — системный жест, и без этого он уносил бы
      // несохранённое мимо всех проверок.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) Navigator.pop(context);
      },
      child: Scaffold(
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
                    icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                    onPressed: _leave,
                  ),
                  Expanded(
                    child: Text(
                      widget.initial == null ? (_ru ? 'Новая статья' : 'New article') : (_ru ? 'Редактирование' : 'Edit article'),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                    ),
                  ),
                  if (_saving)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent)),
                    ),
                  HoverButton(
                    onTap: _save,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    backgroundColor: AppTheme.accent,
                    child: Text(WesiLocale.get('save'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                  SizedBox(width: kHasCustomTitleBar ? 140 : 8),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _titleCtrl,
                    autofocus: widget.initial == null,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: _ru ? 'Заголовок статьи' : 'Article title',
                      hintStyle: TextStyle(color: AppTheme.textMuted.withOpacity(0.5)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ArticleSection.values.map((s) {
                      final sel = s == _section;
                      return GestureDetector(
                        onTap: () => setState(() => _section = s),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel ? AppTheme.accent.withOpacity(0.18) : AppTheme.surface.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: sel ? AppTheme.accent.withOpacity(0.6) : AppTheme.glassBorder),
                          ),
                          child: Text(_sectionLabel(s), style: TextStyle(fontSize: 12, color: sel ? AppTheme.accent : AppTheme.textSecondary)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tagsCtrl,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    decoration: InputDecoration(
                      hintText: _ru ? 'Теги через запятую' : 'Comma-separated tags',
                      hintStyle: TextStyle(fontSize: 12, color: AppTheme.textMuted.withOpacity(0.5)),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _selectParent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.surface.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.glassBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.folder_open, size: 14, color: AppTheme.accent),
                                const SizedBox(width: 6),
                                Flexible(child: Text(_parentName ?? (_ru ? 'Без папки' : 'No folder'), style: TextStyle(fontSize: 12, color: AppTheme.textSecondary), overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => setState(() => _isFolder = !_isFolder),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _isFolder ? AppTheme.accent.withOpacity(0.18) : AppTheme.surface.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _isFolder ? AppTheme.accent.withOpacity(0.6) : AppTheme.glassBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_isFolder ? Icons.check_box : Icons.check_box_outline_blank, size: 14, color: _isFolder ? AppTheme.accent : AppTheme.textMuted),
                              const SizedBox(width: 4),
                              Text(_ru ? 'Папка' : 'Folder', style: TextStyle(fontSize: 12, color: _isFolder ? AppTheme.accent : AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.transparent),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surface.withOpacity(0.3),
                border: Border(bottom: BorderSide(color: AppTheme.glassBorder)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _toolToggle(Icons.format_bold, _ru ? 'Жирный' : 'Bold', Attribute.bold),
                    _toolToggle(Icons.format_italic, _ru ? 'Курсив' : 'Italic', Attribute.italic),
                    _toolToggle(Icons.format_underline, _ru ? 'Подч.' : 'Underl.', Attribute.underline),
                    _toolToggle(Icons.format_strikethrough, _ru ? 'Зачёрк.' : 'Strike', Attribute.strikeThrough),
                    _divider(),
                    _toolLabeled(Icons.looks_one, 'H1', () => _controller.formatSelection(Attribute.h1)),
                    _toolLabeled(Icons.looks_two, 'H2', () => _controller.formatSelection(Attribute.h2)),
                    _toolLabeled(Icons.looks_3, 'H3', () => _controller.formatSelection(Attribute.h3)),
                    _divider(),
                    _toolLabeled(Icons.format_list_bulleted, _ru ? 'Список' : 'Bullet', () => _controller.formatSelection(Attribute.ul)),
                    _toolLabeled(Icons.format_list_numbered, _ru ? 'Нумер.' : 'Num.', () => _controller.formatSelection(Attribute.ol)),
                    _divider(),
                    _toolLabeled(Icons.link, _ru ? 'Ссылка' : 'Link', _insertLink),
                    _insertDrawer(),
                    _toolLabeled(Icons.emoji_emotions, 'Emoji', _toggleEmoji),
                    _toolLabeled(Icons.text_fields, _ru ? 'Спец.' : 'Chars', _toggleSpecialChars),
                    _divider(),
                    _toolLabeled(Icons.format_clear, _ru ? 'Очистить' : 'Clear', _clearFormat),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Container(
                color: AppTheme.background,
                child: QuillEditor.basic(
                  controller: _controller,
                  config: QuillEditorConfig(
                    scrollable: true,
                    autoFocus: widget.initial != null,
                    expands: true,
                    padding: const EdgeInsets.all(16),
                    customStyles: DefaultStyles(
                      h1: DefaultTextBlockStyle(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary), HorizontalSpacing.zero, const VerticalSpacing(12, 8), const VerticalSpacing(0, 0), null),
                      h2: DefaultTextBlockStyle(TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.accent), HorizontalSpacing.zero, const VerticalSpacing(10, 6), const VerticalSpacing(0, 0), null),
                      h3: DefaultTextBlockStyle(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary), HorizontalSpacing.zero, const VerticalSpacing(8, 4), const VerticalSpacing(0, 0), null),
                      paragraph: DefaultTextBlockStyle(TextStyle(fontSize: 14, height: 1.6, color: AppTheme.textSecondary), HorizontalSpacing.zero, const VerticalSpacing(0, 8), const VerticalSpacing(0, 0), null),
                      link: TextStyle(color: AppTheme.accent, decoration: TextDecoration.underline),
                      placeHolder: DefaultTextBlockStyle(TextStyle(fontSize: 14, color: AppTheme.textMuted), HorizontalSpacing.zero, const VerticalSpacing(0, 0), const VerticalSpacing(0, 0), null),
                    ),
                  ),
                ),
              ),
            ),
            if (_emojiVisible)
              Container(
                height: 220,
                decoration: BoxDecoration(color: AppTheme.surface.withOpacity(0.5), border: Border(top: BorderSide(color: AppTheme.glassBorder))),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Row(
                        children: [
                          Text(_ru ? 'Смайлики' : 'Emoji', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                          const Spacer(),
                          IconButton(icon: Icon(Icons.close, size: 18, color: AppTheme.textMuted), onPressed: () => setState(() => _emojiVisible = false), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 10, childAspectRatio: 1.2),
                        itemCount: emojiList.length,
                        itemBuilder: (context, i) => InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => _insertEmoji(emojiList[i]),
                          child: Center(child: Text(emojiList[i], style: const TextStyle(fontSize: 20))),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_specialCharsVisible)
              Container(
                height: 260,
                decoration: BoxDecoration(color: AppTheme.surface.withOpacity(0.5), border: Border(top: BorderSide(color: AppTheme.glassBorder))),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
                      child: Row(
                        children: [
                          Text(_ru ? 'Спецсимволы' : 'Special characters', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                          const Spacer(),
                          IconButton(icon: Icon(Icons.close, size: 18, color: AppTheme.textMuted), onPressed: () => setState(() => _specialCharsVisible = false), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        itemCount: specialCharCategories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (context, i) {
                          final cat = specialCharCategories[i];
                          final sel = cat.id == _specialCharCategoryId;
                          return GestureDetector(
                            onTap: () => setState(() => _specialCharCategoryId = cat.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: sel ? AppTheme.accent.withOpacity(0.18) : AppTheme.surface.withOpacity(0.35),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: sel ? AppTheme.accent.withOpacity(0.6) : AppTheme.glassBorder),
                              ),
                              child: Text(_ru ? cat.labelRu : cat.labelEn, style: TextStyle(fontSize: 11, fontWeight: sel ? FontWeight.w600 : FontWeight.w500, color: sel ? AppTheme.accent : AppTheme.textSecondary)),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final cat = specialCharCategories.firstWhere((c) => c.id == _specialCharCategoryId, orElse: () => specialCharCategories.first);
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 12, childAspectRatio: 1.15),
                            itemCount: cat.chars.length,
                            itemBuilder: (context, i) => InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => _insertSpecialChar(cat.chars[i]),
                              child: Center(child: Text(cat.chars[i], style: TextStyle(fontSize: 18, color: AppTheme.textPrimary))),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }

  /// Кнопка с подписью под иконкой
  Widget _toolLabeled(IconData icon, String label, VoidCallback onTap) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: AppTheme.textSecondary),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(fontSize: 8, color: AppTheme.textMuted, height: 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Toggle-кнопка форматирования (вкл/выкл)
  Widget _toolToggle(IconData icon, String label, Attribute attribute) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        final isActive = _controller.getSelectionStyle().attributes.containsKey(attribute.key);
        return Tooltip(
          message: label,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _controller.formatSelection(attribute),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: isActive
                    ? BoxDecoration(color: AppTheme.accent.withOpacity(0.15), borderRadius: BorderRadius.circular(6))
                    : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: isActive ? AppTheme.accent : AppTheme.textSecondary),
                    const SizedBox(height: 2),
                    Text(label, style: TextStyle(fontSize: 8, color: isActive ? AppTheme.accent : AppTheme.textMuted, height: 1)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _divider() {
    return Container(height: 28, width: 1, margin: const EdgeInsets.symmetric(horizontal: 4), color: AppTheme.glassBorder);
  }

  /// Выдвижная панель вставки медиа / таблиц / графиков
  Widget _insertDrawer() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toolLabeled(Icons.add_box, _ru ? 'Вставить' : 'Insert', () {
            setState(() => _insertDrawerOpen = !_insertDrawerOpen);
          }),
          if (_insertDrawerOpen) ...[
            const SizedBox(width: 2),
            _toolLabeled(Icons.image, _ru ? 'Фото URL' : 'Photo URL', _insertImageFromUrl),
            _toolLabeled(Icons.perm_media, _ru ? 'Фото устр.' : 'Photo dev.', _pickImageFromDevice),
            _toolLabeled(Icons.video_library, _ru ? 'Видео URL' : 'Video URL', _insertVideoFromUrl),
            _toolLabeled(Icons.video_file, _ru ? 'Видео устр.' : 'Video dev.', _pickVideoFromDevice),
            _toolLabeled(Icons.audiotrack, _ru ? 'Аудио URL' : 'Audio URL', _insertAudioFromUrl),
            _toolLabeled(Icons.library_music, _ru ? 'Аудио устр.' : 'Audio dev.', _pickAudioFromDevice),
            _toolLabeled(Icons.insert_chart, _ru ? 'График' : 'Chart', _insertChart),
            _toolLabeled(Icons.table_chart, _ru ? 'Таблица' : 'Table', _insertTable),
          ],
        ],
      ),
    );
  }
}
