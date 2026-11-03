/// AI 图片超分 / 上色设置页与手动处理页的截图预览（开发期用）。
///
/// 运行：`flutter test tool/ai_tools_preview_test.dart`
/// 产物：`build/ui_snapshot/ai_tools_settings.png`（完整设置页）
///       `build/ui_snapshot/ai_tools_manual.png`（手动超分 / 上色 / 翻译页）
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/comic/comic_image_tools_page.dart';

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

ThemeData _theme() {
  final base = LumeTheme.build(brightness: Brightness.light);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'CJK'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'CJK'),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'CJK',
      ),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      titleTextStyle: base.listTileTheme.titleTextStyle?.copyWith(
        fontFamily: 'CJK',
      ),
      subtitleTextStyle: base.listTileTheme.subtitleTextStyle?.copyWith(
        fontFamily: 'CJK',
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List pageBytes;

  setUpAll(() async {
    await _loadFonts();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const rect = Rect.fromLTWH(0, 0, 360, 720);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF6C5CE7), Color(0xFFFF7675)],
        ).createShader(rect),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(360, 720);
    pageBytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
    image.dispose();
    picture.dispose();
  });

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

  testWidgets('AI 超分 / 上色设置页', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 2850 * 2);
    tester.view.devicePixelRatio = 2;
    tester.view.viewPadding = const FakeViewPadding(top: 59 * 2);
    tester.view.padding = const FakeViewPadding(top: 59 * 2);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: const ComicImageToolsSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'ai_tools_settings.png');
  });

  testWidgets('手动超分 / 上色 / 翻译页', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    tester.view.viewPadding = const FakeViewPadding(top: 59 * 2);
    tester.view.padding = const FakeViewPadding(top: 59 * 2);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: ComicImageToolsPage(loadOriginal: () async => pageBytes),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await precacheImage(
        MemoryImage(pageBytes),
        tester.element(find.byType(ComicImageToolsPage)),
      );
    });
    await tester.pumpAndSettle();
    await capture(tester, 'ai_tools_manual.png');
  });
}
