/// 底部 Dock 材质 / 滑动动画的真实渲染预览（开发期用，不参与常规测试）。
///
/// 运行：`flutter test tool/dock_material_preview_test.dart`
/// 产物：`build/ui_snapshot/`
/// - `dock_glass_rest.png`：默认 45% 白 + 15 磨砂，压在一张彩色照片 + 海报墙上
/// - `dock_glass_slide.png`：点到「视频」后 40ms，水滴正在滑动并轻微过冲
/// - `dock_glass_blur_off.png`：同一位置把「磨砂强度」拉到 0（证明滑块真的联动）
/// - `dock_glass_tall_low.png`：高度 150 + 离底 -25（新范围上限）
/// - `dock_glass_extreme_high.png`：150 高 / 100 留白 / 抬高 100 / 满白度与磨砂
/// - `dock_glass_extreme_sink.png`：40 高 / 100 留白 / 离底 -50（压出屏幕）
/// - `dock_glass_compact.png`：40 高 / 100 留白的紧凑下限（文字自动缩放）
/// - `dock_glass_drag_stretch.png`：手指拖拽中，水滴被速度拉成橡皮筋
///
/// 背景优先用 `.tmp_shots/glass_1015.jpg`（本机下载的彩色照片）；文件不存在时
/// 退回纯色海报墙，保证测试本身不依赖外部文件。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/js/lume_js_engine.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/shell/shell_settings.dart';
import 'package:lume_box/core/theme/floating_modules.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/settings/tab_bar_settings_page.dart';
import 'package:lume_box/features/shell/app_shell.dart';
import 'package:lume_box/features/shell/shell_dock.dart';
import 'package:lume_box/features/shell/shell_dock_bar.dart';

const String _fontRoot = r'C:\flutter\bin\cache\artifacts\material_fonts';
const String _cjkFont = r'C:\Windows\Fonts\Deng.ttf';
const String _photoPath = r'.tmp_shots\glass_1015.jpg';

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

ThemeData _snapshotTheme(Brightness brightness) {
  final base = LumeTheme.build(brightness: brightness);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'CJK'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'CJK'),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'CJK',
      ),
    ),
  );
}

/// 一块彩色海报墙：每张「海报」都是真实照片 + 彩色渐变 + 大字号标题。
///
/// Dock 压在它上面时，既能看见照片被磨砂糊开的色块，也能看见海报文字被抹成
/// 柔和的光斑——纯色背景是看不出毛玻璃的。
class _PosterWall extends StatelessWidget {
  const _PosterWall({required this.photo});

  final ui.Image? photo;

  static const List<(List<Color>, String, String)> _posters =
      <(List<Color>, String, String)>[
        (<Color>[Color(0xFF6C5CE7), Color(0xFFE84393)], '漫剧', 'GLASS 01'),
        (<Color>[Color(0xFFFF7675), Color(0xFFFDCB6E)], '电影', 'GLASS 02'),
        (<Color>[Color(0xFF00B894), Color(0xFF0984E3)], '阅读', 'GLASS 03'),
      ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final poster in _posters)
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (photo != null)
                  RawImage(image: photo, fit: BoxFit.cover)
                else
                  const ColoredBox(color: Color(0xFF333333)),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        poster.$1[0].withValues(alpha: .82),
                        poster.$1[1].withValues(alpha: .72),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        poster.$2,
                        style: const TextStyle(
                          fontSize: 30,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        poster.$3,
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: .72),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 整页预览：上半张彩色照片，下半排海报墙一直铺到屏幕底边（Dock 会压在上面）。
class _PreviewPage extends StatelessWidget {
  const _PreviewPage({required this.photo});

  final ui.Image? photo;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (photo != null)
          // 放大 2 倍并锚在顶部：把照片里最鲜艳的峡湾水面留在画面下半部，
          // Dock 后面才有颜色可透。
          ClipRect(
            child: Transform.scale(
              scale: 2.0,
              alignment: Alignment.topCenter,
              child: RawImage(image: photo, fit: BoxFit.cover),
            ),
          )
        else
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0xFF0B3D91), Color(0xFF7C5CFF)],
              ),
            ),
          ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.black.withValues(alpha: .35),
                  Colors.transparent,
                  Colors.black.withValues(alpha: .22),
                ],
                stops: const <double>[0, .35, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '玻璃 / GLASS',
                  style: TextStyle(
                    fontSize: 38,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '真实 Dock 压在彩色照片与海报上 · 能看见背后的色块被磨砂抹开',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: .78),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 海报墙从屏幕下半部铺到最底：Dock 就压在它上面。
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 300,
          child: _PosterWall(photo: photo),
        ),
        // 细斜纹：不模糊时是一根根线，模糊后融成光带，最能说明磨砂在起作用。
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 230,
          child: IgnorePointer(child: CustomPaint(painter: _StripePainter())),
        ),
      ],
    );
  }
}

class _StripePainter extends CustomPainter {
  const _StripePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .14)
      ..strokeWidth = 2;
    for (var x = -size.height; x < size.width; x += 12) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StripePainter oldDelegate) => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late ShellDockController controller;
  ui.Image? photo;

  setUpAll(() async {
    await _loadFonts();
    final file = File(_photoPath);
    if (file.existsSync()) {
      final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
      photo = (await codec.getNextFrame()).image;
    }
  });

  tearDownAll(() {
    photo?.dispose();
  });

  setUp(() async {
    root = Directory.systemTemp.createTempSync('lume_box_dock_material');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? root.path
              : null,
        );
    // ignore: invalid_use_of_visible_for_testing_member
    LumeJsEngine.debugSupportedOverride = true;
    // ignore: invalid_use_of_visible_for_testing_member
    ShellSettingsController.instance.resetForTesting();
    FloatingModules.instance.reset(FloatingModule.dock);
    controller = ShellDockController();
    for (final section in Section.values) {
      await SectionScope.open(section);
    }
  });

  tearDown(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    ShellSettingsController.instance.resetForTesting();
    FloatingModules.instance.reset(FloatingModule.dock);
    controller.dispose();
    // ignore: invalid_use_of_visible_for_testing_member
    LumeJsEngine.debugSupportedOverride = null;
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await SectionScope.closeAll();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(440 * 3, 956 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.viewPadding = const FakeViewPadding(
      top: 59 * 3,
      bottom: 34 * 3,
    );
    tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _snapshotTheme(Brightness.light),
        home: AppShell(
          controller: controller,
          desktopRail: false,
          // ignore: invalid_use_of_visible_for_testing_member
          pageBuilder: (_) => _PreviewPage(photo: photo),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final renderView = tester.binding.renderViews.first;
      final layer = renderView.debugLayer! as OffsetLayer;
      final image = await layer.toImage(renderView.paintBounds);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final output = Directory('build/ui_snapshot')
        ..createSync(recursive: true);
      File('${output.path}/$name').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  testWidgets('Dock 真实材质与滑动动画', (tester) async {
    await pumpShell(tester);
    expect(tester.takeException(), isNull);
    await capture(tester, 'dock_glass_rest.png');

    // 切换到「视频」：40ms（250ms 的 16%）时胶囊走到约六成路程，能明显看到
    // 它悬在「漫画」和「视频」之间，而不是已经落位。
    final video = find
        .descendant(
          of: find.byKey(AppShell.dockKey),
          matching: find.text(Section.video.label),
        )
        .first;
    await tester.tap(video);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await capture(tester, 'dock_glass_slide.png');
    await tester.pumpAndSettle();

    // 把磨砂强度拉到 0：同一背景、同一白度，背后立刻变得清晰。
    FloatingModules.instance.set(
      FloatingModule.dock,
      FloatingModules.instance.style(FloatingModule.dock).copyWith(blur: 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await capture(tester, 'dock_glass_blur_off.png');

    // 设置页的高位档：高度 150 + 负的离底距离。
    FloatingModules.instance.reset(FloatingModule.dock);
    await ShellSettingsController.instance.setAppearance(
      const DockAppearance(height: 150, safeGap: -25),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'dock_glass_tall_low.png');

    // 极限高位：150 高 / 100 留白 / 抬高 100 / 满白度 + 30 磨砂 + 满高光阴影。
    FloatingModules.instance.set(
      FloatingModule.dock,
      const FloatingStyle(opacity: 1, blur: 30),
    );
    await ShellSettingsController.instance.setAppearance(
      const DockAppearance(
        horizontalMargin: 100,
        height: 150,
        safeGap: 100,
        borderOpacity: 1,
        shadowOpacity: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, 'dock_glass_extreme_high.png');

    // 极限下沉：40 高 / 100 留白 / 离底 -50（34pt 安全区下会沉出屏幕 16pt）。
    FloatingModules.instance.set(
      FloatingModule.dock,
      const FloatingStyle(opacity: 1, blur: 30),
    );
    await ShellSettingsController.instance.setAppearance(
      const DockAppearance(
        horizontalMargin: 100,
        height: 40,
        safeGap: -50,
        borderOpacity: 1,
        shadowOpacity: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, 'dock_glass_extreme_sink.png');

    // 紧凑下限但不沉底：验证 40pt 高度里文案会缩放、仍然读得出来。
    FloatingModules.instance.reset(FloatingModule.dock);
    await ShellSettingsController.instance.setAppearance(
      const DockAppearance(
        horizontalMargin: 100,
        height: 40,
        safeGap: 0,
        borderOpacity: 1,
        shadowOpacity: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, 'dock_glass_compact.png');
  });

  testWidgets('拖拽拉伸：水滴跟手变宽（用于拼 GIF）', (tester) async {
    await pumpShell(tester);
    final pill = find.descendant(
      of: find.byKey(AppShell.dockKey),
      matching: find.byKey(ShellDockBar.selectionPillKey),
    );
    final gesture = await tester.startGesture(tester.getCenter(pill));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await capture(tester, 'dock_glass_drag_stretch.png');
    await gesture.up();
    await tester.pumpAndSettle();
    await capture(tester, 'dock_glass_drag_settled.png');
  });

  testWidgets('按压膨胀与动态聚焦（预览）', (tester) async {
    await pumpShell(tester);
    final pill = find.descendant(
      of: find.byKey(AppShell.dockKey),
      matching: find.byKey(ShellDockBar.selectionPillKey),
    );
    final gesture = await tester.startGesture(tester.getCenter(pill));
    await tester.pump();
    // 按满：水滴按当前高度收缩、按当前宽度膨胀；磨砂从 15 动态降到 5.1。
    await tester.pump(const Duration(milliseconds: 800));
    await capture(tester, 'dock_press_focus.png');
    await gesture.up();
    await tester.pumpAndSettle();
    await capture(tester, 'dock_press_released.png');
  });

  testWidgets('选中胶囊滑动逐帧（用于拼 GIF）', (tester) async {
    await pumpShell(tester);
    await capture(tester, 'dock_slide_00.png');

    final video = find
        .descendant(
          of: find.byKey(AppShell.dockKey),
          matching: find.text(Section.video.label),
        )
        .first;
    await tester.tap(video);
    await tester.pump();
    for (var i = 1; i <= 7; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      await capture(tester, 'dock_slide_${i.toString().padLeft(2, '0')}.png');
    }
    await tester.pumpAndSettle();
  });

  testWidgets('管理页里的真实 Dock 预览：滑块改动实时反映在玻璃上', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.viewPadding = const FakeViewPadding(
      top: 59 * 3,
      bottom: 34 * 3,
    );
    tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _snapshotTheme(Brightness.light),
        home: const TabBarSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    final preview = find.byKey(const ValueKey('dock-appearance-preview'));
    await tester.scrollUntilVisible(
      preview,
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(preview), alignment: .12);
    await tester.pumpAndSettle();
    await capture(tester, 'dock_settings_preview.png');

    // 把「玻璃白度」拉到很低、磨砂归零：同一个真实 Dock 立刻变清晰。
    FloatingModules.instance.set(
      FloatingModule.dock,
      const FloatingStyle(opacity: .16, blur: 0),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'dock_settings_preview_linked.png');

    // 极限值下的管理页预览：150 高 / 100 留白 / 100% 白度与磨砂 / 100% 高光阴影。
    FloatingModules.instance.set(
      FloatingModule.dock,
      const FloatingStyle(opacity: 1, blur: 30),
    );
    await ShellSettingsController.instance.setAppearance(
      const DockAppearance(
        horizontalMargin: 100,
        height: 150,
        safeGap: -50,
        borderOpacity: 1,
        shadowOpacity: 1,
      ),
    );
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(preview), alignment: .12);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, 'dock_settings_preview_extreme.png');
  });
}
