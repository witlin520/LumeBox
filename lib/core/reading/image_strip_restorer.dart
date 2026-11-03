import 'dart:typed_data';
import 'dart:ui' as ui;

/// Restores the horizontal strip order described by a source's public reader.
/// The extra rows belong to the first destination strip, matching that reader.
Future<Uint8List> restoreSourceImageStrips(
  Uint8List bytes,
  Map<String, String> headers,
) async {
  final value = headers.entries
      .where((entry) => entry.key.toLowerCase() == 'x-lume-image-strips')
      .map((entry) => entry.value)
      .firstOrNull;
  if (value == null || value == '0') return bytes;
  final strips = int.tryParse(value);
  if (strips == null || strips < 2 || strips > 20) {
    throw const FormatException('Invalid source image strip count');
  }
  final codec = await ui.instantiateImageCodec(bytes);
  ui.Image? source, restored;
  ui.Picture? picture;
  try {
    source = (await codec.getNextFrame()).image;
    if (source.height < strips) {
      throw const FormatException(
        'Source image is too short for its strip count',
      );
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final rows = source.height ~/ strips;
    final remainder = source.height % strips;
    final paint = ui.Paint()
      ..isAntiAlias = false
      ..filterQuality = ui.FilterQuality.none
      ..blendMode = ui.BlendMode.src;
    for (var index = 0; index < strips; index++) {
      final height = rows + (index == 0 ? remainder : 0);
      final sourceY = source.height - rows * (index + 1) - remainder;
      final targetY = rows * index + (index == 0 ? 0 : remainder);
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(
          0,
          sourceY.toDouble(),
          source.width.toDouble(),
          height.toDouble(),
        ),
        ui.Rect.fromLTWH(
          0,
          targetY.toDouble(),
          source.width.toDouble(),
          height.toDouble(),
        ),
        paint,
      );
    }
    picture = recorder.endRecording();
    restored = await picture.toImage(source.width, source.height);
    final png = await restored.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) {
      throw const FormatException('Unable to encode restored source image');
    }
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  } finally {
    picture?.dispose();
    restored?.dispose();
    source?.dispose();
    codec.dispose();
  }
}
