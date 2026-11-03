import 'package:flutter/material.dart';

import '../../core/session/app_preferences.dart';

/// The whole source entry is the drag surface, in both list and grid layouts.
class SourceDragTile extends StatefulWidget {
  const SourceDragTile({
    super.key,
    required this.id,
    required this.name,
    required this.accepts,
    required this.onMove,
    required this.child,
  });
  final String id, name;
  final bool Function(String id) accepts;
  final Future<void> Function(String from, String to) onMove;
  final Widget child;
  @override
  State<SourceDragTile> createState() => _SourceDragTileState();
}

class _SourceDragTileState extends State<SourceDragTile> {
  EdgeDraggingAutoScroller? _scroller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scroller?.stopAutoScroll();
    var scrollable = Scrollable.maybeOf(context);
    // A shrink-wrapped grid lives inside the cat source sheet's outer list.
    while (scrollable?.widget.physics is NeverScrollableScrollPhysics) {
      scrollable = Scrollable.maybeOf(scrollable!.context);
    }
    _scroller = scrollable == null
        ? null
        : EdgeDraggingAutoScroller(scrollable, velocityScalar: 30);
  }

  @override
  void dispose() {
    _scroller?.stopAutoScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onWillAcceptWithDetails: (details) =>
        details.data != widget.id && widget.accepts(details.data),
    onAcceptWithDetails: (details) => widget.onMove(details.data, widget.id),
    builder: (context, candidates, _) => LongPressDraggable<String>(
      hapticFeedbackOnStart: false,
      onDragStarted: () => AppPreferences.instance.selectionFeedback(),
      data: widget.id,
      onDragUpdate: (details) => _scroller?.startAutoScrollIfNecessary(
        Rect.fromCenter(center: details.globalPosition, width: 1, height: 1),
      ),
      onDragEnd: (_) => _scroller?.stopAutoScroll(),
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(widget.name),
        ),
      ),
      childWhenDragging: Opacity(opacity: .3, child: widget.child),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: candidates.isEmpty
              ? null
              : Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
        ),
        child: widget.child,
      ),
    ),
  );
}
