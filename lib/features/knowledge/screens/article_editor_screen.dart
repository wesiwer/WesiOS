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

/// Article editor with special characters (Word-like) and emoji panels.
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
  bool _saving = false;
  bool _emojiVisible = false;
  bool _specialCharsVisible = false;
  String _specialCharCategoryId = 'punct';
  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    _section = a?.section ?? ArticleSection.playbook;
    if (a != null) {
      _titleCtrl.text = a.title;
      _tagsCtrl.text = a.tags.join(', ');
      try {
        final json = jsonDecode(a.body);
        final doc = Document.fromJson(json is List ? json : (json['ops'] ?? []));
        _controller = QuillController(document: doc, selection: const TextSelection.collapsed(offset: 0));
      } catch (_) {
        _controller = QuillController.basic();
      }
    } else {
      _controller = QuillController.basic();
    }
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
    if (title.isEmpty) return;
    setState(() => _saving = true);
    try {
      final body = jsonEncode(_controller.document.toDelta().toJson());
      final tags = _tagsCtrl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
      ArticleModel article;
      if (widget.initial != null) {
        article = widget.initial!.copyWith(title: title, body: body, section: _section, tags: tags, updatedAt: DateTime.now());
        await KnowledgeService.save(article);
      } else {
        article = await KnowledgeService.create(title: title, body: body, section: _section, tags: tags, parentId: widget.initialParentId);
      }
      if (mounted) Navigator.pop(context, article);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _insertText(String s) {
    final index = _controller.selection.start;
    _controller.replaceText(index, 0, s, null);
  }

  void _toggleEmoji() {
    setState(() {
      _emojiVisible = !_emojiVisible;
      if (_emojiVisible) _specialCharsVisible = false;
    });
  }

  void _toggleSpecialChars() {
    setState(() {
      _specialCharsVisible = !_specialCharsVisible;
      if (_specialCharsVisible) _emojiVisible = false;
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
                  IconButton(icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary), onPressed: () => Navigator.pop(context)),
                  Expanded(child: Text(widget.initial == null ? (_ru ? 'Новая статья' : 'New article') : (_ru ? 'Редактирование' : 'Edit article'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary))),
                  HoverButton(onTap: _save, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), backgroundColor: AppTheme.accent, child: Text(WesiLocale.get('save'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                  SizedBox(width: kHasCustomTitleBar ? 140 : 8),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(controller: _titleCtrl, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textPrimary), decoration: InputDecoration(hintText: _ru ? 'Заголовок статьи' : 'Article title', border: InputBorder.none)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: AppTheme.surface.withOpacity(0.3), border: Border(bottom: BorderSide(color: AppTheme.glassBorder))),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _tool(Icons.format_bold, () => _controller.formatSelection(Attribute.bold)),
                    _tool(Icons.format_italic, () => _controller.formatSelection(Attribute.italic)),
                    _tool(Icons.format_underline, () => _controller.formatSelection(Attribute.underline)),
                    _tool(Icons.format_strikethrough, () => _controller.formatSelection(Attribute.strikeThrough)),
                    _tool(Icons.looks_one, () => _controller.formatSelection(Attribute.h1)),
                    _tool(Icons.looks_two, () => _controller.formatSelection(Attribute.h2)),
                    _tool(Icons.looks_3, () => _controller.formatSelection(Attribute.h3)),
                    _tool(Icons.format_list_bulleted, () => _controller.formatSelection(Attribute.ul)),
                    _tool(Icons.format_list_numbered, () => _controller.formatSelection(Attribute.ol)),
                    _tool(Icons.emoji_emotions, _toggleEmoji),
                    _tool(Icons.text_fields, _toggleSpecialChars),
                  ],
                ),
              ),
            ),
            Expanded(
              child: QuillEditor.basic(
                controller: _controller,
                configurations: QuillEditorConfigurations(
                  scrollable: true,
                  focusNode: FocusNode(),
                  autoFocus: false,
                  readOnly: false,
                  expands: true,
                  padding: const EdgeInsets.all(16),
                  customStyles: DefaultStyles(
                    paragraph: DefaultTextBlockStyle(TextStyle(fontSize: 14, height: 1.6, color: AppTheme.textSecondary), const VerticalSpacing(0, 8), const VerticalSpacing(0, 0), null),
                  ),
                ),
              ),
            ),
            if (_emojiVisible)
              Container(
                height: 200,
                decoration: BoxDecoration(color: AppTheme.surface.withOpacity(0.5), border: Border(top: BorderSide(color: AppTheme.glassBorder))),
                child: GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 10, childAspectRatio: 1.2),
                  itemCount: emojiList.length,
                  itemBuilder: (context, i) => InkWell(onTap: () => _insertText(emojiList[i]), child: Center(child: Text(emojiList[i], style: const TextStyle(fontSize: 20)))),
                ),
              ),
            if (_specialCharsVisible)
              Container(
                height: 260,
                decoration: BoxDecoration(color: AppTheme.surface.withOpacity(0.5), border: Border(top: BorderSide(color: AppTheme.glassBorder))),
                child: Column(
                  children: [
                    SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                              child: Text(_ru ? cat.labelRu : cat.labelEn, style: TextStyle(fontSize: 11, color: sel ? AppTheme.accent : AppTheme.textSecondary)),
                            ),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: Builder(builder: (context) {
                        final cat = specialCharCategories.firstWhere((c) => c.id == _specialCharCategoryId, orElse: () => specialCharCategories.first);
                        return GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 12, childAspectRatio: 1.15),
                          itemCount: cat.chars.length,
                          itemBuilder: (context, i) => InkWell(onTap: () => _insertText(cat.chars[i]), child: Center(child: Text(cat.chars[i], style: TextStyle(fontSize: 18, color: AppTheme.textPrimary)))),
                        );
                      }),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tool(IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, size: 18, color: AppTheme.textSecondary)),
    );
  }
}
