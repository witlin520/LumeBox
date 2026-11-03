import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/features/reading/aggregate_search_poster.dart';
import 'package:lume_box/features/reading/aggregate_search_results.dart';
import 'package:lume_box/features/reading/section_toolbar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sites = [
    for (var i = 0; i < 3; i++)
      SourceDescriptor(id: 's$i', name: '来源$i', version: '1', enabled: true),
  ];
  final hits = [
    for (var i = 0; i < 18; i++)
      SearchHit(
        sourceId: sites[i % 3].id,
        sourceName: sites[i % 3].name,
        item: SourceItem(id: '$i', title: '示例作品标题$i', subtitle: '更新至第$i集'),
      ),
  ];

  Widget scene({
    double scale = 1,
    ValueChanged<SearchHit>? onOpen,
    Set<String> failed = const {},
  }) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: AggregateSearchResults(
        section: Section.video,
        hits: hits,
        sites: sites,
        completed: const {'s0', 's1', 's2'},
        failed: failed,
        loading: false,
        onOpen: onOpen ?? (_) {},
        onRetry: () {},
      ),
    ),
  );

  for (final width in [320.0, 393.0, 440.0, 768.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'left sidebar retains three columns at width $width and scale $scale',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(scene(scale: scale));
          await tester.pumpAndSettle();
          final rail = tester.getSize(
            find.byKey(const ValueKey('search-sites-left')),
          );
          expect(
            rail.width,
            closeTo(AggregateSearchLayout.sidebarWidth(width), .01),
          );
          final covers = [
            for (var i = 0; i < 4; i++)
              tester.getRect(find.byKey(ValueKey('search-cover-s${i % 3}-$i'))),
          ];
          expect(rail.width, closeTo(width * .26, .01));
          expect(covers[0].top, closeTo(covers[1].top, .01));
          expect(covers[0].top, closeTo(covers[2].top, .01));
          expect(covers[3].top, greaterThan(covers[0].bottom));
          expect(covers[1].left - covers[0].right, closeTo(8, .01));
          expect(covers[2].left - covers[1].right, closeTo(8, .01));
          expect(covers[0].height / covers[0].width, closeTo(1.38, .001));
          final title = tester.getRect(find.text('示例作品标题0'));
          expect(title.top - covers[0].bottom, closeTo(7, .01));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('失败站点使用紧凑提示，窄屏大字不增加整行错误横幅', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(scene(scale: 2, failed: {'s1', 's2'}));
    await tester.pumpAndSettle();
    expect(find.byTooltip('2 个源未取得结果，其他来源正常显示'), findsOneWidget);
    expect(find.text('2 个源未取得结果，其他来源正常显示'), findsNothing);
    final caption = tester.widget<Text>(find.text('示例作品标题0'));
    expect(caption.maxLines, 2);
    expect(caption.textAlign, TextAlign.start);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source filtering keeps the hit identity and complete metadata', (
    tester,
  ) async {
    SearchHit? opened;
    await tester.pumpWidget(scene(onOpen: (hit) => opened = hit));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('search-filter-s1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-hit-s0-0')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('search-hit-s1-1')));
    expect(opened!.sourceId, 's1');
    expect(opened!.item.id, '1');
    expect(find.byTooltip('示例作品标题1\n来源 来源1 · 更新至第1集'), findsOneWidget);
  });

  testWidgets(
    'legacy layouts migrate once to the reference; later explicit choices persist',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'aggregate-three-columns-',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => root.path,
      );
      final library = (await tester.runAsync(
        () => ReadingLibrary.open(Section.video),
      ))!;
      addTearDown(() async {
        ReadingLibrary.disposeAll();
        ReadingStore.disposeAll();
        await SectionScope.closeAll();
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        root.deleteSync(recursive: true);
      });
      library.setSetting('search.results.siteLayout', 'grouped');
      library.setSetting('search.results.cards', 'false');
      await tester.pumpWidget(scene());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-sites-left')), findsOneWidget);
      expect(find.byType(AggregateSearchPoster), findsWidgets);
      await tester.tap(find.byTooltip('搜索结果布局'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, '顶部站点分类'),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(scene());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-sites-top')), findsOneWidget);
    },
  );
}
