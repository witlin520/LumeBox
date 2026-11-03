import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/comic_image_tools.dart';
import 'package:lume_box/features/comic/comic_page_composition.dart';
import 'package:lume_box/features/comic/comic_page_filters.dart';
import 'package:lume_box/features/comic/comic_reader_preferences.dart';

Future<ui.Image> samplePage({int width = 100, int height = 80}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawColor(const Color(0xFF205080), BlendMode.src);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
    Paint()..color = const Color(0xFF904020),
  );
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), 4),
    Paint()..color = Colors.green,
  );
  final pic = rec.endRecording();
  try {
    return await pic.toImage(width, height);
  } finally {
    pic.dispose();
  }
}

Future<ui.Image> decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('分享合成实际应用半页、裁剪、非线性滤镜、色矩阵和亮度，原图不变', (tester) async {
    await tester.runAsync(() async {
      final image = await samplePage();
      final before = (await image.toByteData())!.buffer.asUint8List();
      final filtered = await filterComicPage(
        image,
        gamma: 2,
        sharpness: 1,
        denoise: true,
      );
      final preferences = ComicReaderPreferences()..inverted = true;
      final source = comicPageSource(
        const Size(100, 80),
        cropRatio: .1,
        half: 1,
      );
      expect(source, const Rect.fromLTWH(50, 8, 40, 64));
      final png = await composeComicPage(
        image: filtered,
        source: source,
        colorMatrix: preferences.colorMatrix,
        brightness: .5,
        displayWidth: 40,
      );
      expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final output = await decode(png);
      expect(
        Size(output.width.toDouble(), output.height.toDouble()),
        const Size(40, 64),
      );
      final data = (await output.toByteData())!.buffer.asUint8List();
      final index = (32 * 40 + 20) * 4;
      for (var c = 0; c < 3; c++) {
        final original = [32, 80, 128][c];
        final gamma = (255 * math.sqrt(original / 255)).round();
        expect(data[index + c], closeTo((255 - gamma) * .5, 2));
      }
      expect(
        (await image.toByteData())!.buffer.asUint8List(),
        orderedEquals(before),
      );
      output.dispose();
      filtered.dispose();
      image.dispose();
    });
  });

  testWidgets('分享含译文且半页外译文不泄漏，屏幕与导出共用译文绘制', (tester) async {
    await tester.runAsync(() async {
      final image = await samplePage();
      final source = comicPageSource(const Size(100, 80), half: 1);
      final matrix = ComicReaderPreferences().colorMatrix;
      Future<ui.Image> compose(List<ComicTextRegion> translations) async =>
          decode(
            await composeComicPage(
              image: image,
              source: source,
              colorMatrix: matrix,
              brightness: 1,
              displayWidth: 50,
              translations: translations,
            ),
          );
      final original = await compose([]);
      final outside = await compose(const [
        ComicTextRegion(
          text: 'outside',
          translation: 'OUTSIDE',
          x: .05,
          y: .2,
          width: .1,
          height: .2,
        ),
      ]);
      final translated = await compose(const [
        ComicTextRegion(
          text: 'inside',
          translation: 'TEST',
          x: .55,
          y: .2,
          width: .4,
          height: .4,
        ),
      ]);
      final plain = (await original.toByteData())!.buffer.asUint8List();
      expect(
        (await outside.toByteData())!.buffer.asUint8List(),
        orderedEquals(plain),
      );
      final data = (await translated.toByteData())!.buffer.asUint8List();
      var changed = 0, white = 0, ink = 0;
      for (var i = 0; i < data.length; i += 4) {
        if (data[i] != plain[i]) changed++;
        if (data[i] > 240 && data[i + 1] > 240 && data[i + 2] > 240) white++;
        if (data[i] < 20 && data[i + 1] < 20 && data[i + 2] < 20) ink++;
      }
      expect(changed, greaterThan(200));
      expect(white, greaterThan(100));
      expect(ink, greaterThan(5));
      original.dispose();
      outside.dispose();
      translated.dispose();
      image.dispose();
    });
  });

  testWidgets('长条图导出限制边长和像素数，未处理图片仍可使用独立克隆', (tester) async {
    await tester.runAsync(() async {
      final image = await samplePage(width: 8, height: 10000);
      final clone = await filterComicPage(image);
      image.dispose();
      final png = await composeComicPage(
        image: clone,
        source: const Rect.fromLTWH(0, 0, 8, 10000),
        colorMatrix: ComicReaderPreferences().colorMatrix,
        brightness: 1,
        displayWidth: 8,
      );
      final output = await decode(png);
      expect(output.height, 8192);
      expect(output.width * output.height, lessThanOrEqualTo(8000000));
      output.dispose();
      clone.dispose();
    });
  });
}
