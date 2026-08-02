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

// ─── Chart Row Helper ─────────────────────────────────────────────────────

class _ChartRow {
  final String label;
  final double value;
  const _ChartRow({required this.label, required this.value});
  _ChartRow copyWith({String? label, double? value}) =>
      _ChartRow(label: label ?? this.label, value: value ?? this.value);
}


// ─── Custom Block Embeds ────────────────────────────────────────────────────

class _TableEmbed extends CustomBlockEmbed {
  const _TableEmbed(String value) : super(_type, value);
  static const String _type = 'table';
}

class _VideoEmbed extends CustomBlockEmbed {
  const _VideoEmbed(String value) : super(_type, value);
  static const String _type = 'video';
}

class _AudioEmbed extends CustomBlockEmbed {
  const _AudioEmbed(String value) : super(_type, value);
  static const String _type = 'audio';
}

class _ChartEmbed extends CustomBlockEmbed {
  const _ChartEmbed(String value) : super(_type, value);
  static const String _type = 'chart';
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
  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    _section = a?.section ?? ArticleSection.playbook;
    _parentId = a?.parentId ?? widget.initialParentId;
    _isFolder = a?.isFolder ?? false;
    _loadParentName();
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
          parentId: _parentId,
          isFolder: _isFolder,
        );
        await KnowledgeService.save(article);
      } else {
        article = await KnowledgeService.create(
          title: title,
          body: body,
          section: _section,
          tags: tags,
          parentId: _parentId,
          isFolder: _isFolder,
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

  Future<void> _insertAudioFromUrl() async {
    final urlCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
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
                  _ru ? 'Вставить аудио' : 'Insert audio',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: urlCtrl,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'URL аудио (MP3)',
                    labelStyle: TextStyle(color: AppTheme.textMuted),
                    helperText: _ru ? 'Прямая ссылка на аудио-файл' : 'Direct link to audio file',
                    helperStyle: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(WesiLocale.get('cancel'), style: TextStyle(color: AppTheme.textMuted)),
                    ),
                    const Spacer(),
                    HoverButton(
                      onTap: () => Navigator.pop(context, true),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      backgroundColor: AppTheme.accent,
                      child: Text(
                        WesiLocale.get('insert'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok == true && urlCtrl.text.trim().isNotEmpty) {
      final index = _controller.selection.start;
      _controller.replaceText(index, 0, '
', null);
      _controller.document.insert(index + 1, BlockEmbed.custom(_AudioEmbed(urlCtrl.text.trim())));
    }
    urlCtrl.dispose();
  }

  Future<void> _pickAudioFromDevice() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.path == null) return;
      final appDir = await getApplicationDocumentsDirectory();
      final destDir = Directory('${appDir.path}/knowledge/audio');
      if (!await destDir.exists()) await destDir.create(recursive: true);
      final dest = File('${destDir.path}/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
      await File(file.path!).copy(dest.path);
      final index = _controller.selection.start;
      _controller.replaceText(index, 0, '
', null);
      _controller.document.insert(index + 1, BlockEmbed.custom(_AudioEmbed(dest.path)));
    } catch (e) {
      _showError(_ru ? 'Ошибка загрузки аудио' : 'Audio upload error');
    }
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

  // ─── Chart / Diagram with visual editor + data sources ────────────────────

  Future<void> _insertChart() async {
    final result = await _showChartDialog();
    if (result == null) return;
    final index = _controller.selection.start;
    _controller.replaceText(index, 0, '\n', null);
    _controller.document.insert(
      index + 1,
      BlockEmbed.custom(_ChartEmbed(jsonEncode(result))),
    );
  }

  Future<Map<String, dynamic>?> _showChartDialog() async {
    String chartType = 'bar';
    final titleCtrl = TextEditingController();
    String dataSource = 'manual'; // manual | forecast | analytics | treasury
    final rows = <_ChartRow>[const _ChartRow(label: '', value: 0)];

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: AppTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _ru ? 'График / Диаграмма' : 'Chart / Diagram',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, size: 18, color: AppTheme.textMuted),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Chart type
                          Text(_ru ? 'Тип графика' : 'Chart type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _chartTypeChip('bar', _ru ? 'Столбчатый' : 'Bar', Icons.bar_chart, chartType, (v) => setDialogState(() => chartType = v)),
                              _chartTypeChip('line', _ru ? 'Линейный' : 'Line', Icons.show_chart, chartType, (v) => setDialogState(() => chartType = v)),
                              _chartTypeChip('pie', _ru ? 'Круговой' : 'Pie', Icons.pie_chart, chartType, (v) => setDialogState(() => chartType = v)),
                              _chartTypeChip('area', _ru ? 'Областной' : 'Area', Icons.area_chart, chartType, (v) => setDialogState(() => chartType = v)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Title
                          TextField(
                            controller: titleCtrl,
                            style: TextStyle(color: AppTheme.textPrimary),
                            decoration: InputDecoration(
                              labelText: _ru ? 'Заголовок' : 'Title',
                              labelStyle: TextStyle(color: AppTheme.textMuted),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.glassBorder)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.glassBorder)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Data source
                          Text(_ru ? 'Источник данных' : 'Data source', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _dataSourceChip('manual', _ru ? 'Вручную' : 'Manual', Icons.edit, dataSource, (v) => setDialogState(() => dataSource = v)),
                              _dataSourceChip('forecast', _ru ? 'Прогноз' : 'Forecast', Icons.trending_up, dataSource, (v) => setDialogState(() => dataSource = v)),
                              _dataSourceChip('analytics', _ru ? 'Аналитика' : 'Analytics', Icons.analytics, dataSource, (v) => setDialogState(() => dataSource = v)),
                              _dataSourceChip('treasury', _ru ? 'Treasury' : 'Treasury', Icons.account_balance_wallet, dataSource, (v) => setDialogState(() => dataSource = v)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Data editor
                          if (dataSource == 'manual')
                            _buildManualEditor(rows, setDialogState)
                          else
                            _buildLinkedDataPreview(dataSource),
                        ],
                      ),
                    ),
                  ),
                  // Footer
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(WesiLocale.get('cancel'), style: TextStyle(color: AppTheme.textMuted)),
                        ),
                        const Spacer(),
                        HoverButton(
                          onTap: () {
                            final data = _buildChartData(chartType, titleCtrl.text.trim(), dataSource, rows);
                            if (data != null) Navigator.pop(context, data);
                          },
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          backgroundColor: AppTheme.accent,
                          child: Text(
                            _ru ? 'Вставить график' : 'Insert chart',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _chartTypeChip(String value, String label, IconData icon, String selected, ValueChanged<String> onTap) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accent.withOpacity(0.18) : AppTheme.surface.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AppTheme.accent.withOpacity(0.6) : AppTheme.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? AppTheme.accent : AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, color: isSelected ? AppTheme.accent : AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _dataSourceChip(String value, String label, IconData icon, String selected, ValueChanged<String> onTap) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentGreen.withOpacity(0.18) : AppTheme.surface.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AppTheme.accentGreen.withOpacity(0.6) : AppTheme.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? AppTheme.accentGreen : AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, color: isSelected ? AppTheme.accentGreen : AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildManualEditor(List<_ChartRow> rows, StateSetter setDialogState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(_ru ? 'Подпись' : 'Label', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Text(_ru ? 'Значение' : 'Value', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ),
            const SizedBox(width: 32),
          ],
        ),
        const SizedBox(height: 4),
        ...rows.asMap().entries.map((entry) {
          final i = entry.key;
          final row = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: TextEditingController(text: row.label),
                    onChanged: (v) => rows[i] = row.copyWith(label: v),
                    style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: _ru ? 'Янв' : 'Jan',
                      hintStyle: TextStyle(fontSize: 12, color: AppTheme.textMuted.withOpacity(0.4)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppTheme.glassBorder)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: TextEditingController(text: row.value.toString()),
                    onChanged: (v) => rows[i] = row.copyWith(value: double.tryParse(v) ?? 0),
                    keyboardType: TextInputType.number,
                    style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: '100',
                      hintStyle: TextStyle(fontSize: 12, color: AppTheme.textMuted.withOpacity(0.4)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppTheme.glassBorder)),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.remove_circle, size: 18, color: AppTheme.accentRed.withOpacity(0.7)),
                  onPressed: rows.length > 1 ? () => setDialogState(() => rows.removeAt(i)) : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 6),
        HoverButton(
          onTap: () => setDialogState(() => rows.add(const _ChartRow(label: '', value: 0))),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          backgroundColor: AppTheme.surface.withOpacity(0.4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 16, color: AppTheme.accent),
              const SizedBox(width: 4),
              Text(_ru ? 'Добавить строку' : 'Add row', style: TextStyle(fontSize: 12, color: AppTheme.accent)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLinkedDataPreview(String source) {
    String title;
    String description;
    switch (source) {
      case 'forecast':
        title = _ru ? 'Прогноз Wesi Forecast' : 'Wesi Forecast';
        description = _ru
            ? 'График будет построен на основе данных прогноза (Holt-Winters + Monte-Carlo). При открытии статьи данные подгрузятся актуальные.'
            : 'Chart based on forecast data (Holt-Winters + Monte-Carlo). Live data on article open.';
      case 'analytics':
        title = _ru ? 'Аналитика WesiOS' : 'WesiOS Analytics';
        description = _ru
            ? 'График будет построен на основе данных аналитики (транзакции, метрики, heatmap). Актуальные данные при каждом открытии.'
            : 'Chart based on analytics data (transactions, metrics, heatmap). Live data on every open.';
      case 'treasury':
        title = _ru ? 'Wesi Treasury' : 'Wesi Treasury';
        description = _ru
            ? 'График баланса на основе реальных транзакций. Данные обновляются при открытии статьи.'
            : 'Balance chart based on real transactions. Data updates on article open.';
      default:
        title = '';
        description = '';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accentGreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accentGreen.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link, size: 16, color: AppTheme.accentGreen),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accentGreen)),
            ],
          ),
          const SizedBox(height: 6),
          Text(description, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.5)),
        ],
      ),
    );
  }

  Map<String, dynamic>? _buildChartData(String type, String title, String source, List<_ChartRow> rows) {
    if (source == 'manual') {
      final validRows = rows.where((r) => r.label.isNotEmpty).toList();
      if (validRows.isEmpty) return null;
      return {
        'type': type,
        'title': title,
        'source': 'manual',
        'data': validRows.map((r) => r.value).toList(),
        'labels': validRows.map((r) => r.label).toList(),
      };
    }
    // Linked data — сохраняем только тип и источник, данные подгружаются при рендере
    return {
      'type': type,
      'title': title.isNotEmpty ? title : (_ru ? 'Данные из $source' : 'Data from $source'),
      'source': source,
      'data': [],
      'labels': [],
    };
  }

  Future<void> _loadParentName() async {
    if (_parentId == null) {
      setState(() => _parentName = null);
      return;
    }
    final all = await KnowledgeService.getAll();
    final parent = all.firstWhere(
      (a) => a.id == _parentId,
      orElse: () => ArticleModel(
        id: '', title: WesiLocale.isRussian ? 'Не найдено' : 'Not found',
        body: '', createdAt: DateTime.now(), updatedAt: DateTime.now(),
      ),
    );
    setState(() => _parentName = parent.title);
  }

  Future<void> _selectParent() async {
    final all = await KnowledgeService.getAll();
    final folders = all.where((a) => a.isFolder && a.id != widget.initial?.id).toList();
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
                child: Text(
                  _ru ? 'Выбрать родительскую папку' : 'Select parent folder',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
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
                        title: Text(
                          _ru ? 'Без папки (корень)' : 'No folder (root)',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                        ),
                        onTap: () => Navigator.pop(context, ''),
                        dense: true,
                      );
                    }
                    final f = folders[i - 1];
                    return ListTile(
                      leading: Icon(Icons.folder, color: AppTheme.accent, size: 20),
                      title: Text(f.title, style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                      subtitle: Text(
                        _sectionLabel(f.section),
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                      onTap: () => Navigator.pop(context, f.id),
                      dense: true,
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(WesiLocale.get('cancel'), style: TextStyle(color: AppTheme.textMuted)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      setState(() => _parentId = selected.isEmpty ? null : selected);
    }
  }

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
                  const SizedBox(height: 10),
                  // Parent folder + isFolder
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
                                Flexible(
                                  child: Text(
                                    _parentName ?? (_ru ? 'Без папки' : 'No folder'),
                                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
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
                            border: Border.all(
                              color: _isFolder ? AppTheme.accent.withOpacity(0.6) : AppTheme.glassBorder,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isFolder ? Icons.check_box : Icons.check_box_outline_blank,
                                size: 14,
                                color: _isFolder ? AppTheme.accent : AppTheme.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _ru ? 'Папка' : 'Folder',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _isFolder ? AppTheme.accent : AppTheme.textSecondary,
                                ),
                              ),
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
                    _tool(Icons.looks_one, 'H1', () => _controller.formatSelection(Attribute.h1)),
                    _tool(Icons.looks_two, 'H2', () => _controller.formatSelection(Attribute.h2)),
                    _tool(Icons.looks_3, 'H3', () => _controller.formatSelection(Attribute.h3)),
                    _divider(),
                    _tool(Icons.format_list_bulleted, _ru ? 'Список' : 'Bullet', () => _controller.formatSelection(Attribute.ul)),
                    _tool(Icons.format_list_numbered, _ru ? 'Нумерация' : 'Numbered', () => _controller.formatSelection(Attribute.ol)),
                    _divider(),
                    _tool(Icons.link, _ru ? 'Ссылка' : 'Link', _insertLink),
                    _tool(Icons.image, _ru ? 'Фото URL' : 'Photo URL', _insertImageFromUrl),
                    _tool(Icons.perm_media, _ru ? 'Фото с устройства' : 'Photo from device', _pickImageFromDevice),
                    _tool(Icons.video_library, _ru ? 'Видео URL' : 'Video URL', _insertVideoFromUrl),
                    _tool(Icons.video_file, _ru ? 'Видео с устройства' : 'Video from device', _pickVideoFromDevice),
                    _tool(Icons.audiotrack, _ru ? 'Аудио URL' : 'Audio URL', _insertAudioFromUrl),
                    _tool(Icons.library_music, _ru ? 'Аудио с устройства' : 'Audio from device', _pickAudioFromDevice),
                    _tool(Icons.insert_chart, _ru ? 'График' : 'Chart', _insertChart),
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
                child: QuillEditor.basic(
                  controller: _controller,
                  configurations: QuillEditorConfigurations(
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