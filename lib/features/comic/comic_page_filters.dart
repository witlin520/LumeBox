import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'comic_shader_artwork.dart';

/// Nonlinear filters run off the UI isolate and only retain a visible tile's result.
class ComicPageFilters extends StatefulWidget {
  const ComicPageFilters({
    super.key,
    required this.image,
    required this.builder,
    this.gamma = 1,
    this.sharpness = 0,
    this.denoise = false,
  });
  final ui.Image image;
  final Widget Function(ui.Image) builder;
  final double gamma, sharpness;
  final bool denoise;
  @override
  State<ComicPageFilters> createState() => _ComicPageFiltersState();
}

class _ComicPageFiltersState extends State<ComicPageFilters> {
  ui.Image? _filtered;
  int _generation = 0;
  bool _working = false;
  bool _again = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(ComicPageFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image ||
        oldWidget.gamma != widget.gamma ||
        oldWidget.sharpness != widget.sharpness ||
        oldWidget.denoise != widget.denoise) {
      _schedule();
    }
  }

  void _discard(ui.Image? image) {
    if (image != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
    }
  }

  void _schedule() {
    _generation++;
    _discard(_filtered);
    _filtered = null;
    if (_working) {
      _again = true;
      return;
    }
    if (widget.gamma == 1 && widget.sharpness == 0 && !widget.denoise) return;
    _process();
  }

  Future<void> _process() async {
    if (widget.image.width * widget.image.height > 8000000) return;
    _working = true;
    final generation = _generation;
    // Clone keeps the backing image alive while its pipeline tile is released.
    final source = widget.image.clone();
    final gamma = widget.gamma,
        sharpness = widget.sharpness,
        denoise = widget.denoise;
    try {
      final image = await filterComicPage(
        source,
        gamma: gamma,
        sharpness: sharpness,
        denoise: denoise,
      );
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      setState(() => _filtered = image);
    } catch (_) {
      // Resource pressure should leave the original visible.
    } finally {
      source.dispose();
      _working = false;
      if (mounted && _again) {
        _again = false;
        _schedule();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _discard(_filtered);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(_filtered ?? widget.image);
}

/// Shared by the visible tile and page export; returns a caller-owned image.
Future<ui.Image> filterComicPage(
  ui.Image source, {
  double gamma = 1,
  double sharpness = 0,
  bool denoise = false,
}) async {
  if (gamma == 1 && sharpness == 0 && !denoise) {
    return source.clone();
  }
  if (source.width * source.height > 8000000) {
    return filterLargeComicPage(
      source,
      gamma: gamma,
      sharpness: sharpness,
      denoise: denoise,
    );
  }
  final data = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) throw StateError('图片像素暂不可读');
  final result = await compute(_filterPixels, (
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    source.width,
    source.height,
    gamma,
    sharpness,
    denoise,
  ));
  final buffer = await ui.ImmutableBuffer.fromUint8List(result);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: source.width,
      height: source.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    codec = await descriptor.instantiateCodec();
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

Uint8List _filterPixels((Uint8List, int, int, double, double, bool) input) {
  final (pixels, width, height, gamma, sharpness, denoise) = input;
  var output = Uint8List.fromList(pixels);
  final lut = List<int>.generate(
    256,
    (value) => (255 * math.pow(value / 255, 1 / gamma)).round().clamp(0, 255),
  );
  for (var offset = 0; offset < output.length; offset += 4) {
    for (var channel = 0; channel < 3; channel++) {
      output[offset + channel] = lut[output[offset + channel]];
    }
  }
  if (!denoise && sharpness == 0) return output;
  final base = output;
  output = Uint8List.fromList(base);
  // Edge-aware smoothing protects lettering; unsharp masking restores fine lines.
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final offset = (y * width + x) * 4;
      for (var channel = 0; channel < 3; channel++) {
        final center = base[offset + channel];
        var sum = center, count = 1;
        for (final neighbor in [
          offset - 4,
          offset + 4,
          offset - width * 4,
          offset + width * 4,
        ]) {
          final value = base[neighbor + channel];
          if (!denoise || (value - center).abs() < 28) {
            sum += value;
            count++;
          }
        }
        final average = sum / count;
        final smooth = denoise ? center * .4 + average * .6 : center.toDouble();
        output[offset + channel] = (smooth + sharpness * (center - average))
            .round()
            .clamp(0, 255);
      }
    }
  }
  return output;
}
