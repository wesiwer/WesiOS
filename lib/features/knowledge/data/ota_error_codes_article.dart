import '../models/article_model.dart';

/// Built-in article: OTA update error codes (W1xx / A2xx).
ArticleModel builtinOtaErrorCodesArticle(bool ru, DateTime now) {
  String h1(String t) => '{"insert":"$t\\n","attributes":{"header":1}}';
  String h2(String t) => '{"insert":"$t\\n","attributes":{"header":2}}';
  String p(String t) => '{"insert":"$t\\n"}';
  String bullet(String t) => '{"insert":"$t\\n","attributes":{"list":"bullet"}}';
  String br() => '{"insert":"\\n"}';
  String embedTable(String json) => '{"insert":{"table":"$json"}}';
  String tableJson(List<List<String>> rows) {
    final encoded =
        rows.map((r) => r.map((c) => '"$c"').join(',')).join('],[');
    return '[[$encoded]]';
  }

  final body = '[${h1(ru ? 'Коды ошибок обновления WesiOS' : 'WesiOS update error codes')},'
      '${p(ru ? 'При ошибке скачивания или установки показывается стилизованное окно с кодом (W1xx / A2xx), описанием и подсказкой. На Windows после сбоя bat приложение перезапускается и читает маркер в Temp.' : 'On download or install failure a styled dialog shows a code (W1xx / A2xx), description and hint. On Windows after a bat failure the app restarts and reads a Temp marker.')},'
      '${h2(ru ? 'Windows и скачивание (W1xx)' : 'Windows and download (W1xx)')},'
      '${embedTable(tableJson([
        [ru ? 'Код' : 'Code', ru ? 'Причина' : 'Cause', ru ? 'Что делать' : 'What to do'],
        ['W101', ru ? 'Нет входа в GitHub' : 'GitHub sign-in missing', ru ? 'Настройки → Обновление → Войти' : 'Settings → Updates → Sign in'],
        ['W102', ru ? 'Нет файла в релизе' : 'Release asset missing', ru ? 'Перезапустить Publish' : 'Re-run Publish'],
        ['W103', ru ? 'Ошибка HTTP скачивания' : 'HTTP download error', ru ? 'Проверить сеть' : 'Check network'],
        ['W104', ru ? 'Сбой подготовки' : 'Prepare failure', ru ? 'Повторить' : 'Retry'],
        ['W105', ru ? 'Не распаковался zip' : 'Expand-Archive failed', ru ? 'Повторить / zip вручную' : 'Retry / manual zip'],
        ['W106', ru ? 'В архиве нет exe' : 'exe not in archive', ru ? 'Проверить CI zip' : 'Check CI zip'],
        ['W107', ru ? 'robocopy / Defender / CFA' : 'robocopy / Defender / CFA', ru ? 'Исключения Defender' : 'Defender exclusions'],
        ['W108', ru ? 'exe пропал после копирования' : 'exe missing after copy', ru ? 'Карантин Defender' : 'Defender quarantine'],
        ['W109', ru ? 'Процесс не закрылся' : 'Process did not exit', ru ? 'Закрыть WesiOS полностью' : 'Fully quit WesiOS'],
        ['W110', ru ? 'Прочая ошибка Windows' : 'Other Windows error', ru ? 'Смотреть лог' : 'See log'],
      ]))},'
      '${br()},'
      '${h2(ru ? 'Android (A2xx)' : 'Android (A2xx)')},'
      '${embedTable(tableJson([
        [ru ? 'Код' : 'Code', ru ? 'Причина' : 'Cause', ru ? 'Что делать' : 'What to do'],
        ['A201', ru ? 'Нет разрешения APK' : 'Install permission denied', ru ? 'Разрешить установку из источника' : 'Allow install from source'],
        ['A202', ru ? 'Installer не открылся' : 'Installer failed', ru ? 'Повторить' : 'Retry'],
      ]))},'
      '${br()},'
      '${h2(ru ? 'W107 — типичный случай' : 'W107 — typical case')},'
      '${p(ru ? 'Скачалось, закрылось, открылось, версия та же: часто Defender. Добавьте папку с wesios.exe и Temp в исключения, затем Повторить.' : 'Downloaded, closed, reopened, same version: often Defender. Add install folder and Temp to exclusions, then Retry.')},'
      '${bullet(ru ? 'Лог: %TEMP%\\\\wesios_update.log' : 'Log: %TEMP%\\\\wesios_update.log')},'
      '${bullet(ru ? 'Маркер: %TEMP%\\\\wesios_update_error.json' : 'Marker: %TEMP%\\\\wesios_update_error.json')},'
      '${bullet('lib/core/services/app_update_service.dart')},'
      '${bullet('lib/core/widgets/update_error_dialog.dart')}'
      ']';

  return ArticleModel(
    id: 'wesios_update_errors',
    title: ru ? 'Коды ошибок OTA' : 'OTA error codes',
    body: body,
    section: ArticleSection.about,
    tags: ru
        ? const ['update', 'ota', 'ошибки', 'коды', 'defender']
        : const ['update', 'ota', 'errors', 'codes', 'defender'],
    createdAt: now,
    updatedAt: now,
    builtIn: true,
    parentId: 'wesios_services',
  );
}
