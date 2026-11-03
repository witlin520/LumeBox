import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// 有上限的内存 LRU 缓存，同时合并同张海报正在进行的取色请求。
/// key 应包含图片地址；若同一地址的内容会改变，应附加版本号。
class PosterPaletteCache {
  static final _colors = <Object, Color>{};
  static final _pending = <Object, Future<Color>>{};
  static const _limit = 64;

  static Future<Color> resolve(
    Object key,
    Future<Color?> Function() extract,
  ) async {
    final cached = _colors.remove(key);
    if (cached != null) {
      _colors[key] = cached;
      return cached;
    }
    final pending = _pending[key];
    if (pending != null) return pending;
    final task = () async {
      try {
        // 成功提取但没有 darkMutedColor，也按黑色保存。
        final color = await extract() ?? Colors.black;
        _colors[key] = color;
        while (_colors.length > _limit) {
          _colors.remove(_colors.keys.first);
        }
        return color;
      } catch (_) {
        // 网络或解码失败回黑色，但不缓存失败，允许下次重试。
        return Colors.black;
      }
    }();
    _pending[key] = task;
    try {
      return await task;
    } finally {
      _pending.remove(key);
    }
  }
}

/// 三段垂直渐变：保留顶部原图，中部融色，底部完全接入页面底色。
LinearGradient posterOverlayGradient(Color color) => LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  stops: const [0, .55, 1],
  colors: [color.withValues(alpha: 0), color.withValues(alpha: .4), color],
);

/// 完整可复用的详情页外壳：前景内容由调用方提供，不改变业务布局。
class PosterGradientScaffold extends StatefulWidget {
  const PosterGradientScaffold({
    super.key,
    required this.poster,
    required this.content,
    this.appBar,
    this.posterHeight = 640,
    this.contentTop = 440,
  });

  final ImageProvider poster;
  final Widget content;
  final PreferredSizeWidget? appBar;
  final double posterHeight;
  final double contentTop;

  @override
  State<PosterGradientScaffold> createState() => _PosterGradientScaffoldState();
}

class _PosterGradientScaffoldState extends State<PosterGradientScaffold> {
  Color _color = Colors.black;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _loadPalette();
  }

  @override
  void didUpdateWidget(covariant PosterGradientScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.poster != widget.poster) {
      _color = Colors.black;
      _loadPalette();
    }
  }

  Future<void> _loadPalette() async {
    final revision = ++_revision;
    final provider = widget.poster;
    final color = await PosterPaletteCache.resolve(provider, () async {
      // 仅用小图取色，避免完整海报像素参与量化。
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        size: const Size(80, 120),
        maximumColorCount: 24,
        // 不排除偏红像素；暗色、柔和程度仍由 darkMuted 目标选择。
        filters: const [],
        timeout: const Duration(seconds: 8),
      );
      return palette.darkMutedColor?.color;
    });
    // 旧海报返回较慢时，不能覆盖新海报的颜色；销毁后也不更新。
    if (!mounted || revision != _revision) return;
    setState(() => _color = color);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _color,
    extendBodyBehindAppBar: true,
    appBar: widget.appBar,
    body: SingleChildScrollView(
      child: Stack(
        children: [
          SizedBox(
            height: widget.posterHeight,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image(
                  image: widget.poster,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, error, stack) => const SizedBox.expand(),
                ),
                // Overlay 独立覆盖在海报上，不使用 ShaderMask。
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: posterOverlayGradient(_color),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: widget.contentTop),
            child: widget.content,
          ),
        ],
      ),
    ),
  );
}
