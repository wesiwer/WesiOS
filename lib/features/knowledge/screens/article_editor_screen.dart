import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hover_button.dart';
import '../../../core/widgets/window_controls.dart';
import '../models/article_model.dart';
import '../services/knowledge_service.dart';

// ─── Custom Block Embeds ────────────────────────────────────────────────────

class _TableEmbed extends CustomBlockEmbed {
  const _TableEmbed(String value) : super(_type, value);
  static const String _type = 'table';
}

class _VideoEmbed extends CustomBlockEmbed {
  const _VideoEmbed(String value) : super(_type, value);
  static const String _type = 'video';
}

// ─── Emoji Data ─────────────────────────────────────────────────────────────

const _emojiList = [
  '😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇','🥰','😍','🤩',
  '😘','😗','😚','😙','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','🤐','🤨',
  '😐','😑','😶','😏','😒','🙄','😬','🤥','😌','😔','😪','🤤','😴','😷','🤒','🤕',
  '🤢','🤮','🤧','🥵','🥶','🥴','😵','🤯','🤠','🥳','😎','🤓','🧐','😕','😟','🙁',
  '☹️','😮','😯','😲','😳','🥺','😦','😧','😨','😰','😥','😢','😭','😱','😖','😣',
  '😞','😓','😩','😫','🥱','😤','😡','😠','🤬','😈','👿','💀','☠️','💩','🤡','👹',
  '👺','👻','👽','👾','🤖','😺','😸','😹','😻','😼','😽','🙀','😿','😾','❤️','🧡',
  '💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕','💞','💓','💗','💖','💘','💝',
  '💟','☮️','✝️','☪️','🕉️','☸️','✡️','🔯','🕎','☯️','☦️','🛐','⛎','♈','♉','♊',
  '♋','♌','♍','♎','♏','♐','♑','♒','♓','🆔','⚛️','🉑','☢️','☣️','📴','📳',
  '🈶','🈚','🈸','🈺','🈷️','✴️','🆚','💮','🉐','㊙️','㊗️','🈴','🈵','🈹','🈲','🅰️',
  '🅱️','🆎','🆑','🅾️','🆘','❌','⭕','🛑','⛔','📛','🚫','💯','💢','♨️','🚷','🚯',
  '🚳','🚱','🔞','📵','🚭','❗','❕','❓','❔','‼️','⁉️','🔅','🔆','〽️','⚠️','🚸',
  '🔱','⚜️','🔰','♻️','✅','🈯','💹','❇️','✳️','❎','🌐','💠','Ⓜ️','🌀','💤','🏧',
  '🚾','♿','🅿️','🈳','🈂','🛂','🛃','🛄','🛅','🛗','🔄','🔃','➡️','⬅️','⬆️','⬇️',
  '↗️','↘️','↙️','↖️','↕️','↔️','↪️','↩️','⤴️','⤵️','🔀','🔁','🔂','🔄','🔃','🎵',
  '🎶','➕','➖','➗','✖️','💲','💱','™️','©️','®️','〰️','➰','➿','🔚','🔙','🔛',
  '🔝','🔜','✔️','☑️','🔘','🔴','🟠','🟡','🟢','🔵','🟣','⚫','⚪','🟤','🔺','🔻',
  '🔸','🔹','🔶','🔷','🔳','🔲','▪️','▫️','◾','◽','◼️','◻️','🟥','🟧','🟨','🟩',
  '🟦','🟪','⬛','⬜','🟫','🔈','🔇','🔉','🔊','🔔','🔕','📣','📢','💬','💭','🗯️',
  '♠️','♣️','♥️','♦️','🃏','🎴','🀄','🕐','🕑','🕒','🕓','🕔','🕕','🕖','🕗','🕘',
  '🕙','🕚','🕛','🕜','🕝','🕞','🕟','🕠','🕡','🕢','🕣','🕤','🕥','🕦','🕧',
];

// ─── Editor Screen ──────────────────────────────────────────────────────────

/// Полноэкранный rich-редактор статей.
///
/// Поддерживает:
/// - Форматирование текста (bold, italic, underline, strike)
/// - Заголовки H1/H2/H3
/// - Списки (bullet, numbered)
/// - Ссылки (https:// и wesios://article/ID)
/// - Изображения: по URL или из галереи/папки устройства
/// - Видео: по URL или из галереи/папки устройства
/// - Таблицы (диалог строки×столбцы)
/// - Emoji
/// - Сохранение в Quill Delta JSON
class ArticleEditorScreen extends StatefulWidget {
  final ArticleModel? initial;
  const ArticleEditorScreen({super.key, this.initial});

  static Future<ArticleModel?> open(BuildContext context, {ArticleModel? initial}) {
    return Navigator.push<ArticleModel>(
      context,
      MaterialPageRoute(builder: (_) => ArticleEditorScreen(initial: initial)),
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
  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    _section = a?.section ?? ArticleSection.playbook;
    if (a != null) {
      _titleCtrl.text = a.title;
      _tagsCtrl.text = a.tags.join(', ');
      _controller = _controllerFromBody(a.body);
    } else {
      _controller = QuillController.basic();
    }
  }

  QuillController _controllerFromBody(String body) {
    try {
      final json = jsonDecode(body);
      final doc = Document.fromJson(json is List ? json : (json['ops'] ?? []));
      return QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
    } catch (_) {
      final doc = Document()..insert(0, body);
      return QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _titleCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  // ─── Save ─────────────────────────────────────────────────────────────────

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
      final tags = _tagsCtrl.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      ArticleModel article;
      if (widget.initial != null) {
        article = widget.initial!.copyWith(
          title: title,
          body: body,
          section: _section,
          tags: tags,
          updatedAt: DateTime.now(),
        );
        await KnowledgeService.save(article);
      } else {
        article = await KnowledgeService.create(
          title: title,
          body: body,
          section: _section,
          tags: tags,
        );
      }
      if (mounted) Navigator.pop(context, article);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.accentRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─── File Pickers (Gallery / Folder) ──────────────────────────────────────

  Future<void> _pickImageFromDevice() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final path = file.path;
    if (path == null) {
      _showError(_ru ? 'Не удалось получить файл' : 'Could not access file');
      return;
    }
    // Копируем во временную директорию приложения, чтобы путь был стабильным
    final savedPath = await _copyToAppDir(path, 'images');
    if (savedPath == null) {
      _showError(_ru ? 'Не удалось сохранить файл' : 'Could not save file');
      return;
    }
    final index = _controller.selection.start;
    _controller.replaceText(index, 0, '\n', null);
    _controller.document.insert(index + 1, BlockEmbed.image(savedPath));
  }

  Future<void> _pickVideoFromDevice() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final path = file.path;
    if (path == null) {
      _showError(_ru ? 'Не удалось получить файл' : 'Could not access file');
      return;
    }
    final savedPath = await _copyToAppDir(path, 'videos');
    if (savedPath == null) {
      _showError(_ru ? 'Не удалось сохранить файл' : 'Could not save file');
      return;
    }
    final index = _controller.selection.start;
    _controller.replaceText(index, 0, '\n', null);
    _controller.document.insert(
      index + 1,
      BlockEmbed.custom(_VideoEmbed(savedPath)),
    );
  }

  Future<String?> _copyToAppDir(String sourcePath, String subDir) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory('${appDir.path}/knowledge/$subDir');
      if (!targetDir.existsSync()) targetDir.createSync(recursive: true);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${sourcePath.split(Platform.pathSeparator).last}';
      final targetPath = '${targetDir.path}/$fileName';
      await File(sourcePath).copy(targetPath);
      return targetPath;
    } catch (e) {
      debugPrint('Copy error: $e');
      return null;
    }
  }

  // ─── Insert by URL ────────────────────────────────────────────────────────

  Future<void> _insertImageFromUrl() async {
    final urlCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _editorDialog(
        title: _ru ? 'Вставить изображение по ссылке' : 'Insert image from URL',
        children: [
          TextField(
            controller: urlCtrl,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'URL',
              labelStyle: TextStyle(color: AppTheme.textMuted),
              helperText: _ru
                  ? 'Ссылка на изображение в интернете'
                  : 'Link to image on the web',
              helperStyle: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ),
        ],
        onConfirm: () => urlCtrl.text.trim().isNotEmpty,
      ),
    );
    if (ok == true && urlCtrl.text.trim().isNotEmpty) {
      final index = _controller.selection.start;
      _controller.replaceText(index, 0, '\n', null);
      _controller.document.insert(index + 1, BlockEmbed.image(urlCtrl.text.trim()));
    }
    urlCtrl.dispose();
  }

  Future<void> _insertVideoFromUrl() async {
    final urlCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _editorDialog(
        title: _ru ? 'Вставить видео по ссылке' : 'Insert video from URL',
        children: [
          TextField(
            controller: urlCtrl,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'URL (MP4, WebM)',
              labelStyle: TextStyle(color: AppTheme.textMuted),
              helperText: _ru ? 'Прямая ссылка на видео' : 'Direct video link',
              helperStyle: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ),
        ],
        onConfirm: () => urlCtrl.text.trim().isNotEmpty,
      ),
    );
    if (ok == true && urlCtrl.text.trim().isNotEmpty) {
      final index = _controller.selection.start;
      _controller.replaceText(index, 0, '\n', null);
      _controller.document.insert(
        index + 1,
        BlockEmbed.custom(_VideoEmbed(urlCtrl.text.trim())),
      );
    }
    urlCtrl.dispose();
  }

  // ─── Link ─────────────────────────────────────────────────────────────────

  Future<void> _insertLink() async {
    final urlCtrl = TextEditingController();
    final textCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _editorDialog(
        title: _ru ? 'Вставить ссылку' : 'Insert link',
        children: [
          TextField(
            controller: textCtrl,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: _ru ? 'Текст ссылки' : 'Link text',
              labelStyle: TextStyle(color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: urlCtrl,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'URL (https:// или wesios://)',
              labelStyle: TextStyle(color: AppTheme.textMuted),
              helperText: _ru
                  ? 'wesios://article/ID — ссылка на статью'
                  : 'wesios://article/ID — link to article',
              helperStyle: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ),
        ],
        onConfirm: () => urlCtrl.text.trim().isNotEmpty,
      ),
    );
    if (ok == true) {
      final index = _controller.selection.start;
      final len = _controller.selection.end - index;
      final text = textCtrl.text.trim().isNotEmpty ? textCtrl.text.trim() : urlCtrl.text.trim();
      _controller.replaceText(index, len, text, null);
      _controller.formatText(index, text.length, LinkAttribute(urlCtrl.text.trim()));
    }
    urlCtrl.dispose();
    textCtrl.dispose();
  }

  // ─── Table ────────────────────────────────────────────────────────────────

  Future<void> _insertTable() async {
    final rowsCtrl = TextEditingController(text: '3');
    final colsCtrl = TextEditingController(text: '3');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _editorDialog(
        title: _ru ? 'Вставить таблицу' : 'Insert table',
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: rowsCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: _ru ? 'Строки' : 'Rows',
                    labelStyle: TextStyle(color: AppTheme.textMuted),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: colsCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: _ru ? 'Столбцы' : 'Columns',
                    labelStyle: TextStyle(color: AppTheme.textMuted),
                  ),
                ),
              ),
            ],
          ),
        ],
        onConfirm: () => true,
      ),
    );
    if (ok == true) {
      final rows = int.tryParse(rowsCtrl.text) ?? 3;
      final cols = int.tryParse(colsCtrl.text) ?? 3;
      final tableData = List.generate(
        rows,
        (r) => List.generate(cols, (c) => r == 0 ? 'Header ${c + 1}' : 'Cell ${r + 1},${c + 1}'),
      );
      final index = _controller.selection.start;
      _controller.replaceText(index, 0, '\n', null);
      _controller.document.insert(
        index + 1,
        BlockEmbed.custom(_TableEmbed(jsonEncode(tableData))),
      );
    }
    rowsCtrl.dispose();
    colsCtrl.dispose();
  }

  // ─── Emoji ────────────────────────────────────────────────────────────────

  void _insertEmoji(String emoji) {
    final index = _controller.selection.start;
    _controller.replaceText(index, 0, emoji, null);
  }

  void _toggleEmoji() {
    setState(() => _emojiVisible = !_emojiVisible);
    if (_emojiVisible) {
      FocusScope.of(context).unfocus();
    }
  }

  // ─── Clear Format ─────────────────────────────────────────────────────────

  void _clearFormat() {
    _controller.formatSelection(Attribute.bold);
    _controller.formatSelection(Attribute.italic);
    _controller.formatSelection(Attribute.underline);
    _controller.formatSelection(Attribute.strikeThrough);
    _controller.formatSelection(Attribute.link);
  }

  // ─── Dialog helper ────────────────────────────────────────────────────────

  Widget _editorDialog({
    required String title,
    required List<Widget> children,
    required bool Function() onConfirm,
  }) {
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
              Text(
                title,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 16),
              ...children,
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(WesiLocale.get('cancel'), style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const Spacer(),
                  HoverButton(
                    onTap: () {
                      if (onConfirm()) Navigator.pop(context, true);
                    },
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    backgroundColor: AppTheme.accent,
                    child: Text(
                      _ru ? 'Вставить' : 'Insert',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Section label ────────────────────────────────────────────────────────

  String _sectionLabel(ArticleSection s) => switch (s) {
        ArticleSection.about => _ru ? 'О программе' : 'About',
        ArticleSection.playbook => _ru ? 'Регламенты' : 'Playbooks',
        ArticleSection.guide => _ru ? 'Инструкции' : 'Guides',
        ArticleSection.finance => _ru ? 'Финансы' : 'Finance',
        ArticleSection.personal => _ru ? 'Личное' : 'Personal',
      };

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      widget.initial == null
                          ? (_ru ? 'Новая статья' : 'New article')
                          : (_ru ? 'Редактирование' : 'Edit article'),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                    ),
                  ),
                  if (_saving)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                      ),
                    ),
                  HoverButton(
                    onTap: _save,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    backgroundColor: AppTheme.accent,
                    child: Text(
                      WesiLocale.get('save'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(width: kHasCustomTitleBar ? 140 : 8),
                ],
              ),
            ),
            // Title + meta
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
                            border: Border.all(
                              color: sel ? AppTheme.accent.withOpacity(0.6) : AppTheme.glassBorder,
                            ),
                          ),
                          child: Text(
                            _sectionLabel(s),
                            style: TextStyle(fontSize: 12, color: sel ? AppTheme.accent : AppTheme.textSecondary),
                          ),
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
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.transparent),
            // Toolbar
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
                    _tool(Icons.format_bold, _ru ? 'Жирный' : 'Bold', () => _controller.formatSelection(Attribute.bold)),
                    _tool(Icons.format_italic, _ru ? 'Курсив' : 'Italic', () => _controller.formatSelection(Attribute.italic)),
                    _tool(Icons.format_underline, _ru ? 'Подчёркнутый' : 'Underline', () => _controller.formatSelection(Attribute.underline)),
                    _tool(Icons.format_strikethrough, _ru ? 'Зачёркнутый' : 'Strikethrough', () => _controller.formatSelection(Attribute.strikeThrough)),
                    _divider(),
                    _tool(Icons.format_h1, 'H1', () => _controller.formatSelection(Attribute.h1)),
                    _tool(Icons.format_h2, 'H2', () => _controller.formatSelection(Attribute.h2)),
                    _tool(Icons.format_h3, 'H3', () => _controller.formatSelection(Attribute.h3)),
                    _divider(),
                    _tool(Icons.format_list_bulleted, _ru ? 'Список' : 'Bullet', () => _controller.formatSelection(Attribute.ul)),
                    _tool(Icons.format_list_numbered, _ru ? 'Нумерация' : 'Numbered', () => _controller.formatSelection(Attribute.ol)),
                    _divider(),
                    _tool(Icons.link, _ru ? 'Ссылка' : 'Link', _insertLink),
                    _tool(Icons.image, _ru ? 'Фото URL' : 'Photo URL', _insertImageFromUrl),
                    _tool(Icons.perm_media, _ru ? 'Фото с устройства' : 'Photo from device', _pickImageFromDevice),
                    _tool(Icons.video_library, _ru ? 'Видео URL' : 'Video URL', _insertVideoFromUrl),
                    _tool(Icons.video_file, _ru ? 'Видео с устройства' : 'Video from device', _pickVideoFromDevice),
                    _tool(Icons.table_chart, _ru ? 'Таблица' : 'Table', _insertTable),
                    _tool(Icons.emoji_emotions, _ru ? 'Emoji' : 'Emoji', _toggleEmoji),
                    _divider(),
                    _tool(Icons.format_clear, _ru ? 'Очистить' : 'Clear', _clearFormat),
                  ],
                ),
              ),
            ),
            // Editor
            Expanded(
              child: Container(
                color: AppTheme.background,
                child: QuillEditor(
                  controller: _controller,
                  scrollController: ScrollController(),
                  scrollable: true,
                  focusNode: FocusNode(),
                  autoFocus: widget.initial != null,
                  readOnly: false,
                  expands: true,
                  padding: const EdgeInsets.all(16),
                  customStyles: DefaultStyles(
                    h1: DefaultTextBlockStyle(
                      TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                      const VerticalSpacing(12, 8),
                      const VerticalSpacing(0, 0),
                      null,
                    ),
                    h2: DefaultTextBlockStyle(
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.accent),
                      const VerticalSpacing(10, 6),
                      const VerticalSpacing(0, 0),
                      null,
                    ),
                    h3: DefaultTextBlockStyle(
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                      const VerticalSpacing(8, 4),
                      const VerticalSpacing(0, 0),
                      null,
                    ),
                    paragraph: DefaultTextBlockStyle(
                      TextStyle(fontSize: 14, height: 1.6, color: AppTheme.textSecondary),
                      const VerticalSpacing(0, 8),
                      const VerticalSpacing(0, 0),
                      null,
                    ),
                    link: TextStyle(color: AppTheme.accent, decoration: TextDecoration.underline),
                    placeHolder: DefaultTextBlockStyle(
                      TextStyle(fontSize: 14, color: AppTheme.textMuted),
                      const VerticalSpacing(0, 0),
                      const VerticalSpacing(0, 0),
                      null,
                    ),
                  ),
                ),
              ),
            ),
            // Emoji panel
            if (_emojiVisible)
              Container(
                height: 220,
                decoration: BoxDecoration(
                  color: AppTheme.surface.withOpacity(0.5),
                  border: Border(top: BorderSide(color: AppTheme.glassBorder)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Row(
                        children: [
                          Text(
                            _ru ? 'Смайлики' : 'Emoji',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(Icons.close, size: 18, color: AppTheme.textMuted),
                            onPressed: () => setState(() => _emojiVisible = false),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 10,
                          childAspectRatio: 1.2,
                        ),
                        itemCount: _emojiList.length,
                        itemBuilder: (context, i) => InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => _insertEmoji(_emojiList[i]),
                          child: Center(
                            child: Text(_emojiList[i], style: const TextStyle(fontSize: 20)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tool(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: AppTheme.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      height: 20,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: AppTheme.glassBorder,
    );
  }
}
