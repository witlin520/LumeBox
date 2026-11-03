import 'package:flutter/material.dart';

/// Shared by ordinary, Python/module and cat source home pages.
abstract final class BrowseHeaderScroll {
  static bool hiddenAfter(ScrollNotification notification, bool hidden) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        notification is! ScrollUpdateNotification ||
        notification.dragDetails == null) {
      return hidden;
    }
    final delta = notification.scrollDelta ?? 0;
    if (notification.metrics.pixels <= 12 || delta < 0) return false;
    return delta > 0 ? true : hidden;
  }
}

class BrowseHeaderMotion extends StatelessWidget {
  const BrowseHeaderMotion({
    super.key,
    required this.hidden,
    required this.child,
  });

  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: hidden,
    child: AnimatedOpacity(
      opacity: hidden ? 0 : 1,
      duration: const Duration(milliseconds: 160),
      child: AnimatedSlide(
        offset: hidden ? const Offset(0, -1) : Offset.zero,
        duration: const Duration(milliseconds: 180),
        child: child,
      ),
    ),
  );
}
