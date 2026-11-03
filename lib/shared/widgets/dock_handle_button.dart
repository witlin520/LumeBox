import 'package:lume_box/shared/widgets/lume_icon.dart';

import 'package:flutter/material.dart';

import '../../core/shell/shell_settings.dart';
import '../../core/theme/lume_theme.dart';

/// 收起后的导航把手：透明中性底色，不绘制主题色边缘；仅图标跟随主题。
class DockHandleButton extends StatelessWidget {
  const DockHandleButton({
    super.key,
    required this.style,
    this.size = 52,
    this.opacity = 1,
    this.onPressed,
    this.tooltip = '展开导航',
    this.sectionIcon = Icons.auto_stories_rounded,
    this.sectionId = 'comic',
    this.materialOpacity = .6,
  });

  final DockHandleStyle style;
  final double size;

  /// 空闲态整体透明度（用户口径：不用的时候可以半透明）。
  final double opacity;
  final VoidCallback? onPressed;
  final String tooltip;
  final IconData sectionIcon;
  final String sectionId;
  final double materialOpacity;

  @override
  Widget build(BuildContext context) {
    final accent = LumeTheme.accent;
    final content = switch (style) {
      DockHandleStyle.currentSection => LumeIcon(
        sectionIcon,
        slot: 'dock.$sectionId.selected',
        size: size * .52,
        color: accent,
      ),
      DockHandleStyle.arrow => LumeIcon(
        Icons.chevron_right_rounded,
        slot: 'dock_handle_button.1',
        size: size * .58,
        color: accent,
      ),
      DockHandleStyle.grid => LumeIcon(
        Icons.grid_view,
        slot: 'dock.handle.grid',
        label: '收起后的导航把手 · 网格',
        group: '底部导航',
        color: accent,
        size: size * .58,
        fallback: _DotGrid(color: accent),
      ),
      DockHandleStyle.lines => LumeIcon(
        Icons.menu,
        slot: 'dock.handle.lines',
        label: '收起后的导航把手 · 横线',
        group: '底部导航',
        color: accent,
        size: size * .58,
        fallback: _RoundedLines(color: accent),
      ),
    };
    return Opacity(
      opacity: opacity,
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          width: size,
          height: size,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Center(child: content),
            ),
          ),
        ),
      ),
    );
  }
}

class _DotGrid extends StatelessWidget {
  const _DotGrid({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var row = 0; row < 3; row++)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var column = 0; column < 3; column++)
              Padding(
                padding: const EdgeInsets.all(2.4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox(width: 4.6, height: 4.6),
                ),
              ),
          ],
        ),
    ],
  );
}

class _RoundedLines extends StatelessWidget {
  const _RoundedLines({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 3; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
            child: const SizedBox(width: 20, height: 3.4),
          ),
        ),
    ],
  );
}
