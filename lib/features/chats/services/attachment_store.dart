import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat_attachment.dart';

/// Куда кладутся приложенные файлы.
///
/// **Копия, а не ссылка на исходное место.** Человек выбирает файл из
/// «Загрузок» или из галереи, и через неделю его там уже нет — почищено,
/// переименовано, перенесено. Сообщение при этом остаётся, и ссылка в нём
/// ведёт в никуда. Копия внутри каталога приложения живёт ровно столько,
/// сколько живёт сообщение.
///
/// **Файл удаляется вместе с сообщением.** Иначе переписка стирается по
/// месячному правилу, а гигабайты вложений остаются навсегда — и место
/// кончается по причине, которую человек не может ни увидеть, ни связать
/// со своими действиями.
class AttachmentStore {
  /// Больше этого не берём.
  ///
  /// Двадцать мегабайт: столько занимает договор со сканами или несколько
  /// фотографий. Выше начинается видео, которому в мессенджере без
  /// серверного хранилища и докачки делать нечего — отправка молча висела
  /// бы и не доходила.
  static const int maxBytes = 20 * 1024 * 1024;

  static const String _dirName = 'chat_attachments';

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Чем закончилась попытка приложить файл.
  static const String tooBig = 'too_big';
  static const String gone = 'gone';
  static const String empty = 'empty';

  /// Положить файл к себе и описать его.
  ///
  /// Возвращает описание либо код отказа строкой — человеку надо сказать,
  /// почему не вышло. Молчаливый отказ выглядит как «кнопка не работает»,
  /// и это самый дорогой вид поломки.
  static Future<Object> take({
    required String sourcePath,
    required String messageId,
    String? displayName,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) return gone;

    final size = await source.length();
    if (size == 0) return empty;
    if (size > maxBytes) return tooBig;

    final name = displayName ?? sourcePath.split(Platform.pathSeparator).last;
    final dir = await _dir();
    // Идентификатор сообщения в имени: два файла с одинаковым названием от
    // разных людей не должны затирать друг друга.
    final target = File(
        '${dir.path}${Platform.pathSeparator}$messageId-${_safe(name)}');
    await source.copy(target.path);

    return ChatAttachment(
      name: name,
      path: target.path,
      sizeBytes: size,
      mime: ChatAttachment.mimeOf(name),
      sha256: await _sha256Of(target),
    );
  }

  /// Убрать файлы удалённых сообщений.
  ///
  /// [aliveIds] — идентификаторы сообщений, которые ещё существуют.
  /// Возвращает, сколько файлов стёрлось.
  ///
  /// Сверка по списку живых, а не удаление при каждом стирании сообщения:
  /// сообщения уходят и по месячному сроку, и очисткой чата, и надгробием с
  /// другого устройства. Три места, где легко забыть, — и файл остаётся
  /// сиротой навсегда.
  static Future<int> sweep(Set<String> aliveIds) async {
    final dir = await _dir();
    if (!await dir.exists()) return 0;

    var removed = 0;
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      final fileName = entry.path.split(Platform.pathSeparator).last;
      final dash = fileName.indexOf('-');
      if (dash <= 0) continue;
      // Идентификатор сообщения сам содержит дефисы: «время-автор-соль».
      // Нужны первые три части.
      final parts = fileName.split('-');
      if (parts.length < 4) continue;
      final messageId = parts.take(3).join('-');
      if (aliveIds.contains(messageId)) continue;
      try {
        await entry.delete();
        removed++;
      } catch (_) {
        // Файл занят другим приложением — не повод срывать уборку.
      }
    }
    return removed;
  }

  /// Имя без того, что ломает пути.
  static String _safe(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  static Future<String> _sha256Of(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
