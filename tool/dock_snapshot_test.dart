/// 底部悬浮 Dock 材质 / 尺寸快照（开发期用，不参与常规测试）。
///
/// 运行：`flutter test tool/dock_snapshot_test.dart`
/// 产物：`build/ui_snapshot/floating_dock.png`（浅色）
///       `build/ui_snapshot/floating_dock_dark.png`（深色）
///
/// 壳层用 `pageBuilder` 注入一块彩色漫画流：真实 Dock 压在有颜色的内容上，
/// 才看得清半透明 + 模糊到底透出了什么，纯白骨架页是看不出玻璃的。
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
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/shell/app_shell.dart';
import 'package:lume_box/features/shell/shell_dock.dart';

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

/// 一块彩色「漫画流」：Dock 下方压着封面与标题，玻璃才不会看起来是实心白块。
class _ColorfulFeed extends StatelessWidget {
  const _ColorfulFeed({required this.dark});

  final bool dark;

  static const List<List<Color>> _covers = <List<Color>>[
    <Color>[Color(0xFF6C5CE7), Color(0xFFA29BFE)],
    <Color>[Color(0xFFFF7675), Color(0xFFFDA085)],
    <Color>[Color(0xFF00B894), Color(0xFF55EFC4)],
    <Color>[Color(0xFF0984E3), Color(0xFF74B9FF)],
    <Color>[Color(0xFFE17055), Color(0xFFFAB1A0)],
    <Color>[Color(0xFFB71540), Color(0xFFFF6B81)],
  ];

  @override
  Widget build(BuildContext context) {
    final text = dark ? Colors.white : const Color(0xFF1A1A1A);
    final sub = dark ? const Color(0xFF9E9EA7) : const Color(0xFF8E8E93);
    return Material(
      color: dark ? const Color(0xFF121214) : const Color(0xFFF6F4F8),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 64, 16, 0),
        children: <Widget>[
          Text(
            '漫剧',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: text,
            ),
          ),
          const SizedBox(height: 4),
          Text('Yomu 原创 · 每周更新', style: TextStyle(fontSize: 14, color: sub)),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _covers.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.62,
            ),
            itemBuilder: (context, index) => ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _covers[index],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      '新番 ${index + 1}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late ShellDockController controller;

  setUpAll(() async {
    await _loadFonts();
  });

  setUp(() async {
    root = Directory.systemTemp.createTempSync('lume_box_dock_preview');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? root.path
              : null,
        );
    // ignore: invalid_use_of_visible_for_testing_member
    LumeJsEngine.debugSupportedOverride = true;
    controller = ShellDockController();
    for (final section in Section.values) {
      await SectionScope.open(section);
    }
  });

  tearDown(() async {
    controller.dispose();
    // ignore: invalid_use_of_visible_for_testing_member
    LumeJsEngine.debugSupportedOverride = null;
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await SectionScope.closeAll();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> capture(
    WidgetTester tester,
    Brightness brightness,
    String name, {
    DockAppearance? appearance,
  }) async {
    ShellSettingsController.instance.apply(
      ShellSettings.defaults.withAppearance(
        appearance ?? DockAppearance.defaults,
      ),
    );
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
        theme: _snapshotTheme(brightness),
        home: AppShell(
          controller: controller,
          desktopRail: false,
          // ignore: invalid_use_of_visible_for_testing_member
          pageBuilder: (_) =>
              _ColorfulFeed(dark: brightness == Brightness.dark),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(tester.takeException(), isNull);
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

  testWidgets('悬浮 Dock 材质：白玻璃与深色玻璃', (tester) async {
    await capture(tester, Brightness.light, 'floating_dock.png');
    await capture(tester, Brightness.dark, 'floating_dock_dark.png');
    // 设置页把参数调大后的真实 Dock（不是设置页里的示意条）：
    // 留白 32 / 高度 60 / 离底 8 / 高光 70% / 阴影 10%。
    await capture(
      tester,
      Brightness.light,
      'floating_dock_custom.png',
      appearance: const DockAppearance(
        horizontalMargin: 32,
        height: 60,
        safeGap: 8,
        borderOpacity: .7,
        shadowOpacity: .1,
      ),
    );
  });
}
