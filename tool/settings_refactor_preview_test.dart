/// 设置模块 UI / 分类重构的截图预览（开发期用）。
///
/// 运行：`flutter test tool/settings_refactor_preview_test.dart`
/// 产物：`build/ui_snapshot/settings_menu_overview.png`（完整主菜单）
///       `settings_menu_top.png`（上半屏）
///       `settings_module_hub.png`（各模块独立设置）
///       `settings_tab_bar.png`（底部导航栏设置）
///       `settings_app_icon.png`（App 图标）
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
import 'package:lume_box/features/settings/app_icon_settings_page.dart';
import 'package:lume_box/features/settings/module_settings_pages.dart';
import 'package:lume_box/features/settings/settings_page.dart';
import 'package:lume_box/features/settings/tab_bar_settings_page.dart';

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

ThemeData _theme(Brightness brightness) {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUpAll(() async {
    await _loadFonts();
  });

  setUp(() async {
    root = Directory.systemTemp.createTempSync('lume_box_settings_preview');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? root.path
              : null,
        );
    // ignore: invalid_use_of_visible_for_testing_member
    ShellSettingsController.instance.resetForTesting();
    FloatingModules.instance.reset(FloatingModule.dock);
  });

  tearDown(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    ShellSettingsController.instance.resetForTesting();
    FloatingModules.instance.reset(FloatingModule.dock);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> setSurface(
    WidgetTester tester,
    Size size, {
    double dpr = 2,
  }) async {
    tester.view.physicalSize = Size(size.width * dpr, size.height * dpr);
    tester.view.devicePixelRatio = dpr;
    tester.view.viewPadding = FakeViewPadding(top: 59 * dpr);
    tester.view.padding = FakeViewPadding(top: 59 * dpr);
    addTearDown(tester.view.reset);
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

  Future<void> pump(WidgetTester tester, Widget page, Size size) async {
    await setSurface(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        home: page,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('设置主菜单：五组完整长图 + 上半屏', (tester) async {
    // 拉高视口把全部设置项一次布局出来，便于看分组总览。
    await pump(
      tester,
      const SettingsPage(runtimeAvailable: true),
      const Size(390, 2950),
    );
    await capture(tester, 'settings_menu_overview.png');

    // 再按真机一屏高度截一张，检查首屏密度。
    await pump(
      tester,
      const SettingsPage(runtimeAvailable: true),
      const Size(390, 844),
    );
    await capture(tester, 'settings_menu_top.png');
  });

  testWidgets('各模块独立设置：灰色线条小图标', (tester) async {
    await pump(tester, const ModuleSettingsHubPage(), const Size(390, 844));
    await capture(tester, 'settings_module_hub.png');
  });

  testWidgets('底部导航栏设置：数值右对齐 + 放大预览', (tester) async {
    await pump(tester, const TabBarSettingsPage(), const Size(390, 844));
    // 对准「外观与材质」标题：预览卡完整落在顶栏下方，不把上面的说明切一半。
    await Scrollable.ensureVisible(
      tester.element(find.text('外观与材质')),
      alignment: .22,
    );
    await tester.pumpAndSettle();
    await capture(tester, 'settings_tab_bar.png');
  });

  testWidgets('App 图标页', (tester) async {
    await pump(tester, const AppIconSettingsPage(), const Size(390, 844));
    // 测试环境的资源图片是异步解码的；先 precache，截图里才看得到图标。
    final context = tester.element(find.byType(AppIconGrid));
    await tester.runAsync(() async {
      for (final name in <String>[
        'app_icon_1024',
        'Aurora',
        'Obsidian',
        'Solar',
        'Orbit',
        'Prism',
        'Spark',
      ]) {
        await precacheImage(AssetImage('assets/icon/$name.png'), context);
      }
    });
    await tester.pumpAndSettle();
    await capture(tester, 'settings_app_icon.png');
  });
}
