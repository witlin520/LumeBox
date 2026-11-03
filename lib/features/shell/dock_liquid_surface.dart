import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show ImageFilterConfig, ImageFilterContext;

/// 底部 Dock 的底座玻璃。
///
/// 取样与合成顺序是这一层的关键：
/// 1. 引擎先对**原始页面**做一次高斯模糊（[ImageFilter.blur]）；
/// 2. [DockLiquidSurfaceFilter] 再把模糊结果按“透镜区域”遮罩：
///    透镜核心变成近乎透明（[coreAlpha] 只留一层很薄的玻璃），外圈仍是
///    带白度/主题色的磨砂；
/// 3. 因为核心处这一层几乎透明，**未经任何 Dock 滤镜的原始页面**会透出来，
///    随后绘制的 [DockLiquidLens] 采样到的就是清晰背景 + 图标文字，
///    不会再出现“整条先糊一遍、透镜再糊一遍”的细节丢失。
///
/// 非 Impeller 渲染后端（ImageFilter.shader 不可用）自动退回旧行为：
/// 整条底座按 [fallbackSigma] 模糊，并由 [fallbackChild] 提供白度/渐变/描边，
/// 与改造前的观感一致。
class DockLiquidSurface extends StatefulWidget {
  const DockLiquidSurface({
    super.key,
    required this.borderRadius,
    required this.blurSigma,
    required this.fallbackSigma,
    required this.fallbackChild,
    required this.lensRect,
    required this.lensRadius,
    required this.lensScale,
    required this.feather,
    required this.clarity,
    required this.coreAlpha,
    required this.backgroundAdapt,
    required this.tintColor,
    required this.tintOpacity,
    required this.pixelRatio,
    required this.stageOrigin,
    this.clipPath,
    this.filterKey,
  });

  static const String shaderAsset = 'assets/shaders/dock_liquid_surface.frag';

  /// [ui.ImageFilter.shader] 只在 Impeller 后端可用。
  static bool get shaderSupported => ui.ImageFilter.isShaderFilterSupported;

  static ui.FragmentProgram? _program;

  final BorderRadius borderRadius;

  /// Shader 路径：底座磨砂始终使用这个 sigma（清晰区域由遮罩决定）。
  final double blurSigma;

  /// 回退路径：按按压进度减弱后的 sigma，与旧实现一致。
  final double fallbackSigma;

  /// 回退路径下 [BackdropFilter] 的子节点（白度 + 渐变 + 描边）。
  final Widget fallbackChild;

  /// 透镜在舞台（内容层）坐标系里的矩形。
  final Rect lensRect;

  /// 透镜圆角半径（逻辑像素）。
  final double lensRadius;

  /// 透镜所在的整条底栏缩放倍数：遮盖矩形按同一倍数放大才能贴合屏幕上的透镜。
  final double lensScale;

  /// 透镜边缘柔和过渡带宽度（逻辑像素）。
  final double feather;

  /// 0 = 完全磨砂；1 = 透镜核心完全清澈。
  final double clarity;

  /// 清澈核心处保留的极薄玻璃层（0 = 完全无遮挡）。
  final double coreAlpha;

  /// 背景明暗联动强度：亮背景更白、暗背景更透。
  final double backgroundAdapt;

  final Color tintColor;
  final double tintOpacity;
  final double pixelRatio;

  /// 透镜矩形所在内容层的全局原点（逻辑像素），在绘制阶段取值。
  final Offset Function() stageOrigin;

  /// 可选的底座轮廓（局部收腰等自定义形变）；为空时使用圆角矩形。
  final Path? clipPath;

  /// 测试/壳层用来定位这一层的 key（通常是 [ShellDockBar.capsuleFilterKey]）。
  final Key? filterKey;

  @override
  State<DockLiquidSurface> createState() => _DockLiquidSurfaceState();
}

class _DockLiquidSurfaceState extends State<DockLiquidSurface> {
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    if (DockLiquidSurface.shaderSupported) _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = DockLiquidSurface._program ??=
          await ui.FragmentProgram.fromAsset(DockLiquidSurface.shaderAsset);
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    } catch (error) {
      // 退回旧磨砂路径；底栏不能因为一个着色器资源失败而消失。
      debugPrint('Dock liquid surface shader unavailable: $error');
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    Widget clip(Widget child) => widget.clipPath == null
        ? ClipRRect(borderRadius: widget.borderRadius, child: child)
        : ClipPath(
            clipper: _SurfacePathClipper(widget.clipPath!),
            child: child,
          );
    if (shader == null) {
      return clip(
        BackdropFilter(
          key: widget.filterKey,
          filter: ui.ImageFilter.blur(
            sigmaX: widget.fallbackSigma,
            sigmaY: widget.fallbackSigma,
            tileMode: ui.TileMode.mirror,
          ),
          child: widget.fallbackChild,
        ),
      );
    }
    return clip(
      BackdropFilter(
        key: widget.filterKey,
        filterConfig: DockLiquidSurfaceFilter(
          shader: shader,
          blurSigma: widget.blurSigma,
          lensRect: widget.lensRect,
          lensRadius: widget.lensRadius,
          lensScale: widget.lensScale,
          feather: widget.feather,
          clarity: widget.clarity,
          coreAlpha: widget.coreAlpha,
          backgroundAdapt: widget.backgroundAdapt,
          tintColor: widget.tintColor,
          tintOpacity: widget.tintOpacity,
          pixelRatio: widget.pixelRatio,
          stageOrigin: widget.stageOrigin,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SurfacePathClipper extends CustomClipper<Path> {
  const _SurfacePathClipper(this.path);

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_SurfacePathClipper oldClipper) => oldClipper.path != path;
}

/// 把“整面模糊 + 局部清澈遮罩”合成为一个 ImageFilter。
///
/// 顺序必须是 `compose(outer: shader, inner: blur)`：引擎先对原始 backdrop
/// 做 blur，再交给 shader 做遮罩与白度合成；反过来会先遮罩后模糊，清澈区
/// 会重新被糊掉。
class DockLiquidSurfaceFilter implements ImageFilterConfig {
  DockLiquidSurfaceFilter({
    required this.shader,
    required this.blurSigma,
    required this.lensRect,
    required this.lensRadius,
    required this.lensScale,
    required this.feather,
    required this.clarity,
    required this.coreAlpha,
    required this.backgroundAdapt,
    required this.tintColor,
    required this.tintOpacity,
    required this.pixelRatio,
    required this.stageOrigin,
  });

  final ui.FragmentShader shader;
  final double blurSigma;
  final Rect lensRect;
  final double lensRadius;
  final double lensScale;
  final double feather;
  final double clarity;
  final double coreAlpha;
  final double backgroundAdapt;
  final Color tintColor;
  final double tintOpacity;
  final double pixelRatio;
  final Offset Function() stageOrigin;

  @override
  ui.ImageFilter? get filter => null;

  @override
  String get debugShortDescription => 'dockLiquidSurface';

  @override
  ui.ImageFilter resolve(ImageFilterContext context) {
    final origin = stageOrigin();
    final ratio = pixelRatio;
    final scale = lensScale.clamp(0.1, 4.0);
    shader
      // float 0/1 与 sampler 0 由引擎写入（float 0/1 = 输入纹理尺寸）。
      ..setFloat(2, (origin.dx + lensRect.left * scale) * ratio)
      ..setFloat(3, (origin.dy + lensRect.top * scale) * ratio)
      ..setFloat(4, lensRect.width * scale * ratio)
      ..setFloat(5, lensRect.height * scale * ratio)
      ..setFloat(6, lensRadius * scale * ratio)
      ..setFloat(7, feather * scale * ratio)
      ..setFloat(8, clarity.clamp(0.0, 1.0))
      ..setFloat(9, tintOpacity.clamp(0.0, 1.0))
      ..setFloat(10, coreAlpha.clamp(0.0, 1.0))
      ..setFloat(11, tintColor.r)
      ..setFloat(12, tintColor.g)
      ..setFloat(13, tintColor.b)
      ..setFloat(14, backgroundAdapt.clamp(0.0, 1.0));
    return ui.ImageFilter.compose(
      outer: ui.ImageFilter.shader(shader),
      inner: ui.ImageFilter.blur(
        sigmaX: blurSigma,
        sigmaY: blurSigma,
        tileMode: ui.TileMode.mirror,
      ),
    );
  }
}
