import 'dart:convert';
import 'dart:io';

import '../../../core/sync/sync_endpoint.dart';
import '../models/employee_model.dart';

/// Связывает локальную карточку сотрудника с auth-записью PocketBase.
///
/// Сотрудник получает тот же логин и пароль в приложении и на портале
/// загрузки. Внешний API PocketBase для регистрации закрыт, поэтому запись
/// создаёт защищённый owner-only endpoint `/api/wesi/portal/employees/provision`.
class PortalAccountService {
  const PortalAccountService._();

  static Future<bool> provision({
    required EmployeeModel employee,
    required String password,
  }) async {
    final base = SyncEndpoint.url;
    final session = SyncEndpoint.session;
    final token = session?['token'];

    // Создание карточки не должно ломаться в офлайне. После подключения
    // синхронизации пароль можно сбросить — это повторно вызовет provision.
    if (base == null || token is! String || token.isEmpty) return false;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(
        Uri.parse('$base/api/wesi/portal/employees/provision'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, token);
      request.write(jsonEncode({
        'login': employee.login,
        'name': employee.displayName,
        'password': password,
      }));

      final response = await request.close().timeout(const Duration(seconds: 15));
      await response.drain<void>();
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
