import 'package:flutter/widgets.dart';

/// Section-owned actions are captured before opening a navigator's drawer.
class SourceDrawerActions extends InheritedWidget {
  const SourceDrawerActions({
    super.key,
    required this.actions,
    required super.child,
  });
  final List<Widget> actions;
  static List<Widget> of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SourceDrawerActions>()
          ?.actions ??
      const [];
  @override
  bool updateShouldNotify(SourceDrawerActions oldWidget) =>
      actions != oldWidget.actions;
}
