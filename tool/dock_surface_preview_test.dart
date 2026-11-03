/// 开发期预览：在 Impeller 下渲染真实 [ShellDockBar] 的静止/按压画面，
/// 用来目视检查“底座局部清澈 + 透镜保留背景细节”。
///
/// 运行：`flutter test --enable-impeller tool/dock_surface_preview_test.dart`
/// 产物：`build/dock-surface-preview/`
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/shell/shell_settings.dart';
import 'package:lume_box/core/theme/floating_modules.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/shell/dock_liquid_surface.dart';
import 'package:lume_box/features/shell/shell_dock_bar.dart';

const Key _captureKey = Key('surface.capture');
const String _fontRoot = r'C:\flutter\bin\cache\artifacts\material_fonts';
const String _cjkFont = r'C:\Windows\Fonts\Deng.ttf';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final path = '$_fontRoot\\$file';
      if (!File(path).existsSync()) continue;
      loader.addFont(
        File(path).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
      );
    }
    await loader.load();
  }

  await load('Roboto', <String>[
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]);
  await load('MaterialIcons', <String>['materialicons-regular.otf']);
  final cjk = FontLoader('CJK');
  if (File(_cjkFont).existsSync()) {
    cjk.addFont(
      File(_cjkFont).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
    );
  }
  await cjk.load();
}

class _PagePainter extends CustomPainter {
  const _PagePainter();

  static const List<List<Color>> _posters = <List<Color>>[
    <Color>[Color(0xFF6C5CE7), Color(0xFFA29BFE)],
    <Color>[Color(0xFFFF7675), Color(0xFFFDA085)],
    <Color>[Color(0xFF00B894), Color(0xFF55EFC4)],
    <Color>[Color(0xFF0984E3), Color(0xFF74B9FF)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF7F7FA),
    );
    final title = TextPainter(
      text: const TextSpan(
        text: 'Comedy',
        style: TextStyle(
          color: Color(0xFF121212),
          fontSize: 30,
          fontWeight: FontWeight.w800,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    title.paint(canvas, const Offset(24, 24));
    // 参考录屏的页面：白底 + 一排彩色海报，Dock 压在卡片下沿上。
    for (var i = 0; i < 4; i++) {
      final rect = Rect.fromLTWH(16.0 + i * 104, 150, 96, 150);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(10)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _posters[i],
          ).createShader(rect),
      );
      final label = TextPainter(
        text: TextSpan(
          text: 'Channel ${i + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFamily: 'Roboto',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(rect.left + 8, rect.bottom - 22));
    }
  }

  @override
  bool shouldRepaint(_PagePainter oldDelegate) => false;
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  static const List<Color> _bands = <Color>[
    Color(0xFFFFD400),
    Color(0xFFFF3B7F),
    Color(0xFF8B5CF6),
    Color(0xFF00E0FF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF1E3A8A),
            Color(0xFFB91C1C),
            Color(0xFF0F766E),
            Color(0xFFB45309),
          ],
        ).createShader(rect),
    );
    // 3px 黑白细条纹 + 彩色横带：模糊后细节是否保留一眼可见。
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 3, size.height),
        Paint()..color = Colors.white.withValues(alpha: .9),
      );
      canvas.drawRect(
        Rect.fromLTWH(x + 3, 0, 3, size.height),
        Paint()..color = const Color(0xFF10131A).withValues(alpha: .8),
      );
    }
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, 60.0 + i * 54, size.width, 22),
        Paint()..color = _bands[i].withValues(alpha: .75),
      );
    }
    // 文字块：观察透镜对文字的放大与弯曲。
    final text = TextPainter(
      text: const TextSpan(
        text: 'LUMEBOX · GLASS',
        style: TextStyle(
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, const Offset(24, 210));
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) => false;
}

Widget _scene({
  required VoidCallback onSelect,
  required CustomPainter background,
  DockAppearance appearance = const DockAppearance(),
}) {
  final base = LumeTheme.build();
  final theme = base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'CJK'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'CJK'),
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    home: RepaintBoundary(
      key: _captureKey,
      child: Scaffold(
        body: Stack(
          children: <Widget>[
            Positioned.fill(child: CustomPaint(painter: background)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: ShellDockBar(
                entries: const <ShellDockEntry>[
                  ShellDockEntry(
                    id: 'comic',
                    label: '漫画',
                    icon: Icons.auto_stories_outlined,
                    selectedIcon: Icons.auto_stories_rounded,
                  ),
                  ShellDockEntry(
                    id: 'video',
                    label: '视频',
                    icon: Icons.play_circle_outline_rounded,
                    selectedIcon: Icons.play_circle_fill_rounded,
                  ),
                  ShellDockEntry(
                    id: 'cat',
                    label: '猫源',
                    icon: Icons.pets_outlined,
                    selectedIcon: Icons.pets_rounded,
                  ),
                  ShellDockEntry(
                    id: 'settings',
                    label: '设置',
                    icon: Icons.settings_outlined,
                    selectedIcon: Icons.settings_rounded,
                  ),
                ],
                activeId: 'comic',
                onSelect: (_) => onSelect(),
                appearance: appearance,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<Uint8List> _pixels(WidgetTester tester, {bool png = false}) async =>
    (await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(find.byKey(_captureKey))
          .toImage(pixelRatio: 1);
      final bytes = (await image.toByteData(
        format: png ? ui.ImageByteFormat.png : ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      image.dispose();
      return bytes;
    }))!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dock surface preview', (tester) async {
    // ignore: avoid_print
    print('PREVIEW step 0: fonts');
    // FontLoader 的加载回调要通过引擎异步完成；在 flutter_tester 的
    // 伪时钟里必须放进 runAsync，否则 --enable-impeller 下会一直等。
    await tester.runAsync(_loadFonts);
    // ignore: avoid_print
    print('PREVIEW step 1: surface size');
    await tester.binding.setSurfaceSize(const Size(440, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final modules = FloatingModules.instance;
    final original = modules.style(FloatingModule.dock);
    addTearDown(() => modules.set(FloatingModule.dock, original));
    modules.set(FloatingModule.dock, original.copyWith(opacity: .45, blur: 15));

    final out = Directory('build/dock-surface-preview')
      ..createSync(recursive: true);
    final tag = DockLiquidSurface.shaderSupported ? 'gpu' : 'cpu';
    Future<void> capture(String name) async {
      final png = await _pixels(tester, png: true);
      File('${out.path}/$tag-$name.png').writeAsBytesSync(png);
    }

    final backgrounds = <String, CustomPainter>{
      'page': const _PagePainter(),
      'stripes': const _BackdropPainter(),
    };
    for (final entry in backgrounds.entries) {
      final bg = entry.key;
      // ignore: avoid_print
      print('PREVIEW background=$bg');
      await tester.pumpWidget(_scene(onSelect: () {}, background: entry.value));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      await capture('$bg-idle');

      // 按住第二个页签，等按压动画走满、shader 资源载入。
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('视频')),
      );
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        final filters = tester
            .widgetList<BackdropFilter>(
              find.byKey(ShellDockBar.capsuleFilterKey),
            )
            .toList();
        final ready = filters.any(
          (filter) => filter.filterConfig is DockLiquidSurfaceFilter,
        );
        if (ready && i > 8) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await capture('$bg-held');
      await gesture.moveBy(const Offset(-90, 0));
      await tester.pump(const Duration(milliseconds: 120));
      await capture('$bg-dragging');
      await gesture.up();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await capture('$bg-released');
    }

    // 基础形状对照组：同一页面背景下按住时的四种规则形状。
    for (final shape in DockLensShape.values) {
      // ignore: avoid_print
      print('PREVIEW shape=${shape.name}');
      final appearance = DockAppearance(
        liquid: const DockLiquidSettings()
            .withShape(shape)
            .withValue(
              DockLiquidParameter.shapeRoundness,
              shape == DockLensShape.roundedRect ? .45 : 1,
            ),
      );
      await tester.pumpWidget(
        _scene(
          onSelect: () {},
          background: const _PagePainter(),
          appearance: appearance,
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      await capture('shape-${shape.name}-idle');
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('视频')),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await capture('shape-${shape.name}-held');
      await gesture.up();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    // 可选“局部收腰”效果：默认关闭，这里拉满做视觉对照。
    {
      final appearance = DockAppearance(
        liquid: const DockLiquidSettings().withValue(
          DockLiquidParameter.waist,
          1,
        ),
      );
      await tester.pumpWidget(
        _scene(
          onSelect: () {},
          background: const _PagePainter(),
          appearance: appearance,
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('视频')),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await capture('waist-held');
      await gesture.up();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    // ignore: avoid_print
    print(
      'PREVIEW done shaderSupported=${DockLiquidSurface.shaderSupported} '
      'surface=${find.byType(DockLiquidSurface).evaluate().length} '
      'out=${out.path}',
    );
    expect(tester.takeException(), isNull);
  });
}
