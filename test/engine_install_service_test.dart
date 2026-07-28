import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/services/engine_install_service.dart';

void main() {
  group('EngineInstallProgress.fraction', () {
    test('computes a ratio when totalBytes is known', () {
      const p = EngineInstallProgress(
        stage: InstallStage.downloading,
        bytesDownloaded: 25,
        totalBytes: 100,
      );
      expect(p.fraction, 0.25);
    });

    test('is null when the server never reported Content-Length', () {
      const p = EngineInstallProgress(
        stage: InstallStage.downloading,
        bytesDownloaded: 25,
        totalBytes: null,
      );
      expect(p.fraction, isNull);
    });

    test('is null (not division-by-zero or infinity) when totalBytes is 0',
        () {
      const p = EngineInstallProgress(
        stage: InstallStage.downloading,
        bytesDownloaded: 0,
        totalBytes: 0,
      );
      expect(p.fraction, isNull);
    });

    test('clamps to 1.0 rather than overshooting on a slightly stale total',
        () {
      const p = EngineInstallProgress(
        stage: InstallStage.downloading,
        bytesDownloaded: 105,
        totalBytes: 100,
      );
      expect(p.fraction, 1.0);
    });
  });
}
