import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/shell/shell_settings.dart';
import 'package:lume_box/features/shell/dock_liquid_lens.dart';
import 'package:lume_box/features/shell/shell_dock_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const captureKey = Key('lens.capture');
  const lensRect = Rect.fromLTWH(120, 80, 140, 50);

  Future<Uint8List> pixels(
    WidgetTester tester, {
    bool png = false,
    double ratio = 1,
  }) async => (await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(captureKey))
        .toImage(pixelRatio: ratio);
    final bytes = (await image.toByteData(
      format: png ? ui.ImageByteFormat.png : ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    image.dispose();
    return bytes;
  }))!;

  List<Widget> lensContents(
    bool lens,
    Rect rect,
    VoidCallback? onTap,
    double press,
  ) => [
    Positioned.fromRect(
      rect: rect,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: const SizedBox.expand(),
      ),
    ),
    if (lens)
      Positioned.fromRect(
        rect: rect,
        child: DockLiquidLens(
          path: Path()
            ..addRRect(
              RRect.fromRectAndRadius(
                Offset.zero & rect.size,
                const Radius.circular(25),
              ),
            ),
          press: press,
          stretch: 0,
          highlight: 0,
        ),
      ),
  ];

  Widget scene({
    required bool lens,
    VoidCallback? onTap,
    Rect rect = lensRect,
    bool nested = false,
    double press = 1,
  }) => MaterialApp(
    home: RepaintBoundary(
      key: captureKey,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.black, Colors.white]),
              ),
            ),
          ),
          Positioned.fill(
            child: nested
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(18, 20, 22, 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                        child: RepaintBoundary(
                          child: Stack(
                            children: lensContents(lens, rect, onTap, press),
                          ),
                        ),
                      ),
                    ),
                  )
                : Stack(children: lensContents(lens, rect, onTap, press)),
          ),
        ],
      ),
    ),
  );

  testWidgets('松手静止及页面返回后，透镜保留原像素而非第二个选中圆片', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(scene(lens: false));
    final original = await pixels(tester);
    await tester.pumpWidget(scene(lens: true, press: 1));
    await tester.pump();
    await tester.pumpWidget(scene(lens: true, press: 0));
    await tester.pumpAndSettle();
    expect(find.byKey(DockLiquidLens.filterKey), findsNothing);
    expect(await pixels(tester), orderedEquals(original));
  });

  testWidgets('兼容透镜实时放大背景且中心不漂移，点击穿透并保留裁剪', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(400, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(scene(lens: false));
    final before = await pixels(tester);
    var tapped = false;
    await tester.pumpWidget(scene(lens: true, onTap: () => tapped = true));
    await tester.pump();
    if (ui.ImageFilter.isShaderFilterSupported) {
      for (var frame = 0; frame < 30; frame++) {
        final filter = tester.widget<BackdropFilter>(
          find.byKey(DockLiquidLens.filterKey),
        );
        if (filter.filterConfig?.filter != null) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(
        tester
            .widget<BackdropFilter>(find.byKey(DockLiquidLens.filterKey))
            .filterConfig!
            .filter
            .toString(),
        contains('ImageFilter.shader'),
      );
    }
    // This records the actual renderer rather than assuming a CLI flag enables it.
    debugPrint(
      'Dock lens backdrop shader supported: ${ui.ImageFilter.isShaderFilterSupported}',
    );
    final after = await pixels(tester);
    int red(Uint8List data, int x, int y) => data[(y * 400 + x) * 4];
    expect(red(after, 190, 105), closeTo(red(before, 190, 105), 2));
    expect(red(after, 140, 105), greaterThan(red(before, 140, 105) + 3));
    expect(red(after, 240, 105), lessThan(red(before, 240, 105) - 3));
    expect(red(after, 80, 105), red(before, 80, 105));
    expect(red(after, 120, 80), red(before, 120, 80));
    await tester.tapAt(lensRect.center);
    expect(tapped, isTrue);
    for (final rect in const [
      Rect.fromLTWH(24, 30, 100, 50),
      Rect.fromLTWH(270, 160, 100, 50),
    ]) {
      await tester.pumpWidget(scene(lens: true, rect: rect));
      await tester.pump();
      final moved = await pixels(tester);
      final x = rect.center.dx.round(), y = rect.center.dy.round();
      expect(
        red(moved, x, y),
        closeTo(red(before, x, y), 2),
        reason: '调整位置后透镜中心必须跟随胶囊，而不是固定在屏幕中心',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('透镜适应嵌套磨砂、绘制边界及不同像素密度', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final ratio in [1.0, 2.0, 3.0]) {
      tester.view.devicePixelRatio = ratio;
      const rect = Rect.fromLTWH(24, 30, 100, 50);
      await tester.pumpWidget(scene(lens: false, rect: rect, nested: true));
      final before = await pixels(tester, ratio: ratio);
      await tester.pumpWidget(scene(lens: true, rect: rect, nested: true));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      if (ui.ImageFilter.isShaderFilterSupported) {
        expect(
          tester
              .widget<BackdropFilter>(find.byKey(DockLiquidLens.filterKey))
              .filterConfig!
              .filter
              .toString(),
          contains('ImageFilter.shader'),
        );
      }
      final after = await pixels(tester, ratio: ratio);
      int red(Uint8List data, double x) =>
          data[((75 * ratio).round() * (400 * ratio).round() +
                  (x * ratio).round()) *
              4];
      expect(
        red(after, 92),
        closeTo(red(before, 92), 2),
        reason: '中心必须随局部绘制坐标及 DPR $ratio 更新',
      );
      expect(red(after, 62), greaterThan(red(before, 62) + 1));
      expect(red(after, 122), lessThan(red(before, 122)));
    }
  });

  testWidgets('实际 GLSL 编译并改变采样位置及边缘颜色，零参数保留原像素', (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size(240, 80);
      canvas.drawColor(Colors.white, BlendMode.src);
      for (var x = 0; x < 240; x += 12) {
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), 0, 6, 80),
          Paint()..color = const Color(0xFF182946),
        );
      }
      final picture = recorder.endRecording();
      final input = await picture.toImage(240, 80);
      picture.dispose();
      final program = await ui.FragmentProgram.fromAsset(
        DockLiquidLens.shaderAsset,
      );
      final shader = program.fragmentShader();
      Future<Uint8List> render(
        double strength,
        double dispersion,
        String name,
      ) async {
        shader
          ..setFloat(0, size.width)
          ..setFloat(1, size.height)
          ..setFloat(2, strength)
          ..setFloat(3, dispersion)
          ..setFloat(4, 0)
          ..setFloat(5, 0)
          ..setFloat(6, 0)
          ..setFloat(7, size.width)
          ..setFloat(8, size.height)
          ..setFloat(9, 0)
          ..setFloat(10, 0)
          ..setFloat(11, 0)
          ..setFloat(12, 0)
          ..setFloat(13, 0)
          ..setImageSampler(0, input);
        final rec = ui.PictureRecorder();
        Canvas(rec).drawRect(Offset.zero & size, Paint()..shader = shader);
        final pic = rec.endRecording();
        final output = await pic.toImage(240, 80);
        pic.dispose();
        if (const bool.fromEnvironment('DOCK_LENS_PREVIEW')) {
          final dir = Directory('build/dock-lens-previews')
            ..createSync(recursive: true);
          final png = await output.toByteData(format: ui.ImageByteFormat.png);
          File('${dir.path}/$name.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
        }
        final result = (await output.toByteData())!.buffer.asUint8List();
        output.dispose();
        return result;
      }

      final original = (await input.toByteData())!.buffer.asUint8List();
      final identity = await render(0, 0, 'shader-identity');
      final refracted = await render(.26, 0, 'shader-refraction');
      final dispersed = await render(.26, .02, 'shader-dispersion');
      expect(identity, orderedEquals(original));
      var moved = 0, fringed = 0;
      for (var i = 0; i < original.length; i += 4) {
        if ((refracted[i] - original[i]).abs() > 20) {
          moved++;
        }
        if ((dispersed[i] - refracted[i]).abs() > 20 ||
            (dispersed[i + 2] - refracted[i + 2]).abs() > 20) {
          fringed++;
        }
      }
      expect(moved, greaterThan(1000), reason: '必须实际改变背景采样，不能只画边框');
      expect(fringed, greaterThan(100), reason: '边缘红/蓝通道必须采用不同采样位置');
      shader.dispose();
      input.dispose();
    });
  });

  testWidgets('底栏拖动保持单份页签语义，透镜在图标之后且随水滴变形', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(420, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    if (const bool.fromEnvironment('DOCK_LENS_PREVIEW')) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        );
      await icons.load();
      final font = FontLoader('DockPreview')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
            ),
          ),
        );
      await font.load();
    }
    var selected = 'home';
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: const bool.fromEnvironment('DOCK_LENS_PREVIEW')
              ? 'DockPreview'
              : null,
        ),
        home: RepaintBoundary(
          key: captureKey,
          child: Scaffold(
            backgroundColor: const Color(0xFF789FAD),
            body: StatefulBuilder(
              builder: (context, update) => Align(
                alignment: Alignment.center,
                child: ShellDockBar(
                  entries: const [
                    ShellDockEntry(
                      id: 'home',
                      label: 'Home',
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home,
                    ),
                    ShellDockEntry(
                      id: 'library',
                      label: 'Library',
                      icon: Icons.library_books_outlined,
                      selectedIcon: Icons.library_books,
                    ),
                    ShellDockEntry(
                      id: 'settings',
                      label: 'Settings',
                      icon: Icons.settings_outlined,
                      selectedIcon: Icons.settings,
                    ),
                  ],
                  activeId: selected,
                  onSelect: (id) => update(() => selected = id),
                  appearance: const DockAppearance(
                    horizontalMargin: 24,
                    height: 64,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(InkWell), findsNWidgets(3));
    final pill = find.byKey(ShellDockBar.selectionPillKey);
    final before = tester.getRect(pill);
    final gesture = await tester.startGesture(before.center);
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.moveBy(const Offset(90, 0));
    await tester.pump(const Duration(milliseconds: 30));
    final lens = tester.widget<DockLiquidLens>(find.byType(DockLiquidLens));
    expect(lens.press, greaterThan(0));
    expect(lens.stretch, greaterThan(0));
    expect(tester.getRect(find.byType(DockLiquidLens)), tester.getRect(pill));
    final stack = tester.widget<Stack>(
      find
          .ancestor(
            of: find.byType(DockLiquidLens),
            matching: find.byType(Stack),
          )
          .first,
    );
    final lensIndex = stack.children.indexWhere(
      (child) => child is Positioned && child.child is DockLiquidLens,
    );
    expect(lensIndex, greaterThan(0));
    final rimIndex = stack.children.indexWhere(
      (child) => find
          .descendant(
            of: find.byWidget(child),
            matching: find.byKey(const Key('shell.dock.selectionRim')),
          )
          .evaluate()
          .isNotEmpty,
    );
    expect(rimIndex, greaterThan(lensIndex), reason: '边框在透镜之后画，避免边框被折射成双圈');
    if (const bool.fromEnvironment('DOCK_LENS_PREVIEW')) {
      final png = await pixels(tester, png: true);
      final dir = Directory('build/dock-lens-previews')
        ..createSync(recursive: true);
      final name = ui.ImageFilter.isShaderFilterSupported
          ? 'dock-drag-shader'
          : 'dock-drag-matrix-fallback';
      File('${dir.path}/$name.png').writeAsBytesSync(png);
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, 'library');
    expect(find.text('Library'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
