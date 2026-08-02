import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hover_button.dart';

/// Media / link / table insert helpers for the knowledge article editor.
class MediaInsertHelper {
  static Future<String?> _copyToAppDir(String sourcePath, String subDir) async {
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

  static Future<void> pickImageFromDevice({
    required BuildContext context,
    required QuillController controller,
    required bool isRu,
    required void Function(String) showError,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) {
      showError(isRu ? 'Не удалось получить файл' : 'Could not access file');
      return;
    }
    final savedPath = await _copyToAppDir(path, 'images');
    if (savedPath == null) {
      showError(isRu ? 'Не удалось сохранить файл' : 'Could not save file');
      return;
    }
    final index = controller.selection.start;
    controller.replaceText(index, 0, '\n', null);
    controller.document.insert(index + 1, BlockEmbed.image(savedPath));
  }

  static Future<void> pickVideoFromDevice({
    required BuildContext context,
    required QuillController controller,
    required bool isRu,
    required void Function(String) showError,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) {
      showError(isRu ? 'Не удалось получить файл' : 'Could not access file');
      return;
    }
    final savedPath = await _copyToAppDir(path, 'videos');
    if (savedPath == null) {
      showError(isRu ? 'Не удалось сохранить файл' : 'Could not save file');
      return;
    }
    final index = controller.selection.start;
    controller.replaceText(index, 0, '\n', null);
    controller.document.insert(index + 1, BlockEmbed.custom(CustomBlockEmbed('video', savedPath)));
  }

  static Future<void> insertImageFromUrl({
    required BuildContext context,
    required QuillController controller,
    required bool isRu,
    required Widget Function({required String title, required List<Widget> children, required bool Function() onConfirm}) editorDialog,
  }) async {
    final urlCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => editorDialog(
        title: isRu ? 'Вставить изображение по ссылке' : 'Insert image from URL',
        children: [
          TextField(
            controller: urlCtrl,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'URL',
              labelStyle: TextStyle(color: AppTheme.textMuted),
              helperText: isRu ? 'Ссылка на изображение в интернете' : 'Link to image on the web',
              helperStyle: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ),
        ],
        onConfirm: () => urlCtrl.text.trim().isNotEmpty,
      ),
    );
    if (ok == true && urlCtrl.text.trim().isNotEmpty) {
      final index = controller.selection.start;
      controller.replaceText(index, 0, '\n', null);
      controller.document.insert(index + 1, BlockEmbed.image(urlCtrl.text.trim()));
    }
    urlCtrl.dispose();
  }

  static Future<void> insertAudioFromUrl({
    required BuildContext context,
    required QuillController controller,
    required bool isRu,
  }) async {
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
                Text(isRu ? 'Вставить аудио' : 'Insert audio', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const SizedBox(height: 16),
                TextField(
                  controller: urlCtrl,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'URL аудио (MP3)',
                    labelStyle: TextStyle(color: AppTheme.textMuted),
                    helperText: isRu ? 'Прямая ссылка на аудио-файл' : 'Direct link to audio file',
                    helperStyle: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: Text(WesiLocale.get('cancel'), style: TextStyle(color: AppTheme.textMuted))),
                    const Spacer(),
                    HoverButton(
                      onTap: () => Navigator.pop(context, true),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      backgroundColor: AppTheme.accent,
                      child: Text(WesiLocale.get('insert'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
      final index = controller.selection.start;
      controller.replaceText(index, 0, '\n', null);
      controller.document.insert(index + 1, BlockEmbed.custom(CustomBlockEmbed('audio', urlCtrl.text.trim())));
    }
    urlCtrl.dispose();
  }

  static Future<void> pickAudioFromDevice({
    required BuildContext context,
    required QuillController controller,
    required bool isRu,
    required void Function(String) showError,
  }) async {
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
      final index = controller.selection.start;
      controller.replaceText(index, 0, '\n', null);
      controller.document.insert(index + 1, BlockEmbed.custom(CustomBlockEmbed('audio', dest.path)));
    } catch (e) {
      showError(isRu ? 'Ошибка загрузки аудио' : 'Audio upload error');
    }
  }

  static Future<void> insertVideoFromUrl({
    required BuildContext context,
    required QuillController controller,
    required bool isRu,
    required Widget Function({required String title, required List<Widget> children, required bool Function() onConfirm}) editorDialog,
  }) async {
    final urlCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => editorDialog(
        title: isRu ? 'Вставить видео по ссылке' : 'Insert video from URL',
        children: [
          TextField(
            controller: urlCtrl,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'URL (MP4, WebM)',
              labelStyle: TextStyle(color: AppTheme.textMuted),
              helperText: isRu ? 'Прямая ссылка на видео' : 'Direct video link',
              helperStyle: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ),
        ],
        onConfirm: () => urlCtrl.text.trim().isNotEmpty,
      ),
    );
    if (ok == true && urlCtrl.text.trim().isNotEmpty) {
      final index = controller.selection.start;
      controller.replaceText(index, 0, '\n', null);
      controller.document.insert(index + 1, BlockEmbed.custom(CustomBlockEmbed('video', urlCtrl.text.trim())));
    }
    urlCtrl.dispose();
  }

  static Future<void> insertLink({
    required BuildContext context,
    required QuillController controller,
    required bool isRu,
    required Widget Function({required String title, required List<Widget> children, required bool Function() onConfirm}) editorDialog,
  }) async {
    final urlCtrl = TextEditingController();
    final textCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => editorDialog(
        title: isRu ? 'Вставить ссылку' : 'Insert link',
        children: [
          TextField(
            controller: textCtrl,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: isRu ? 'Текст ссылки' : 'Link text',
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
              helperText: isRu ? 'wesios://article/ID — ссылка на статью' : 'wesios://article/ID — link to article',
              helperStyle: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ),
        ],
        onConfirm: () => urlCtrl.text.trim().isNotEmpty,
      ),
    );
    if (ok == true) {
      final index = controller.selection.start;
      final len = controller.selection.end - index;
      final linkText = textCtrl.text.trim().isNotEmpty ? textCtrl.text.trim() : urlCtrl.text.trim();
      controller.replaceText(index, len, linkText, null);
      controller.formatText(index, linkText.length, LinkAttribute(urlCtrl.text.trim()));
    }
    urlCtrl.dispose();
    textCtrl.dispose();
  }

  static Future<void> insertTable({
    required BuildContext context,
    required QuillController controller,
    required bool isRu,
    required Widget Function({required String title, required List<Widget> children, required bool Function() onConfirm}) editorDialog,
  }) async {
    final rowsCtrl = TextEditingController(text: '3');
    final colsCtrl = TextEditingController(text: '3');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => editorDialog(
        title: isRu ? 'Вставить таблицу' : 'Insert table',
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: rowsCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: isRu ? 'Строки' : 'Rows',
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
                    labelText: isRu ? 'Столбцы' : 'Columns',
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
      final index = controller.selection.start;
      controller.replaceText(index, 0, '\n', null);
      controller.document.insert(index + 1, BlockEmbed.custom(CustomBlockEmbed('table', jsonEncode(tableData))));
    }
    rowsCtrl.dispose();
    colsCtrl.dispose();
  }
}
