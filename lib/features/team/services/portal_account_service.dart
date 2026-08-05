import 'dart:convert';
import 'dart:io';

import '../../../core/sync/sync_endpoint.dart';
import '../models/employee_model.dart';

/// Создаёт серверную auth-запись сотрудника одновременно с локальной
/// карточкой WesiOS.
///
/// Сервер получает пароль только по HTTPS, сразу хеширует его PocketBase и
/// никогда не возвращает обратно. После provision клиент выполняет реальный
/// тестовый вход теми же данными: успешным считается только аккаунт, который
/// уже действительно принимает логин и пароль.
class PortalAccountService {
  const PortalAccountService._();

  static const String defaultServer = 'https://api.wesi-inc.ru';

  static Future<bool> provision({
    required EmployeeModel employee,
    required String password,
  }) async {
    final base = SyncEndpoint.url ?? defaultServer;
    final session = SyncEndpoint.session;
    final ownerToken = session?['token'];
    if (ownerToken is! String || ownerToken.isEmpty) return false;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(
        Uri.parse('$base/api/wesi/portal/employees/provision'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, ownerToken);
      request.write(jsonEncode({
        'login': employee.login,
        'name': employee.displayName,
        'password': password,
      }));

      final response = await request.close().timeout(const Duration(seconds: 15));
      final responseText = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200 && response.statusCode != 201) {
        return false;
      }

      // Не доверяем только коду provision: сразу проверяем тот же путь входа,
      // которым пользуется портал сотрудников.
      final auth = await client.postUrl(
        Uri.parse('$base/api/collections/users/auth-with-password'),
      );
      auth.headers.contentType = ContentType.json;
      auth.write(jsonEncode({
        'identity': '${employee.login}@wesi.local',
        'password': password,
      }));
      final authResponse = await auth.close().timeout(const Duration(seconds: 15));
      await authResponse.drain<void>();
      return authResponse.statusCode == 200 && responseText.isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
