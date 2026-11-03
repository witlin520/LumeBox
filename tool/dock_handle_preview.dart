import 'package:flutter/material.dart';

import 'package:lume_box/core/shell/shell_settings.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/shared/widgets/dock_handle_button.dart';

/// Three collapsed-dock handle styles, side by side, over a patterned backdrop
/// so the BackdropFilter glass is visible.
///
/// Run: `flutter run -d windows -t tool/dock_handle_preview.dart`
void main() => runApp(const DockHandlePreview());

class DockHandlePreview extends StatefulWidget {
  const DockHandlePreview({super.key});
  @override
  State<DockHandlePreview> createState() => _DockHandlePreviewState();
}

class _DockHandlePreviewState extends State<DockHandlePreview> {
  bool dark = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
    theme: LumeTheme.build(
      brightness: dark ? Brightness.dark : Brightness.light,
    ),
    home: DockHandleShowcase(
      dark: dark,
      onToggle: () => setState(() => dark = !dark),
    ),
  );
}

class DockHandleShowcase extends StatelessWidget {
  const DockHandleShowcase({
    super.key,
    required this.dark,
    required this.onToggle,
  });
  final bool dark;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: LumeTheme.base,
    appBar: AppBar(
      title: const Text('收起悬浮球 · 三种样式'),
      actions: [
        IconButton(
          tooltip: '切换亮暗模式',
          onPressed: onToggle,
          icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
        ),
      ],
    ),
    body: Center(
      child: SizedBox(
        width: 960,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final style in DockHandleStyle.values) ...[
              Expanded(
                child: _HandleCard(style: style, dark: dark),
              ),
              if (style != DockHandleStyle.values.last)
                const SizedBox(width: 14),
            ],
          ],
        ),
      ),
    ),
  );
}

class _HandleCard extends StatelessWidget {
  const _HandleCard({required this.style, required this.dark});
  final DockHandleStyle style;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final accent = LumeTheme.accent;
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: LumeTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LumeTheme.hairline),
        boxShadow: LumeTheme.floatShadow,
      ),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent.withValues(alpha: .30),
                          const Color(0xFFFFC46B).withValues(alpha: .35),
                          const Color(0xFF5BC8FF).withValues(alpha: .30),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 28,
                    top: 26,
                    child: _Blob(
                      color: Colors.white.withValues(alpha: .55),
                      size: 64,
                    ),
                  ),
                  Positioned(
                    right: 24,
                    bottom: 20,
                    child: _Blob(
                      color: accent.withValues(alpha: .45),
                      size: 78,
                    ),
                  ),
                  Center(
                    child: DockHandleButton(
                      style: style,
                      size: 64,
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  style.label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: LumeTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  style.description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: LumeTheme.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
