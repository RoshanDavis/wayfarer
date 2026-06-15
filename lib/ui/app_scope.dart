/// Exposes the single [AppController] to the widget tree.
library;

import 'package:flutter/widgets.dart';

import '../app/app_controller.dart';

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  static AppController of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppScope>()!
      .notifier!;
}
