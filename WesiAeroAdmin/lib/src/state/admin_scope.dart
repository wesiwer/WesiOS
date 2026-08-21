import 'package:flutter/widgets.dart';

import 'admin_controller.dart';

class AdminScope extends InheritedNotifier<AdminController> {
  const AdminScope({required AdminController controller, required super.child, super.key})
      : super(notifier: controller);

  static AdminController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AdminScope>();
    assert(scope != null, 'AdminScope not found.');
    return scope!.notifier!;
  }

  static AdminController read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<AdminScope>();
    final scope = element?.widget as AdminScope?;
    assert(scope != null, 'AdminScope not found.');
    return scope!.notifier!;
  }
}
