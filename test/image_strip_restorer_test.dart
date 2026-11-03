import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/image_strip_restorer.dart';

Future<Uint8List> rowsFixture(int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (var row = 0; row < height; row++) {
    canvas.drawRect(
      ui.Rect.fromLTWH(0, row.toDouble(), 2, 1),
      ui.Paint()..color = ui.Color.fromARGB(255, row * 16, 0, 0),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, height);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (height, order) in [
    (11, [6, 7, 8, 9, 10, 3, 4, 5, 0, 1, 2]),
    (12, [8, 9, 10, 11, 4, 5, 6, 7, 0, 1, 2, 3]),
  ]) {
    test(
      'restores every row without cropping or seams at height $height',
      () async {
        final restored = await restoreSourceImageStrips(
          await rowsFixture(height),
          const {'X-Lume-Image-Strips': '3'},
        );
        final codec = await ui.instantiateImageCodec(restored);
        final image = (await codec.getNextFrame()).image;
        try {
          expect(image.width, 2);
          expect(image.height, height);
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          expect(
            [for (var row = 0; row < height; row++) pixels.getUint8(row * 8)],
            [for (final row in order) row * 16],
          );
          expect(
            [
              for (var row = 0; row < height; row++)
                pixels.getUint8(row * 8 + 4),
            ],
            [for (final row in order) row * 16],
          );
        } finally {
          image.dispose();
          codec.dispose();
        }
      },
    );
  }
  test(
    'ordinary images pass through and invalid metadata is rejected',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(
        identical(await restoreSourceImageStrips(bytes, const {}), bytes),
        isTrue,
      );
      await expectLater(
        restoreSourceImageStrips(bytes, const {'X-Lume-Image-Strips': '30'}),
        throwsFormatException,
      );
    },
  );
}
