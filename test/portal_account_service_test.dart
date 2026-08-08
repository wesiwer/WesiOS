import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/team/services/portal_account_service.dart';

void main() {
  group('PortalAccountService.messageForResponse', () {
    test('translates generic PocketBase failure', () {
      final message = PortalAccountService.messageForResponse(
        500,
        '{"message":"Something went wrong while processing your request."}',
        fallback: 'Сервер не принял данные.',
      );

      expect(message, 'Серверный модуль входа временно недоступен.');
    });

    test('explains missing production hook', () {
      final message = PortalAccountService.messageForResponse(
        404,
        '{"message":"Something went wrong while processing your request."}',
        fallback: 'Сервер не принял данные.',
      );

      expect(message, contains('модуль безопасности не установлен'));
    });

    test('keeps useful Russian server message', () {
      final message = PortalAccountService.messageForResponse(
        400,
        '{"message":"Такой логин уже занят"}',
        fallback: 'Сервер не принял данные.',
      );

      expect(message, 'Такой логин уже занят');
    });

    test('reads field validation message', () {
      final message = PortalAccountService.messageForResponse(
        400,
        '{"data":{"password":{"message":"Пароль слишком короткий"}}}',
        fallback: 'Сервер не принял данные.',
      );

      expect(message, 'Пароль слишком короткий');
    });
  });
}
