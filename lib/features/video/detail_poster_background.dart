import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Continue the poster tone through the synopsis into a deeper episode surface.
/// The image is opaque above this layer; the tint becomes visible as it fades.
LinearGradient detailPosterSurfaceGradient(Color color) {
  final tone = HSLColor.fromColor(color);
  final lifted = tone
      .withLightness(tone.lightness + (1 - tone.lightness) * .08)
      .toColor();
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: const [0, .48, 1],
    colors: [lifted, lifted, color],
  );
}

/// Preserve the poster's hue in a quiet, readable page surface.
Color compactPosterPageColor(Color poster, {required Brightness brightness}) {
  final tone = HSLColor.fromColor(poster);
  final dark = brightness == Brightness.dark;
  return tone
      .withSaturation(
        (tone.saturation * (dark ? .35 : .42)).clamp(0, dark ? .24 : .30),
      )
      .withLightness(dark ? .14 : .87)
      .withAlpha(1)
      .toColor();
}

Color adjustDetailBackground(
  Color color, {
  double brightness = 1,
  double saturation = 1,
}) {
  if (brightness == 1 && saturation == 1) return color;
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness((hsl.lightness * brightness).clamp(.02, .95))
      .withSaturation((hsl.saturation * saturation).clamp(0, 1))
      .toColor();
}

/// Fixed, bounded-resolution image layer. Blur the image alone, not the scrolling
/// controls above it; the repaint boundary can reuse it while content scrolls.
class DetailPosterBackground extends StatelessWidget {
  const DetailPosterBackground({
    super.key,
    required this.backdrop,
    required this.fallback,
    required this.tint,
    this.headers = const {},
  });

  final String? backdrop;
  final Widget fallback;
  final Color tint;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Transform.scale(
                scale: 1.12,
                child: backdrop == null
                    ? fallback
                    : Image.network(
                        backdrop!,
                        headers: headers,
                        cacheWidth: 384,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (_, _, _) => fallback,
                      ),
              ),
            ),
            // Preserve image colour and texture instead of an opaque dark fill.
            ColoredBox(color: tint.withValues(alpha: .38)),
          ],
        ),
      ),
    ),
  );
}

/// Fade only the poster's alpha. A bounded saveLayer with dstIn avoids using
/// ShaderMask and exposes the page colour underneath the poster.
class DetailPosterFade extends SingleChildRenderObjectWidget {
  const DetailPosterFade({
    super.key,
    required super.child,
    this.strength = 1,
    this.brightness = 1,
  });
  final double strength, brightness;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PosterFadeRender(strength, brightness);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _PosterFadeRender).update(strength, brightness);
  }
}

class _PosterFadeRender extends RenderProxyBox {
  _PosterFadeRender(this.strength, this.brightness);
  double strength, brightness;
  void update(double strength, double brightness) {
    if (this.strength == strength && this.brightness == brightness) return;
    this.strength = strength;
    this.brightness = brightness;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || size.isEmpty) return;
    final rect = offset & size;
    final canvas = context.canvas;
    final paint = Paint();
    if (brightness != 1) {
      paint.colorFilter = ColorFilter.matrix([
        brightness,
        0,
        0,
        0,
        0,
        0,
        brightness,
        0,
        0,
        0,
        0,
        0,
        brightness,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]);
    }
    canvas.saveLayer(rect, paint);
    super.paint(context, offset);
    if (strength > 0) {
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, .48, .64, .78, .90, .97, 1],
            colors: [
              for (final alpha in [1.0, 1.0, .93, .72, .36, .08, 0.0])
                Colors.white.withAlpha(
                  (255 * math.pow(alpha, strength)).round(),
                ),
            ],
          ).createShader(rect),
      );
    }
    canvas.restore();
  }
}
