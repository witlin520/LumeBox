import 'package:flutter/material.dart';

import '../../core/source/source_display_names.dart';

import '../../core/theme/lume_theme.dart';
import 'source_card_metrics.dart';
import 'lume_icon.dart';

/// One card layout for comic, ordinary video, Python, cat and web sources.
class SourcePickerCard extends StatelessWidget {
  const SourcePickerCard({
    super.key,
    this.tapKey,
    this.surfaceKey,
    this.moreKey,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.onMore,
    this.titleTrailing,
    this.moreTooltip = '源操作',
    this.titleMaxLines = 1,
    this.height = SourceCardMetrics.height,
  });

  final Key? tapKey, moreKey, surfaceKey;
  final String title, moreTooltip;
  final int titleMaxLines;
  final double height;
  final Widget subtitle, icon;
  final Widget? titleTrailing;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).brightness == Brightness.dark
        ? LumeTheme.surfaceAlt
        : LumeTheme.surface;
    return Tooltip(
      message: SourceDisplayNames.withoutRatingSuffix(title),
      triggerMode: TooltipTriggerMode.manual,
      child: Semantics(
        selected: selected,
        child: SizedBox(
          height: height,
          child: DecoratedBox(
            key: surfaceKey,
            decoration: BoxDecoration(
              color: selected
                  ? Color.alphaBlend(accent.withValues(alpha: .08), surface)
                  : surface,
              borderRadius: SourceCardMetrics.borderRadius,
              border: Border.all(
                color: selected ? accent : SourceCardMetrics.unselectedBorder,
              ),
              boxShadow: SourceCardMetrics.shadow,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: SourceCardMetrics.borderRadius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: tapKey,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: SourceCardMetrics.iconSize,
                        child: icon,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          SourceDisplayNames.withoutRatingSuffix(
                                            title,
                                          ),
                                          maxLines: titleMaxLines,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15,
                                            height: 1.2,
                                            fontWeight: FontWeight.w600,
                                            color: LumeTheme.textPrimary,
                                          ),
                                        ),
                                      ),
                                      ?titleTrailing,
                                      if (selected)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 3,
                                          ),
                                          child: Icon(
                                            Icons.check_circle,
                                            size: 14,
                                            color: accent,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  DefaultTextStyle(
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.2,
                                      color: selected
                                          ? accent
                                          : LumeTheme.muted,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    child: subtitle,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        key: moreKey,
                        tooltip: moreTooltip,
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        constraints: const BoxConstraints.tightFor(
                          width: 24,
                          height: 40,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: onMore,
                        icon: const LumeIcon(
                          Icons.more_vert,
                          size: 18,
                          slot: 'source_picker.more',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
