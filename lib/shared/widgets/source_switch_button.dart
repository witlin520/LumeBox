import 'package:flutter/material.dart';

import '../../core/source/source_display_names.dart';

import '../../core/theme/lume_theme.dart';
import 'lume_icon.dart';

/// Shared source-picker entry; the name takes all space left by the switch cue.
class SourceSwitchButton extends StatelessWidget {
  const SourceSwitchButton({
    super.key,
    required this.name,
    required this.onPressed,
    required this.iconSlot,
    this.compact = false,
  });

  final String name;
  final VoidCallback? onPressed;
  final String iconSlot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final accent = enabled ? LumeTheme.accent : LumeTheme.muted;
    final radius = BorderRadius.circular(14);
    return LayoutBuilder(
      builder: (context, constraints) => Semantics(
        button: true,
        enabled: enabled,
        label: '当前源：$name，切换源',
        onTap: onPressed,
        child: Tooltip(
          message: '切换源：$name',
          excludeFromSemantics: true,
          child: Material(
            color: accent.withValues(alpha: enabled ? .06 : .03),
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: accent.withValues(alpha: .16)),
            ),
            child: InkWell(
              onTap: onPressed,
              excludeFromSemantics: true,
              borderRadius: radius,
              child: SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ExcludeSemantics(
                          child: Text(
                            SourceDisplayNames.withoutRatingSuffix(name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: LumeTypography.titleSize,
                              height: 1.1,
                              fontWeight: FontWeight.w600,
                              color: enabled
                                  ? LumeTheme.textPrimary
                                  : LumeTheme.muted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ExcludeSemantics(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LumeIcon(
                              Icons.swap_horiz,
                              slot: iconSlot,
                              label: '切换源',
                              size: 18,
                              color: accent,
                            ),
                            if (!compact ||
                                (constraints.maxWidth >= 180 &&
                                    MediaQuery.textScalerOf(context)
                                            .scale(14) <=
                                        18)) ...[
                              const SizedBox(width: 3),
                              Text(
                                '切换',
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: LumeTypography.descriptionSize,
                                  fontWeight: FontWeight.w600,
                                  color: accent,
                                ),
                              ),
                            ],
                          ],
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
