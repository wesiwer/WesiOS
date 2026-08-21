import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesi_aero/src/models/gateway_models.dart';
import 'package:wesi_aero/src/state/gateway_controller.dart';
import 'package:wesi_aero/src/state/gateway_scope.dart';

void main() {
  testWidgets('telemetry-only updates do not rebuild GatewayScope dependents',
      (tester) async {
    final controller = GatewayController();
    var builds = 0;

    await tester.pumpWidget(
      GatewayScope(
        controller: controller,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              GatewayScope.of(context);
              builds += 1;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(builds, 1);

    controller.snapshot = controller.snapshot.copyWith(
      stats: const SessionStats(
        downloadBytesPerSecond: 4 * 1024 * 1024,
        uploadBytesPerSecond: 768 * 1024,
        downloadedBytes: 128 * 1024 * 1024,
        uploadedBytes: 16 * 1024 * 1024,
        pingMs: 31,
      ),
    );
    controller.notifyListeners();
    await tester.pump();

    expect(
      builds,
      1,
      reason: 'RX/TX telemetry has a dedicated ValueNotifier and must not '
          'invalidate the expensive inherited UI tree.',
    );

    controller.navigationIndex = 1;
    controller.notifyListeners();
    await tester.pump();

    expect(builds, 2, reason: 'A visible navigation change must rebuild.');

    controller.snapshot = controller.snapshot.copyWith(
      status: TunnelStatus.connecting,
    );
    controller.notifyListeners();
    await tester.pump();

    expect(builds, 3, reason: 'A visible tunnel status change must rebuild.');

    controller.dispose();
  });
}
