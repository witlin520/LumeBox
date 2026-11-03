import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/features/video/detail_poster_background.dart';

void main() {
  test('背景明暗与色彩独立调节，默认保持当前取色', () {
    const seed = Color(0xff2c3948);
    expect(adjustDetailBackground(seed), seed);
    expect(
      adjustDetailBackground(seed, brightness: 2).computeLuminance(),
      greaterThan(seed.computeLuminance()),
    );
    expect(
      adjustDetailBackground(seed, saturation: 0).r,
      closeTo(adjustDetailBackground(seed, saturation: 0).b, .001),
    );
  });
  testWidgets('海报亮度可实时更新，关闭渐变保留图片，渐变末端露出原背景', (tester) async {
    final key = GlobalKey();
    Future<ByteData> capture(double brightness, double strength) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 100,
                height: 100,
                child: ColoredBox(
                  color: Colors.blue,
                  child: DetailPosterFade(
                    brightness: brightness,
                    strength: strength,
                    child: const ColoredBox(color: Color(0xffff0000)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        image.dispose();
        return bytes;
      }))!;
    }

    final bright = await capture(1, 0);
    final dim = await capture(.5, 0);
    final faded = await capture(.5, 3);
    final gradual = await capture(1, 1);
    int baseContribution(int y) => gradual.getUint8((y * 100 + 50) * 4 + 2);
    expect(baseContribution(60), greaterThan(0));
    expect(baseContribution(75), greaterThan(baseContribution(60)));
    expect(baseContribution(90), greaterThan(baseContribution(75)));
    expect(baseContribution(99), greaterThan(baseContribution(90)));
    expect(baseContribution(99), greaterThanOrEqualTo(240));
    final top = (10 * 100 + 50) * 4;
    final bottom = (99 * 100 + 50) * 4;
    expect(bright.getUint8(top), greaterThan(250));
    expect(dim.getUint8(top), inInclusiveRange(125, 130));
    expect(dim.getUint8(bottom + 2), 0);
    expect(faded.getUint8(bottom + 2), greaterThan(240));
  });
  testWidgets('正文底色沿同一色相逐步加深，末端衔接页面底色', (tester) async {
    const base = Color(0xff542424);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 100,
              height: 200,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: detailPosterSurfaceGradient(base),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final bytes = (await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes;
    }))!;
    Color pixel(int y) {
      final i = (y * 100 + 50) * 4;
      return Color.fromARGB(
        255,
        bytes.getUint8(i),
        bytes.getUint8(i + 1),
        bytes.getUint8(i + 2),
      );
    }

    expect(
      pixel(100).computeLuminance(),
      greaterThan(pixel(150).computeLuminance()),
    );
    expect(
      pixel(150).computeLuminance(),
      greaterThan(pixel(199).computeLuminance()),
    );
    expect((pixel(199).r - base.r).abs(), lessThan(2 / 255));
    expect((pixel(199).g - base.g).abs(), lessThan(2 / 255));
    expect(pixel(150).r, greaterThan(pixel(150).b));
  });

  test('紧凑版保留海报冷暖色相，同时保证浅深色文字对比', () {
    final lightColors = <Color>{};
    for (final seed in [
      Colors.red,
      Colors.orange,
      Colors.blue,
      Colors.green,
      Colors.grey,
      Colors.black,
      Colors.white,
    ]) {
      final light = compactPosterPageColor(seed, brightness: Brightness.light);
      final dark = compactPosterPageColor(seed, brightness: Brightness.dark);
      lightColors.add(light);
      expect(HSLColor.fromColor(light).saturation, lessThanOrEqualTo(.31));
      expect(
        (light.computeLuminance() + .05) /
            (const Color(0xFF16171B).computeLuminance() + .05),
        greaterThan(10),
      );
      expect(1.05 / (dark.computeLuminance() + .05), greaterThan(10));
      expect(light.a, 1);
      expect(dark.a, 1);
    }
    expect(
      lightColors.length,
      greaterThanOrEqualTo(5),
      reason: '不同海报应产生可区分的底色',
    );
    final warm = compactPosterPageColor(
      Colors.orange,
      brightness: Brightness.light,
    );
    final cool = compactPosterPageColor(
      Colors.blue,
      brightness: Brightness.light,
    );
    expect(warm.r, greaterThan(warm.b));
    expect(cool.b, greaterThan(cool.r));
  });

  testWidgets('海报底部真正淡出到底图，而不是叠黑色蒙层', (tester) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: boundary,
            child: const SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: Colors.blue),
                  DetailPosterFade(child: ColoredBox(color: Colors.red)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late ui.Image image;
    ByteData? pixels;
    await tester.runAsync(() async {
      image = await render.toImage(pixelRatio: 1);
      pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    });
    final top = (10 * 100 + 50) * 4;
    final bottom = (99 * 100 + 50) * 4;
    expect(pixels!.getUint8(top), greaterThan(240));
    expect(pixels!.getUint8(bottom + 2), greaterThan(240));
    expect(pixels!.getUint8(bottom + 3), 255);
    image.dispose();
  });

  testWidgets('无 TMDB 背景图时展示源封面，模糊层隔离滚动重绘', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DetailPosterBackground(
          backdrop: null,
          fallback: ColoredBox(key: Key('source-cover'), color: Colors.red),
          tint: Color(0xff542424),
        ),
      ),
    );
    expect(find.byKey(const Key('source-cover')), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
    final filter = find.byType(ImageFiltered);
    expect(
      find.ancestor(of: filter, matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
  });
}
