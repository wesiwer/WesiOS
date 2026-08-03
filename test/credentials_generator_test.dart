import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/team/services/credentials_generator.dart';

void main() {
  group('pick', () {
    test('не выдаёт логин из числа занятых', () {
      final taken = CredentialsGenerator.words.take(50).toSet();
      for (var i = 0; i < 200; i++) {
        final login = CredentialsGenerator.pick(taken);
        expect(login, isNotNull);
        expect(taken.contains(login), isFalse);
      }
    });

    test('когда все слова заняты — подбирает слово с числом', () {
      final taken = CredentialsGenerator.words.toSet();
      final login = CredentialsGenerator.pick(taken);
      expect(login, isNotNull);
      expect(taken.contains(login), isFalse);
      // Слово+число, а не голое слово — все слова уже заняты.
      expect(RegExp(r'^[a-z]+\d{4}$').hasMatch(login!), isTrue);
    });

    test('null, только если и слова, и числа исчерпаны', () {
      // Занимаем все слова и все комбинации слово+число, которые вообще
      // может выдать pick (диапазон 1000..9999 для каждого слова).
      final taken = {
        ...CredentialsGenerator.words,
        for (final w in CredentialsGenerator.words)
          for (var n = 1000; n < 10000; n++) '$w$n',
      };
      final login = CredentialsGenerator.pick(taken);
      expect(login, isNull);
    });
  });

  group('password', () {
    test('состоит только из знаков разрешённого алфавита', () {
      const ambiguous = {'0', 'O', '1', 'l', 'I', '5', 'S'};
      for (var i = 0; i < 50; i++) {
        final pwd = CredentialsGenerator.password();
        expect(pwd.length, CredentialsGenerator.defaultPasswordLength);
        for (final ch in pwd.split('')) {
          expect(ambiguous.contains(ch), isFalse,
              reason: 'символ "$ch" путается при чтении/надиктовке');
        }
      }
    });

    test('уважает переданную длину', () {
      expect(CredentialsGenerator.password(length: 20).length, 20);
    });

    test('не даёт длину короче 8 символов', () {
      // Короткий пароль — это не оптимизация, а дыра; вход туда молча
      // подрезать нельзя было бы обнаружить по сигнатуре метода.
      expect(CredentialsGenerator.password(length: 3).length, 8);
    });

    test('два подряд вызова не совпадают', () {
      // Не строгая гарантия статистически, но при 55^14 вариантах совпадение
      // означало бы, что генератор сломан (например, зафиксированный seed).
      final a = CredentialsGenerator.password();
      final b = CredentialsGenerator.password();
      expect(a, isNot(equals(b)));
    });
  });

  group('normalize', () {
    test('регистр не имеет значения', () {
      expect(CredentialsGenerator.normalize('Amber'),
          CredentialsGenerator.normalize('amber'));
    });

    test('обрезает края и схлопывает пробелы', () {
      expect(CredentialsGenerator.normalize('  am ber  '), 'amber');
    });
  });

  group('isValid', () {
    test('принимает нейтральные логины из словаря', () {
      for (final w in CredentialsGenerator.words) {
        expect(CredentialsGenerator.isValid(w), isTrue, reason: w);
      }
    });

    test('принимает логин с точкой, дефисом и подчёркиванием внутри', () {
      expect(CredentialsGenerator.isValid('amber-north.42'), isTrue);
      expect(CredentialsGenerator.isValid('amber_north'), isTrue);
    });

    test('отвергает слишком короткую и слишком длинную строку', () {
      expect(CredentialsGenerator.isValid('ab'), isFalse);
      expect(CredentialsGenerator.isValid('a' * 33), isFalse);
    });

    test('отвергает начало/конец на разделителе', () {
      expect(CredentialsGenerator.isValid('-amber'), isFalse);
      expect(CredentialsGenerator.isValid('amber-'), isFalse);
      expect(CredentialsGenerator.isValid('.amber'), isFalse);
    });

    test('отвергает недопустимые символы', () {
      expect(CredentialsGenerator.isValid('amber@north'), isFalse);
      expect(CredentialsGenerator.isValid('амбер'), isFalse);
    });

    test('пробел внутри схлопывается, а не запрещает логин', () {
      // normalize() намеренно убирает пробелы целиком — логин часто
      // диктуют, и случайный пробел не должен ронять вход.
      expect(CredentialsGenerator.isValid('amber north'), isTrue);
      expect(CredentialsGenerator.normalize('amber north'), 'ambernorth');
    });
  });

  group('toEmail / fromEmail', () {
    test('строит служебный адрес на wesi.local по умолчанию', () {
      expect(CredentialsGenerator.toEmail('Amber'), 'amber@wesi.local');
    });

    test('уважает переданный домен', () {
      expect(CredentialsGenerator.toEmail('amber', domain: 'example.com'),
          'amber@example.com');
    });

    test('round-trip: fromEmail(toEmail(x)) == normalize(x)', () {
      for (final w in CredentialsGenerator.words) {
        final email = CredentialsGenerator.toEmail(w);
        expect(CredentialsGenerator.fromEmail(email),
            CredentialsGenerator.normalize(w));
      }
    });

    test('fromEmail без @ возвращает строку как есть', () {
      expect(CredentialsGenerator.fromEmail('amber'), 'amber');
    });
  });
}
