import 'package:flutter/material.dart';

class SourceRatingBadge extends StatelessWidget {
  const SourceRatingBadge({super.key, this.compact = false});

  /// Fixed red age-rating mark, independent of theme and custom icon packs.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const message = '含成人内容 · 18+';
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: message,
      child: Semantics(
        label: message,
        image: true,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 2.5 : 3,
            vertical: .75,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0xffe94e65), Color(0xffb52340)]
                  : const [Color(0xffdb3e55), Color(0xffad2039)],
            ),
            border: Border.all(
              color: const Color(0xfffa9aaa).withValues(alpha: .5),
              width: .5,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            '18+',
            style: TextStyle(
              fontSize: compact ? 6.5 : 7,
              height: 1.1,
              fontWeight: FontWeight.w700,
              letterSpacing: .1,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
