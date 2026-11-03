import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/reading/collection_panel.dart';
import 'package:lume_box/features/reading/history_sheet.dart';

/// 猫源历史 / 收藏必须复用视频板块的卡片，而不是自己的一套 ListTile / Card：
/// - 单列：80×100 缩略图、时间、状态、三点菜单；
/// - 双列：60×80 缩略图，与视频同尺寸；
/// - 三列：无白底 Card，封面贴边圆角，文字落在透明背景上。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late ReadingLibrary library;
  final now = DateTime(2026, 10, 17, 12);

  setUp(() async {
    root = Directory.systemTemp.createTempSync('cat_collection_layout');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    library = await ReadingLibrary.open(Section.cat);
  });

  tearDown(() async {
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await SectionScope.closeAll();
    for (var i = 0; i < 5 && root.existsSync(); i++) {
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }
  });

  LibraryItem item(String id, String title, {required Duration ago}) =>
      LibraryItem(
        section: Section.cat,
        itemId: id,
        sourceId: 'demo',
        title: title,
        chapterCount: 12,
        readChapterIndex: -1,
        addedAt: now.subtract(ago),
        updatedAt: now.subtract(ago),
      );

  VideoProgress videoProgress(
    String id,
    Duration ago,
    Duration position,
    Duration duration,
  ) => VideoProgress(
    section: Section.cat,
    itemId: id,
    chapterIndex: 0,
    chapterId: 'e1',
    chapterTitle: '第 1 集',
    updatedAt: now.subtract(ago),
    position: position,
    duration: duration,
  );

  Future<void> pumpMode(WidgetTester tester, String mode) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    library.setSetting('collection.history.layout', mode);

    final items = <LibraryItem>[
      item('played', '长夜将尽', ago: const Duration(minutes: 16)),
      item('fresh', '山与海之间', ago: const Duration(hours: 2)),
      item('saved', '收藏了还没看', ago: const Duration(days: 3)),
    ];
    final progress = <String, VideoProgress?>{
      'played': videoProgress(
        'played',
        const Duration(minutes: 16),
        const Duration(minutes: 33, seconds: 8),
        const Duration(hours: 2, minutes: 25),
      ),
      'fresh': null,
      'saved': null,
    };

    await tester.pumpWidget(
      MaterialApp(
        theme: LumeTheme.build(),
        home: Scaffold(
          body: SizedBox(
            height: 700,
            child: CollectionPanel(
              key: ValueKey<String>(mode),
              title: '历史',
              library: library,
              storageKey: 'collection.history.layout',
              ids: items.map((entry) => entry.itemId).toList(),
              onDelete: (_) async {},
              itemBuilder: (index) => HistoryEntryTile(
                pipeline: null,
                item: items[index],
                progress: progress[items[index].itemId],
                now: now,
                onResume: () {},
              ),
              gridBuilder: (index) => HistoryGridTile(
                item: items[index],
                progress: progress[items[index].itemId],
                pipeline: null,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('猫源历史/收藏复用视频卡片：单列、双列、三列完全同尺寸', (tester) async {
    // 单列：共享卡片、80×100 缩略图、相对时间、尚未开始、三点菜单。
    await pumpMode(tester, 'list');
    expect(find.byType(HistoryEntryTile), findsWidgets);
    expect(find.byType(HistoryGridTile), findsNothing);
    final singleThumb = find.byKey(const ValueKey('history-thumb')).first;
    expect(tester.getSize(singleThumb), const Size(80, 100));
    expect(find.text('尚未开始'), findsWidgets);
    expect(find.text('16分钟前'), findsOneWidget);
    expect(find.byTooltip('更多'), findsWidgets);

    // 双列：60×80，与视频板块的双列完全同尺寸。
    await pumpMode(tester, 'list2');
    final doubleThumb = find.byKey(const ValueKey('history-thumb')).first;
    expect(tester.getSize(doubleThumb), const Size(60, 80));

    // 三列：共享网格卡片，没有白底 Card，封面直接圆角贴边。
    await pumpMode(tester, 'grid3');
    expect(find.byType(HistoryGridTile), findsWidgets);
    final grid = find.byType(HistoryGridTile).first;
    expect(
      find.ancestor(of: grid, matching: find.byType(Card)),
      findsNothing,
      reason: '三列不再使用带白底和内边距的 Card',
    );
    final cover = find.byKey(const ValueKey('history-grid-cover')).first;
    expect(
      tester.widget<ClipRRect>(cover).borderRadius,
      BorderRadius.circular(10),
      reason: '封面直接用 10px 圆角贴边',
    );
    expect(find.text('尚未开始'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
