import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/util/lume_log.dart';

import 'comic_page_composition.dart';

/// Cache the compiled program, never a Future tied to a test's async zone.
ui.FragmentProgram? _program;
Future<ui.FragmentShader> _newShader() async {
  final program = _program ??= await ui.FragmentProgram.fromAsset(
    'assets/shaders/comic_page_filters.frag',
  );
  return program.fragmentShader();
}

void _drawFiltered(
  Canvas canvas,
  ui.FragmentShader shader,
  ui.Image image,
  Rect source,
  Rect destination,
  double gamma,
  double sharpness,
  bool denoise,
) {
  final values = <double>[
    image.width.toDouble(),
    image.height.toDouble(),
    source.left,
    source.top,
    source.width,
    source.height,
    destination.left,
    destination.top,
    destination.width,
    destination.height,
    gamma,
    sharpness,
    denoise ? 1 : 0,
  ];
  for (var i = 0; i < values.length; i++) {
    shader.setFloat(i, values[i]);
  }
  shader.setImageSampler(0, image);
  canvas.drawRect(destination, Paint()..shader = shader);
}

/// Large images stay on the GPU while reading. Filtering neither copies the
/// whole RGBA bitmap to Dart nor allocates a second full-height texture.
class ComicShaderArtwork extends StatefulWidget {
  const ComicShaderArtwork({
    super.key,
    required this.image,
    required this.geometry,
    required this.gamma,
    required this.sharpness,
    required this.denoise,
  });
  final ui.Image image;
  final ComicPageGeometry geometry;
  final double gamma, sharpness;
  final bool denoise;
  @override
  State<ComicShaderArtwork> createState() => _ComicShaderArtworkState();
}

class _ComicShaderArtworkState extends State<ComicShaderArtwork> {
  ui.FragmentShader? _shader;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final shader = await _newShader();
      if (!mounted) {
        shader.dispose();
        return;
      }
      setState(() => _shader = shader);
    } catch (error) {
      // Keep the page readable if the renderer cannot allocate the effect.
      LumeLog.warn('长图滤镜暂不可用，保留原图：$error');
    }
  }

  @override
  void dispose() {
    final shader = _shader;
    if (shader != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => shader.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _ArtworkPainter(
      widget.image,
      widget.geometry,
      _shader,
      widget.gamma,
      widget.sharpness,
      widget.denoise,
    ),
  );
}

class _ArtworkPainter extends CustomPainter {
  const _ArtworkPainter(
    this.image,
    this.geometry,
    this.shader,
    this.gamma,
    this.sharpness,
    this.denoise,
  );
  final ui.Image image;
  final ComicPageGeometry geometry;
  final ui.FragmentShader? shader;
  final double gamma, sharpness;
  final bool denoise;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (shader == null) {
      canvas.drawImageRect(
        image,
        geometry.source,
        geometry.destination,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      _drawFiltered(
        canvas,
        shader!,
        image,
        geometry.source,
        geometry.destination,
        gamma,
        sharpness,
        denoise,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArtworkPainter old) =>
      old.image != image ||
      old.geometry != geometry ||
      old.shader != shader ||
      old.gamma != gamma ||
      old.sharpness != sharpness ||
      old.denoise != denoise;
}

/// Caller owns the result. PNG export bounds its texture/memory while applying
/// exactly the same nonlinear filter as the live large-image shader.
Future<ui.Image> filterLargeComicPage(
  ui.Image image, {
  required double gamma,
  required double sharpness,
  required bool denoise,
}) async {
  final shader = await _newShader();
  final scale = math.min(
    1.0,
    math.min(
      8192 / math.max(image.width, image.height),
      math.sqrt(8000000 / (image.width * image.height)),
    ),
  );
  final width = math.max(1, (image.width * scale).floor());
  final height = math.max(1, (image.height * scale).floor());
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  _drawFiltered(
    canvas,
    shader,
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    gamma,
    sharpness,
    denoise,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
    shader.dispose();
  }
}
