import 'package:lume_box/core/media/media_library.dart';

import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/comic/comic_detail_page.dart';
import 'package:lume_box/features/comic/comic_reader_page.dart';
import 'package:lume_box/shared/widgets/glass_card.dart';
import 'package:lume_box/shared/widgets/source_translation.dart';
import 'package:lume_box/shared/widgets/chapter_tile.dart';

import 'support/fake_reading_source.dart';
import 'support/fake_source_manager.dart';

/// 详情页与目录页的验证：元信息、章节正序 / 倒序切换、进阅读器与入架。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late ReadingLibrary comicLibrary;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('lume_box_detail');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? root.path
              : null,
        );
    await MediaLibrary.instance.boot();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('lumebox/mediaTracks'),
          (_) async => {'known': true, 'audio': true, 'video': true},
        );
    comicLibrary = await ReadingLibrary.open(Section.comic);
    comicLibrary.setSetting('comic.detail.compactLayout', 'false');
    await ReadingLibrary.open(Section.video);
  });

  tearDown(() async {
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await SectionScope.closeAll();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  FakeSourceManager managerFor(Section section) => FakeSourceManager(
    sources: const <SourceDescriptor>[
      SourceDescriptor(id: 'a', name: '测试源', version: '1.0', enabled: true),
    ],
    opened: <String, DataSource>{
      'a': FakeReadingDataSource(section: section, chapterCount: 3),
    },
  );

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: LumeTheme.build(), home: child));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
  }

  const comicTarget = ReadingTarget(
    sourceId: 'a',
    itemId: 'item-1',
    title: '测试漫画',
  );

  testWidgets('漫画元信息先显示，慢目录不阻塞标题简介且不误报空目录', (tester) async {
    final source = _SlowChapters();
    final manager = FakeSourceManager(
      sources: const [
        SourceDescriptor(id: 'a', name: '测试源', version: '1', enabled: true),
      ],
      opened: {'a': source},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: LumeTheme.build(),
        home: ComicDetailPage(
          library: comicLibrary,
          manager: manager,
          target: comicTarget,
          runtimeAvailable: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('元信息先返回'), findsWidgets);
    expect(find.textContaining('目录还在请求'), findsOneWidget);
    expect(find.text('正在加载目录…'), findsOneWidget);
    expect(find.text(kNoChaptersHint), findsNothing);
    source.gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('共 1 章'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('漫画详情：元信息、章节列表与倒序切换', (tester) async {
    await pump(
      tester,
      ComicDetailPage(
        library: comicLibrary,
        manager: managerFor(Section.comic),
        target: comicTarget,
        runtimeAvailable: true,
      ),
    );

    expect(find.text('测试作品 item-1'), findsWidgets);
    expect(find.text('共 3 章'), findsOneWidget);
    expect(find.text('开始阅读'), findsOneWidget);
    expect(find.text('加入书架'), findsOneWidget);

    // 正序：第 1 章在上。
    expect(
      tester.getTopLeft(find.text('第 1 章')).dy,
      lessThan(tester.getTopLeft(find.text('第 3 章')).dy),
    );

    await tester.tap(find.text('正序'));
    await tester.pumpAndSettle(); // 切到倒序
    expect(find.text('倒序'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('第 3 章')).dy,
      lessThan(tester.getTopLeft(find.text('第 1 章')).dy),
      reason: '倒序后最后一章排在最前',
    );
  });

  testWidgets('漫画详情：章节条目的触摸区与行距（移动端点得准）', (tester) async {
    await pump(
      tester,
      ComicDetailPage(
        library: comicLibrary,
        manager: managerFor(Section.comic),
        target: comicTarget,
        runtimeAvailable: true,
      ),
    );

    // 章节行 = 含「第 N 章」文字的 GlassCard；量它们的矩形。
    final rects = <Rect>[];
    for (final element in find.byType(GlassCard).evaluate()) {
      final hasTitle = find
          .descendant(
            of: find.byWidget(element.widget),
            matching: find.textContaining(RegExp(r'^第 \d+ 章$')),
          )
          .evaluate()
          .isNotEmpty;
      if (hasTitle) rects.add(tester.getRect(find.byWidget(element.widget)));
    }
    expect(rects.length, greaterThanOrEqualTo(3), reason: '三个章节行都该被量到');

    // 触摸区：整行高度要达到 iOS 的最小触摸目标 44pt（原先约 24pt）。
    for (final rect in rects) {
      expect(
        rect.height,
        greaterThanOrEqualTo(44.0),
        reason: '章节条目高度 ${rect.height}pt 小于 44pt，手指要瞄着点',
      );
    }
    // 行距：相邻两行之间要留间隔，避免点串行。
    for (var i = 1; i < rects.length; i++) {
      final sameRow = (rects[i].top - rects[i - 1].top).abs() < 1;
      final gap = sameRow
          ? rects[i].left - rects[i - 1].right
          : rects[i].top - rects[i - 1].bottom;
      expect(
        gap,
        greaterThanOrEqualTo(8.0),
        reason: '相邻章节之间只有 ${gap}pt 间隔，容易误点相邻行',
      );
    }
    // 全局可读性调整：标题用统一的 LumeTypography.titleSize。
    final title = tester.widget<Text>(find.text('第 1 章'));
    expect(title.style?.fontSize, 16);
  });

  testWidgets('原版目录两列、切换持久化、搜索及书架旁翻译入口', (tester) async {
    await pump(
      tester,
      ComicDetailPage(
        library: comicLibrary,
        manager: managerFor(Section.comic),
        target: comicTarget,
        runtimeAvailable: true,
      ),
    );
    Rect chapter(int index) => tester.getRect(
      find.byKey(ValueKey('comic-detail-original-chapter-$index')),
    );
    expect(chapter(0).top, chapter(1).top);
    expect(chapter(1).left - chapter(0).right, 10);
    expect(chapter(0).height, 52);
    await tester.tap(find.byTooltip('章节列数'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<int>, '一列'));
    await tester.pumpAndSettle();
    expect(comicLibrary.setting('comic.detail.originalColumns'), '1');
    expect(chapter(1).top, greaterThan(chapter(0).bottom));
    await tester.tap(find.byTooltip('搜索章节'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '第 2 章');
    await tester.pumpAndSettle();
    expect(find.text('第 1 章'), findsNothing);
    expect(find.byKey(const ValueKey('comic-detail-original-chapter-1')), findsOneWidget);
    await tester.tap(find.byTooltip('显示全部章节'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 章'), findsOneWidget);
    final actions = find
        .ancestor(of: find.text('加入书架'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(
        of: actions,
        matching: find.byType(SourceTranslationAction),
      ),
      findsOneWidget,
    );
  });

  testWidgets('漫画详情：点章节进阅读器，只写历史，不自动收藏', (tester) async {
    await pump(
      tester,
      ComicDetailPage(
        library: comicLibrary,
        manager: managerFor(Section.comic),
        target: comicTarget,
        runtimeAvailable: true,
      ),
    );

    // 只打开详情页也不该自动收藏；只留下 favorite = 0 的历史行。
    expect(comicLibrary.onShelf('item-1'), isFalse);
    expect(
      comicLibrary.history().map((item) => item.itemId),
      contains('item-1'),
    );

    await tester.tap(find.text('第 2 章'));
    await tester.pumpAndSettle();

    expect(find.byType(ComicReaderPage), findsOneWidget);
    expect(
      comicLibrary.onShelf('item-1'),
      isFalse,
      reason: '阅读不是收藏，收藏只能由用户点「加入书架」',
    );
    expect(
      comicLibrary.history().map((item) => item.itemId),
      contains('item-1'),
    );
    final progress = comicLibrary.comicProgress('item-1')!;
    expect(progress.chapterIndex, 1);
  });
}

class _SlowChapters extends FakeReadingDataSource {
  _SlowChapters() : super(section: Section.comic, chapterCount: 1);
  final gate = Completer<void>();
  @override
  Future<SourceDetail?> detail(String itemId) async =>
      SourceDetail(id: itemId, title: '元信息先返回', description: '目录还在请求，简介已经可读');
  @override
  Future<List<SourceChapter>> chapters(String itemId) async {
    await gate.future;
    return super.chapters(itemId);
  }
}
