/// 四板块真实分类页的圆角预览（开发期用，不参与常规测试）。
///
/// 运行：`flutter test tool/cover_radius_pages_preview_test.dart`
/// 产物：`build/ui_snapshot/cover_pages_*.png`
///
/// 每个板块截「三列网格」和「双列列表」两种模式，用真实的 ExploreView 与
/// MockDataSource 渲染；封面走 MissingCover 的彩色占位，圆角裁切清晰可见。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/reading/browse_layout.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/reading/explore_view.dart';

import '../test/support/fake_source_manager.dart';

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
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory cacheDir;
  late SectionImagePipeline pipeline;

  setUpAll(() async {
    await _loadFonts();
  });

  setUp(() async {
    root = Directory.systemTemp.createTempSync('lume_box_cover_pages');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? root.path
              : null,
        );
    // ignore: invalid_use_of_visible_for_testing_member
    BrowseLayoutSettings.instance.resetForTesting();
    await BrowseLayoutSettings.instance.boot();
    cacheDir = Directory.systemTemp.createTempSync('lume_box_cover_pages_img');
    pipeline = SectionImagePipeline(cacheDir: cacheDir.path);
  });

  tearDown(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    BrowseLayoutSettings.instance.resetForTesting();
    pipeline.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
  });

  Future<void> pumpPage(
    WidgetTester tester,
    Section section,
    BrowseLayoutMode mode,
  ) async {
    await BrowseLayoutSettings.instance.setMode(section, mode);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _snapshotTheme(),
        // ExploreView 的背景是透明的，正式壳层由 GlassScaffold 铺底色；
        // 预览里补一层页面底色，否则截图会落在黑底上。
        home: ColoredBox(
          color: LumeTheme.base,
          child: ExploreView(
            // 每个板块 / 布局用独立 State：否则测试里复用同一个 ExploreView
            // 状态，截图会一直停在第一个板块的数据上。
            key: ValueKey<String>('${section.id}-${mode.id}'),
            section: section,
            pipeline: pipeline,
            layout: ExploreLayout.list,
            manager: FakeSourceManager(
              sources: <SourceDescriptor>[
                SourceDescriptor(
                  id: 'preview-${section.id}',
                  name: '${section.label}预览源',
                  version: '1.0',
                  enabled: true,
                ),
              ],
              opened: <String, DataSource>{
                'preview-${section.id}': MockDataSource(section: section),
              },
            ),
            onOpenItem: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
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

  testWidgets('四板块真实分类页：三列网格 + 双列列表', (tester) async {
    for (final mode in <BrowseLayoutMode>[
      BrowseLayoutMode.grid3,
      BrowseLayoutMode.list2,
    ]) {
      for (final section in Section.values) {
        await pumpPage(tester, section, mode);
        expect(tester.takeException(), isNull);
        await capture(tester, 'cover_pages_${section.id}_${mode.id}.png');
      }
    }
  });
}
