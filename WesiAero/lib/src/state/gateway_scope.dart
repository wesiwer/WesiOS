import 'package:flutter/widgets.dart';

import 'gateway_controller.dart';

class GatewayScope extends InheritedNotifier<GatewayController> {
  const GatewayScope({
    required GatewayController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static GatewayController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<GatewayScope>();
    assert(scope != null, 'GatewayScope not found in widget tree.');
    return scope!.notifier!;
  }

  static GatewayController read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<GatewayScope>();
    final scope = element?.widget as GatewayScope?;
    assert(scope != null, 'GatewayScope not found in widget tree.');
    return scope!.notifier!;
  }
}

