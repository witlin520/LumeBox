import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/features/comic/comic_page_composition.dart';
import 'package:lume_box/features/comic/comic_page_filters.dart';
import 'package:lume_box/features/comic/comic_shader_artwork.dart';

Future<ui.Image> image(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFF205080), BlendMode.src);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
    Paint()..color = const Color(0xFF904020),
  );
  for (var x = 8; x < math.min(width, 40); x += 3) {
    canvas.drawRect(
      Rect.fromLTWH(x.toDouble(), 8, 1, 12),
      Paint()..color = Color.fromARGB(255, 130 + x % 15, 70, 40),
    );
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('GPU 伽马、锐度和降噪与既有像素算法一致', (tester) async {
    await tester.runAsync(() async {
      final source = await image(80, 40);
      for (final denoise in [false, true]) {
        final cpu = await filterComicPage(
          source,
          gamma: 1.6,
          sharpness: .8,
          denoise: denoise,
        );
        final gpu = await filterLargeComicPage(
          source,
          gamma: 1.6,
          sharpness: .8,
          denoise: denoise,
        );
        final a = (await cpu.toByteData())!.buffer.asUint8List();
        final b = (await gpu.toByteData())!.buffer.asUint8List();
        var maximum = 0;
        for (var i = 0; i < a.length; i++) {
          maximum = math.max(maximum, (a[i] - b[i]).abs());
        }
        expect(maximum, lessThanOrEqualTo(2));
        cpu.dispose();
        gpu.dispose();
      }
      source.dispose();
    });
  });

  testWidgets('超过八百万像素仍应用非线性滤镜，导出有界且原图不变', (tester) async {
    await tester.runAsync(() async {
      final source = await image(2048, 4096);
      expect(source.width * source.height, greaterThan(8000000));
      final output = await filterComicPage(
        source,
        gamma: 2,
        sharpness: .5,
        denoise: true,
      );
      expect(output.width * output.height, lessThanOrEqualTo(8000000));
      final rgba = (await output.toByteData())!.buffer.asUint8List();
      final offset =
          ((output.height ~/ 2) * output.width + output.width * 3 ~/ 4) * 4;
      for (var channel = 0; channel < 3; channel++) {
        expect(
          rgba[offset + channel],
          closeTo(255 * math.sqrt([32, 80, 128][channel] / 255), 2),
        );
      }
      final original = (await source.toByteData())!.buffer.asUint8List();
      final index =
          ((source.height ~/ 2) * source.width + source.width * 3 ~/ 4) * 4;
      expect(original.sublist(index, index + 3), [32, 80, 128]);
      output.dispose();
      source.dispose();
    });
  });

  testWidgets('长图显示 Shader 遵守裁剪与局部坐标，缩放不改变颜色', (tester) async {
    final source = (await tester.runAsync(() => image(2048, 4096)))!;
    const key = Key('filtered.capture');
    for (final ratio in [1.0, 2.0]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 120,
                height: 240,
                child: ComicShaderArtwork(
                  image: source,
                  geometry: ComicPageGeometry(
                    imageSize: const Size(2048, 4096),
                    source: const Rect.fromLTWH(1024, 0, 1024, 4096),
                    size: const Size(120, 240),
                  ),
                  gamma: 2,
                  sharpness: .5,
                  denoise: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        final shot = await boundary.toImage(pixelRatio: ratio);
        final bytes = (await shot.toByteData())!.buffer.asUint8List();
        final index = ((shot.height ~/ 2) * shot.width + shot.width ~/ 2) * 4;
        expect(bytes[index], closeTo(90, 2));
        expect(bytes[index + 1], closeTo(143, 2));
        expect(bytes[index + 2], closeTo(181, 2));
        shot.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    source.dispose();
    expect(tester.takeException(), isNull);
  });
}
