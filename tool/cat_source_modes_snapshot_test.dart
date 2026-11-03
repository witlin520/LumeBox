/// 猫源单列 / 双列独立预览快照（开发期用，不参与常规测试）。
///
/// 运行：`flutter test tool/cat_source_modes_snapshot_test.dart`
/// 产物：`build/ui_snapshot/cat_source_modes.png`
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/theme/lume_theme.dart';

import 'cat_source_modes_preview.dart';

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

ThemeData _snapshotTheme() {
  final base = LumeTheme.build();
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

  setUpAll(() async {
    await _loadFonts();
  });

  testWidgets('猫源单列 / 双列：文字都居中', (tester) async {
    tester.view.physicalSize = const Size(980, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _snapshotTheme(),
        home: CatSourceModesBody(dark: false, onToggle: () {}),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    // 两个面板各滑开第一张卡，预览里直接看到设置/删除。
    await tester.drag(
      find.byKey(const ValueKey('picker-source-cat-1')).first,
      const Offset(-100, 0),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('picker-source-cat-1')).last,
      const Offset(-100, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final renderView = tester.binding.renderViews.first;
      final layer = renderView.debugLayer! as OffsetLayer;
      final image = await layer.toImage(renderView.paintBounds);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final output = Directory('build/ui_snapshot')
        ..createSync(recursive: true);
      File('${output.path}/cat_source_modes.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
