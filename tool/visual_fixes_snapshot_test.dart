/// 本轮视觉修复的预览快照（开发期用，不参与常规测试）。
///
/// 运行：`flutter test tool/visual_fixes_snapshot_test.dart`
/// 产物：`build/ui_snapshot/home_badge.png` / `filter_footer.png`
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/source/source_subscription_sync.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/comic/comic_page.dart';
import 'package:lume_box/features/reading/browse_choice_access.dart';

import '../test/support/fake_reading_source.dart';
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
    // 筛选标签读 chipTheme.labelStyle，单独补上中文字族，预览才不是方块。
    chipTheme: base.chipTheme.copyWith(
      labelStyle: base.chipTheme.labelStyle?.copyWith(fontFamily: 'CJK'),
      secondaryLabelStyle: base.chipTheme.secondaryLabelStyle?.copyWith(
        fontFamily: 'CJK',
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory output;
  late ReadingLibrary comicLibrary;

  setUpAll(() async {
    await _loadFonts();
  });

  setUp(() async {
    root = Directory.systemTemp.createTempSync('lume_box_visual_fixes');
    output = Directory('build/ui_snapshot')..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? root.path
              : null,
        );
    comicLibrary = await ReadingLibrary.open(Section.comic);
  });

  tearDown(() async {
    SourceSubscriptionSync.acknowledge(Section.comic);
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await SectionScope.closeAll();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final renderView = tester.binding.renderViews.first;
      final layer = renderView.debugLayer! as OffsetLayer;
      final image = await layer.toImage(renderView.paintBounds);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${output.path}/$name.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(414, 896));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _snapshotTheme(),
        home: child,
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('首页：23 条订阅更新的紧凑角标', (tester) async {
    for (var index = 1; index <= 8; index++) {
      comicLibrary.shelve(
        sourceId: 'a',
        itemId: 'shelf-$index',
        title: '书架作品 $index',
        subtitle: '作者 · 连载中',
        chapterCount: 30,
      );
    }
    for (var i = 0; i < 23; i++) {
      SourceSubscriptionSync.recordChange(
        Section.comic,
        'notice-$i',
        '订阅站点 $i',
        '已更新',
      );
    }
    final manager = FakeSourceManager(
      sources: const <SourceDescriptor>[
        SourceDescriptor(id: 'a', name: '漫画示例源', version: '1.0', enabled: true),
      ],
      opened: <String, DataSource>{
        'a': FakeReadingDataSource(section: Section.comic),
      },
    );
    await pump(
      tester,
      ComicPage(
        library: comicLibrary,
        manager: manager,
        runtimeAvailable: true,
      ),
    );
    expect(tester.takeException(), isNull);
    await capture(tester, 'home_badge');
  });

  testWidgets('筛选面板：内收 16px 的圆角悬浮操作栏', (tester) async {
    tester.view.physicalSize = const Size(414, 896);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _snapshotTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showBrowseFilters(
                  context: context,
                  categories: const [
                    SourceCategory(id: 'movie', title: '电影'),
                    SourceCategory(id: 'series', title: '电视剧'),
                    SourceCategory(id: 'anime', title: '动漫'),
                  ],
                  groups: [
                    SourceFilterGroup(
                      id: 'type',
                      title: '类型',
                      options: [
                        for (final label in ['动作', '喜剧', '科幻', '爱情'])
                          SourceFilterOption(id: label, title: label),
                      ],
                    ),
                    SourceFilterGroup(
                      id: 'area',
                      title: '地区',
                      options: [
                        for (final label in ['中国大陆', '中国香港', '美国', '日本'])
                          SourceFilterOption(id: label, title: label),
                      ],
                    ),
                    SourceFilterGroup(
                      id: 'year',
                      title: '年份',
                      options: [
                        for (final label in ['2026', '2025', '2024'])
                          SourceFilterOption(id: label, title: label),
                      ],
                    ),
                  ],
                  category: 'movie',
                  filters: const {'type': '动作', 'area': '中国大陆'},
                ),
                child: const Text('打开分类与筛选'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开分类与筛选'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('filter-footer')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'filter_footer');
  });
}
