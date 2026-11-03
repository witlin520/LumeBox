import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;

import '../../core/reading/comic_image_tools.dart';

/// The same source geometry is used by visible pages, OCR overlays and exports.
Rect comicPageSource(Size imageSize, {double cropRatio = 0, int half = 0}) {
  final crop = cropRatio.clamp(0.0, .15);
  var source = Rect.fromLTRB(
    imageSize.width * crop,
    imageSize.height * crop,
    imageSize.width * (1 - crop),
    imageSize.height * (1 - crop),
  );
  if (half != 0) {
    source = Rect.fromLTWH(
      source.left + (half > 0 ? source.width / 2 : 0),
      source.top,
      source.width / 2,
      source.height,
    );
  }
  return source;
}

class ComicPageGeometry {
  ComicPageGeometry({
    required this.imageSize,
    required Rect source,
    required Size size,
    BoxFit fit = BoxFit.contain,
  }) {
    final fitted = applyBoxFit(fit, source.size, size);
    this.source = Alignment.center.inscribe(fitted.source, source);
    destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
  }
  final Size imageSize;
  late final Rect source, destination;

  Rect regionRect(ComicTextRegion region) => Rect.fromLTWH(
    destination.left +
        (region.x * imageSize.width - source.left) /
            source.width *
            destination.width,
    destination.top +
        (region.y * imageSize.height - source.top) /
            source.height *
            destination.height,
    math.max(
      24,
      region.width * imageSize.width / source.width * destination.width,
    ),
    math.max(
      18,
      region.height * imageSize.height / source.height * destination.height,
    ),
  );
}

/// Translated lettering shares one painter between reading and PNG composition.
class ComicTranslationPainter extends CustomPainter {
  const ComicTranslationPainter({
    required this.geometry,
    required this.regions,
    this.textScaler = TextScaler.noScaling,
    this.fontFamily,
  });
  final ComicPageGeometry geometry;
  final List<ComicTextRegion> regions;
  final TextScaler textScaler;
  final String? fontFamily;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(geometry.destination.intersect(Offset.zero & size));
    for (final region in regions) {
      if (region.translation.isEmpty) continue;
      final box = geometry.regionRect(region);
      if (!box.overlaps(geometry.destination)) continue;
      canvas.drawRect(box, Paint()..color = const Color(0xF5FFFFFF));
      final text = TextPainter(
        text: TextSpan(
          text: region.translation,
          style: TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontFamily: fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      final inner = box.deflate(2);
      final scale = math
          .min(
            1.0,
            math.min(
              inner.width / math.max(1, text.width),
              inner.height / math.max(1, text.height),
            ),
          )
          .clamp(0.0, 1.0);
      canvas.save();
      canvas.clipRect(box);
      canvas.translate(
        box.center.dx - text.width * scale / 2,
        box.center.dy - text.height * scale / 2,
      );
      canvas.scale(scale);
      text.paint(canvas, Offset.zero);
      canvas.restore();
      text.dispose();
    }
    canvas.restore();
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (final region in regions)
          if (region.translation.isNotEmpty &&
              geometry.regionRect(region).overlaps(geometry.destination))
            CustomPainterSemantics(
              rect: geometry
                  .regionRect(region)
                  .intersect(geometry.destination)
                  .intersect(Offset.zero & size),
              properties: SemanticsProperties(
                label: region.translation,
                textDirection: TextDirection.ltr,
              ),
            ),
      ];

  @override
  bool shouldRepaint(ComicTranslationPainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.regions != regions ||
      oldDelegate.textScaler != textScaler ||
      oldDelegate.fontFamily != fontFamily;
}

/// Exports a complete current page/half-page, excluding reader controls and
/// temporary speech highlights. [image] already contains nonlinear filtering.
/// Source pixels are never mutated. Output dimensions bound long-page memory.
Future<Uint8List> composeComicPage({
  required ui.Image image,
  required Rect source,
  required List<double> colorMatrix,
  required double brightness,
  required double displayWidth,
  List<ComicTextRegion> translations = const [],
  TextScaler textScaler = TextScaler.noScaling,
  String? fontFamily,
}) async {
  final scale = math.min(
    1.0,
    math.min(
      8192 / math.max(source.width, source.height),
      math.sqrt(8000000 / (source.width * source.height)),
    ),
  );
  final width = math.max(1, (source.width * scale).round());
  final height = math.max(1, (source.height * scale).round());
  final logicalSize = Size(displayWidth, displayWidth * height / width);
  final geometry = ComicPageGeometry(
    imageSize: Size(image.width.toDouble(), image.height.toDouble()),
    source: source,
    size: logicalSize,
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(width / logicalSize.width, height / logicalSize.height);
  final bounds = Offset.zero & logicalSize;
  canvas.saveLayer(
    bounds,
    Paint()..colorFilter = ColorFilter.matrix(colorMatrix),
  );
  canvas.drawImageRect(
    image,
    geometry.source,
    geometry.destination,
    Paint()..filterQuality = FilterQuality.medium,
  );
  ComicTranslationPainter(
    geometry: geometry,
    regions: translations,
    textScaler: textScaler,
    fontFamily: fontFamily,
  ).paint(canvas, logicalSize);
  canvas.restore();
  if (brightness < 1) {
    canvas.drawRect(
      bounds,
      Paint()
        ..color = Colors.black.withValues(
          alpha: 1 - brightness.clamp(0.0, 1.0),
        ),
    );
  }
  final picture = recorder.endRecording();
  ui.Image? output;
  try {
    output = await picture.toImage(width, height);
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('无法生成分享图片');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    output?.dispose();
    picture.dispose();
  }
}
