import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/services/currency_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('wesios_privacy_test');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>('wesios_settings');
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  setUp(() {
    CurrencyService.privacyMode.value = false;
  });

  test('в обычном режиме сумма видна', () {
    expect(CurrencyService.format(1234), contains('1.2'));
    expect(CurrencyService.formatExact(1234), contains('1234'));
  });

  test('в режиме приватности цифры не просачиваются ни в одну из форм', () {
    CurrencyService.privacyMode.value = true;
    for (final s in [
      CurrencyService.format(1234),
      CurrencyService.format(-9999999),
      CurrencyService.formatExact(1234.56),
      CurrencyService.formatExact(0),
    ]) {
      expect(RegExp(r'\d').hasMatch(s), isFalse, reason: s);
    }
  });

  test('значок валюты остаётся: скрыта сумма, а не то, в чём она', () {
    CurrencyService.privacyMode.value = true;
    expect(CurrencyService.format(1234), startsWith(CurrencyService.symbol));
  });

  test('знак минуса не выдаёт убыток', () {
    // Иначе по одному «-» было бы видно, что дела плохи, — а прятали именно
    // это.
    CurrencyService.privacyMode.value = true;
    expect(CurrencyService.format(-5000).contains('-'), isFalse);
  });

  test('данные не трогаются: display возвращает настоящее число', () {
    // Маскируется вывод, а не значение: графики и расчёты должны продолжать
    // работать с реальными суммами.
    CurrencyService.privacyMode.value = true;
    expect(CurrencyService.display(1234), isNot(0));
  });

  test('настройка переживает перезапуск', () async {
    await CurrencyService.setPrivacyMode(true);
    CurrencyService.privacyMode.value = false;
    CurrencyService.loadPrivacyMode();
    expect(CurrencyService.privacyMode.value, isTrue);

    await CurrencyService.setPrivacyMode(false);
    CurrencyService.loadPrivacyMode();
    expect(CurrencyService.privacyMode.value, isFalse);
  });
}
