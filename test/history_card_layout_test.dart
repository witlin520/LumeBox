import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/reading/history_sheet.dart';
import 'package:lume_box/features/reading/poster_card.dart';
import 'package:lume_box/shared/widgets/glass_card.dart';

/// 历史 / 收藏卡片的三种手机布局：
/// - 三列网格：海报无白边、四角圆角、标题单行、进度只显示「已播 / 总长」；
/// - 双列列表：60×80 缩略图，标题与浅灰相对时间垂直居中；
/// - 单列列表：80×100 缩略图，细进度条用主题色。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  final now = DateTime(2026, 10, 17, 12);

  setUp(() async {
    root = Directory.systemTemp.createTempSync('history-card-layout');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    for (final section in Section.values) {
      await ReadingLibrary.open(section);
    }
    final library = await ReadingLibrary.open(Section.video);
    library.recordHistoryItem(sourceId: 'demo', itemId: 'one', title: '长夜将尽');
    library.saveProgress(
      VideoProgress(
        section: Section.video,
        itemId: 'one',
        chapterIndex: 0,
        chapterId: 'e1',
        chapterTitle: '第 1 集',
        updatedAt: now.subtract(const Duration(minutes: 16)),
        position: const Duration(minutes: 33, seconds: 8),
        duration: const Duration(hours: 2, minutes: 25),
      ),
    );
  });

  tearDown(() async {
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await SectionScope.closeAll();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> pumpMode(WidgetTester tester, String mode) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final library = await ReadingLibrary.open(Section.video);
    library.setSetting('collection.history.layout', mode);
    await tester.pumpWidget(
      MaterialApp(
        theme: LumeTheme.build(),
        home: Scaffold(
          body: ReadingHistorySheet(
            key: ValueKey<String>(mode),
            section: Section.video,
            library: library,
            clock: () => now,
            onResume: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('显示模式只保留单列 / 双列 / 三列，四列五列不再出现', (tester) async {
    await pumpMode(tester, 'list');
    await tester.tap(find.byTooltip('显示模式'));
    await tester.pumpAndSettle();

    for (final label in <String>['单列列表', '双列列表', '三列网格']) {
      expect(find.text(label), findsWidgets, reason: '缺少「$label」');
    }
    for (final removed in <String>['双列网格', '四列网格', '五列网格']) {
      expect(find.text(removed), findsNothing, reason: '「$removed」应已砍掉');
    }
  });

  testWidgets('三列网格：无白边、封面四角圆角、标题单行、进度不带集数', (tester) async {
    await pumpMode(tester, 'grid3');

    final grid = find.byType(HistoryGridTile);
    expect(grid, findsOneWidget);
    expect(
      find.ancestor(of: grid, matching: find.byType(GlassCard)),
      findsNothing,
      reason: '网格卡片不再套白底 GlassCard',
    );

    final cover = find.byKey(const ValueKey('history-grid-cover'));
    expect(cover, findsOneWidget);
    final clip = tester.widget<ClipRRect>(cover);
    expect(clip.borderRadius, BorderRadius.circular(10), reason: '封面四角都要圆角');
    expect(
      clip.child,
      isA<CoverThumb>(),
      reason: 'ClipRRect 直接包封面，中间不能再夹 Padding（白边）',
    );

    final title = find.descendant(of: grid, matching: find.text('长夜将尽'));
    expect(tester.widget<Text>(title).maxLines, 1);
    expect(find.text('33:08 / 2:25:00'), findsOneWidget);
    expect(find.textContaining('第 1 集'), findsNothing, reason: '集数是冗余信息');
  });

  testWidgets('双列列表：60×80 缩略图、浅灰时间与标题垂直居中、主题色细进度条', (tester) async {
    await pumpMode(tester, 'list2');

    final thumb = find.byKey(const ValueKey('history-thumb'));
    expect(tester.getSize(thumb), const Size(60, 80));

    final title = find.text('长夜将尽');
    final time = find.text('16分钟前');
    expect(time, findsOneWidget);
    expect(
      tester.widget<Text>(time).style?.color,
      LumeTheme.descriptionColor,
      reason: '相对时间用浅灰色',
    );
    expect(
      (tester.getCenter(title).dy - tester.getCenter(time).dy).abs(),
      lessThan(2),
      reason: '时间与标题垂直居中',
    );

    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('history-progress')),
    );
    expect(bar.minHeight, 3);
    expect(
      bar.value,
      closeTo((33 * 60 + 8) / (2 * 3600 + 25 * 60), .001),
      reason: '33:08 / 2:25:00 的已播比例',
    );
    expect(bar.backgroundColor, LumeTheme.fillStrong);
    expect(
      (bar.valueColor as AlwaysStoppedAnimation<Color>).value,
      LumeTheme.accent,
      reason: '已播部分是主题色',
    );
  });

  testWidgets('单列列表：80×100 缩略图', (tester) async {
    await pumpMode(tester, 'list');
    final thumb = find.byKey(const ValueKey('history-thumb'));
    expect(tester.getSize(thumb), const Size(80, 100));
  });
}
