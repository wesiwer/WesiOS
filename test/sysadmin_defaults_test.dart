import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/sysadmin/models/monitor_target.dart';
import 'package:wesios/features/sysadmin/services/monitor_service.dart';

void main() {
  group('инфраструктура Wesi по умолчанию', () {
    test('новая установка знает российский сервер и портал', () {
      final targets = MonitorService.defaultTargets;

      expect(
        targets.any((t) =>
            t.id == 'wesi-russia-server' &&
            t.host == 'api.wesi-inc.ru' &&
            t.loadUrl == 'https://api.wesi-inc.ru/wesios-status.json'),
        isTrue,
      );
      expect(
        targets.any((t) =>
            t.id == 'wesi-employee-portal' &&
            t.url == 'https://api.wesi-inc.ru/portal/' &&
            t.kind == TargetKind.site),
        isTrue,
      );
    });

    test('зарубежный Wesi AI не смешан с российским сервером', () {
      final ai = MonitorService.defaultTargets.singleWhere(
        (t) => t.id == 'wesi-ai-gateway',
      );
      expect(ai.host, 'ai.wesi-inc.ru');
      expect(ai.url, 'https://ai.wesi-inc.ru/v1/health');
      expect(ai.host, isNot('api.wesi-inc.ru'));
    });

    test('в предустановленных узлах нет секретов', () {
      final json = MonitorService.defaultTargets
          .map((target) => target.toJson().toString().toLowerCase())
          .join('\n');
      expect(json, isNot(contains('password')));
      expect(json, isNot(contains('private key')));
      expect(json, isNot(contains('bearer ')));
    });
  });
}
