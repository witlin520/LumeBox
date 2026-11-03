import 'package:flutter/material.dart';

/// Paint-only motion: the detail's layout and hit targets stay in place.
class DetailArtworkMotion extends StatelessWidget {
  const DetailArtworkMotion({
    super.key,
    required this.scroll,
    required this.height,
    required this.child,
  });
  final ScrollController scroll;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedBuilder(
      animation: scroll,
      child: RepaintBoundary(child: child),
      builder: (context, artwork) {
        // During a layout-style replacement the old scroll view can remain
        // attached until the frame ends. Follow the newest view in that frame.
        final position = scroll.positions.lastOrNull;
        final offset = position?.hasPixels == true ? position!.pixels : 0.0;
        final pull = (-offset).clamp(0.0, height * .35);
        return Transform.translate(
          offset: Offset(
            0,
            offset < 0 ? offset : offset.clamp(0.0, height) * .4,
          ),
          child: Transform.scale(
            scale: 1 + pull / height,
            alignment: Alignment.topCenter,
            child: artwork,
          ),
        );
      },
    );
  }
}
