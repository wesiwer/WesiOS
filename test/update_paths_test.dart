import 'package:flutter_test/flutter_test.dart';

/// Пути установщика обновления собираются интерполяцией строк, и Dart
/// НЕ предупреждает, когда разделитель пути съедается escape-последова­
/// тельностью. Именно так обновление на Windows молча не применялось:
///
///   '$temp\wesios_update.bat'   → …\Tempwesios_update.bat   (потерян «\»)
///   '$temp\$_errorFileName'     → …\Temp$_errorFileName     (буквальный текст)
///
/// Эти тесты фиксируют оба случая, чтобы ошибка не вернулась.
void main() {
  const temp = r'C:\Users\Wesi\AppData\Local\Temp';
  const errorFileName = 'wesios_update_error.json';
  const sep = r'\';

  String tempFile(String name) => '$temp$sep$name';

  group('как НЕ надо (фиксируем поведение Dart)', () {
    test(r'\w не escape — разделитель исчезает', () {
      // ignore: use_raw_strings
      final broken = '$temp\wesios_update.bat';
      expect(broken, 'C:\\Users\\Wesi\\AppData\\Local\\Tempwesios_update.bat');
      expect(broken.contains(r'Temp\wesios'), isFalse,
          reason: 'разделитель съеден — путь ведёт не туда');
    });

    test(r'\$ — экранированный доллар, имя файла не подставляется', () {
      final broken = '$temp\$errorFileName';
      expect(broken.endsWith(r'$errorFileName'), isTrue);
      expect(broken.contains(errorFileName), isFalse,
          reason: 'в путь попал текст «\$errorFileName», а не имя файла');
    });
  });

  group('как надо', () {
    test('разделитель на месте', () {
      expect(tempFile('wesios_update.bat'),
          r'C:\Users\Wesi\AppData\Local\Temp\wesios_update.bat');
    });

    test('имя файла ошибки подставляется значением', () {
      expect(tempFile(errorFileName), endsWith(r'Temp\wesios_update_error.json'));
    });

    test('скрипт и приложение смотрят на ОДИН файл ошибки', () {
      // Скрипт пишет сюда…
      final written = tempFile(errorFileName);
      // …а приложение читает так (checkPendingError).
      final read = '$temp$sep$errorFileName';
      expect(written, read,
          reason: 'если пути разойдутся, неудача обновления станет невидимой');
    });

    test('все три служебных пути лежат внутри Temp, а не рядом с ним', () {
      for (final name in [
        'wesios_update.bat',
        'wesios_update_unpacked',
        'wesios_update.log',
        errorFileName,
      ]) {
        final path = tempFile(name);
        expect(path.startsWith('$temp$sep'), isTrue, reason: path);
        expect(path.substring(temp.length), '$sep$name');
      }
    });
  });
}
