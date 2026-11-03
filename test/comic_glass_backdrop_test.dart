import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:lume_box/shared/widgets/frosted_glass_widget.dart';
import 'package:lume_box/shared/widgets/glass_card.dart';
import 'package:lume_box/core/theme/floating_modules.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/features/comic/comic_glass_backdrop.dart';

class _Artwork extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.red, Colors.blue, Colors.green],
        ).createShader(Offset.zero & size),
    );
    canvas.drawCircle(const Offset(85, 130), 60, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(180, 90), 65, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(_Artwork old) => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = Key('comic.glass.capture');

  testWidgets('iOS 各级悬浮材质透明，正文不参与模糊和淡化', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final module in [
      null,
      FloatingModule.home,
      FloatingModule.navigation,
      FloatingModule.overlay,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: Colors.blue)),
                Center(
                  child: GlassPanel(
                    module: module,
                    radius: 24,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '清晰标题',
                        key: Key('foreground'),
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
      final foreground = find.byKey(const Key('foreground'));
      expect(
        find.ancestor(of: foreground, matching: find.byType(BackdropFilter)),
        findsNothing,
      );
      expect(
        find.ancestor(of: foreground, matching: find.byType(ImageFiltered)),
        findsNothing,
      );
      expect(
        find.ancestor(of: foreground, matching: find.byType(Opacity)),
        findsNothing,
      );
      final fill = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(BackdropFilter),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(fill.color.a, closeTo(.58, .01));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(
      const MaterialApp(
        home: ComicGlassBackdrop(
          radius: 28,
          opacity: .42,
          color: Colors.yellow,
          child: Text('正文'),
        ),
      ),
    );
    final glass = tester.widget<FrostedGlassWidget>(
      find.byType(FrostedGlassWidget),
    );
    expect(glass.opacity, .42);
    expect(glass.color, Colors.yellow);
    expect(glass.neutralTint, isTrue);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('阅读器折射实际采样局部背景，像素密度和位移不破坏点按', (tester) async {
    var taps = 0;
    for (final ratio in [1.0, 2.0, 3.0]) {
      Future<void> pump(bool lens) async {
        Widget surface = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const SizedBox.expand(),
        );
        surface = lens
            ? ComicGlassBackdrop(radius: 28, child: surface)
            : BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: surface,
              );
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(devicePixelRatio: ratio),
              child: Center(
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                    width: 320,
                    height: 260,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(painter: _Artwork()),
                        Positioned(
                          left: 35,
                          top: 60,
                          width: 220,
                          height: 130,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: surface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
      }

      Future<List<int>> pixels() async => (await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        final image = await boundary.toImage(pixelRatio: ratio);
        try {
          return (await image.toByteData())!.buffer.asUint8List().toList();
        } finally {
          image.dispose();
        }
      }))!;
      await pump(false);
      final before = await pixels();
      await pump(true);
      final after = await pixels();
      expect(
        find.descendant(
          of: find.byType(ComicGlassBackdrop),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
      {
        var changed = 0;
        for (var i = 0; i < before.length; i++) {
          if ((before[i] - after[i]).abs() > 1) changed++;
        }
        expect(
          changed,
          greaterThan(100),
          reason: 'DPR $ratio must render actual refraction',
        );
      }
      await tester.tap(find.byType(ComicGlassBackdrop));
      await tester.pump();
    }
    expect(taps, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('叠层圆角玻璃各持自己的 Shader，关闭后释放且不残留交互层', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 400,
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _Artwork())),
                for (var i = 0; i < 3; i++)
                  Positioned(
                    left: i * 15.0,
                    top: i * 50.0,
                    width: 250,
                    height: 200,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: ComicGlassBackdrop(
                        radius: 28,
                        child: ColoredBox(
                          color: Colors.white.withValues(alpha: .6),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.byType(ComicGlassBackdrop), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
