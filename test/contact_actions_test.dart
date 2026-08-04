import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/team/services/contact_actions.dart';

void main() {
  group('нормализация номера', () {
    test('оставляет только цифры и ведущий плюс', () {
      expect(ContactActions.normalizePhone('+7 (999) 123-45-67'),
          '+79991234567');
      expect(ContactActions.normalizePhone('8 999 123 45 67'), '89991234567');
    });

    test('пустое и мусор дают пустую строку', () {
      expect(ContactActions.normalizePhone(''), '');
      expect(ContactActions.normalizePhone('   '), '');
      expect(ContactActions.normalizePhone('позвонить Ивану'), '');
    });

    test('плюс не в начале не считается плюсом', () {
      expect(ContactActions.normalizePhone('999+123'), '999123');
    });
  });

  group('ссылки на соцсети', () {
    test('готовый адрес берётся как есть', () {
      final uri = ContactActions.socialUri('Telegram', 'https://t.me/wesi');
      expect(uri.toString(), 'https://t.me/wesi');
    });

    test('собачка превращается в адрес', () {
      // Люди пишут «@wesi», и это должно работать так же, как полный адрес.
      expect(ContactActions.socialUri('Telegram', '@wesi').toString(),
          'https://t.me/wesi');
      expect(ContactActions.socialUri('VK', 'wesi').toString(),
          'https://vk.com/wesi');
    });

    test('русские названия сетей тоже понимаются', () {
      expect(ContactActions.socialUri('Телеграм', '@wesi').toString(),
          'https://t.me/wesi');
      expect(ContactActions.socialUri('ВКонтакте', 'wesi').toString(),
          'https://vk.com/wesi');
    });

    test('WhatsApp получает номер без знаков', () {
      expect(ContactActions.socialUri('WhatsApp', '+7 (999) 123-45-67')
          .toString(),
          'https://wa.me/79991234567');
    });

    test('незнакомая сеть с доменом открывается как адрес', () {
      expect(ContactActions.socialUri('Мойсайт', 'wesi.example').toString(),
          'https://wesi.example');
    });

    test('незнакомая сеть без домена ссылкой не становится', () {
      // Иначе «рабочая ссылка» вела бы в никуда, что хуже её отсутствия.
      expect(ContactActions.socialUri('Мойсайт', 'просто текст'), isNull);
    });

    test('пустое значение ссылкой не становится', () {
      expect(ContactActions.socialUri('Telegram', ''), isNull);
      expect(ContactActions.socialUri('Telegram', '   '), isNull);
      expect(ContactActions.socialUri('Telegram', '@'), isNull);
    });

    test('регистр названия сети не важен', () {
      expect(ContactActions.socialUri('TELEGRAM', '@w').toString(),
          'https://t.me/w');
      expect(ContactActions.socialUri('github', 'w').toString(),
          'https://github.com/w');
    });
  });
}
