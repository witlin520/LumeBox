import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/features/reading/explore_view.dart';

import 'support/fake_source_manager.dart';

class _LateMetadataSource extends MockDataSource
    implements FilterCapable, HomeCapable {
  _LateMetadataSource(Section section, this.useHome) : super(section: section);
  final bool useHome;
  final gate = Completer<void>();
  bool ready = false, categoryReady = false;
  @override
  Future<bool> supportsHome() async => useHome;
  @override
  Future<bool> supportsFilters() async => true;
  List<SourceItem> get items =>
      List.generate(30, (i) => SourceItem(id: '$i', title: 'Item $i'));
  @override
  Future<SourceHome> home() async {
    await gate.future;
    ready = true;
    return SourceHome(items: items);
  }

  @override
  Future<SourceList> list({
    String? categoryId,
    String? keyword,
    int page = 1,
    Map<String, String>? filters,
  }) async {
    if (!useHome) {
      await gate.future;
      ready = true;
    }
    return SourceList(items: items, hasMore: false);
  }

  @override
  Future<List<SourceCategory>> categories() async {
    if (!ready) return [];
    await Future<void>.delayed(const Duration(milliseconds: 1));
    categoryReady = true;
    return [const SourceCategory(id: 'movie', title: '分类已就绪')];
  }

  @override
  Future<List<SourceFilterGroup>> filters() async => categoryReady
      ? [
          const SourceFilterGroup(
            id: 'year',
            title: '年份',
            options: [SourceFilterOption(id: '2026', title: '2026年')],
          ),
        ]
      : [];
}

void main() {
  for (final section in [Section.comic, Section.video]) {
    for (final home in [false, true]) {
      testWidgets('${section.id} ${home ? "home" : "list"} 加载后立即补齐筛选并可收缩', (
        tester,
      ) async {
        final dir = Directory.systemTemp.createTempSync('lume-metadata-');
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => dir.path,
        );
        addTearDown(() {
          messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
          dir.deleteSync(recursive: true);
        });
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final source = _LateMetadataSource(section, home);
        await tester.pumpWidget(
          MaterialApp(
            home: ExploreView(
              section: section,
              manager: FakeSourceManager(
                sources: [
                  SourceDescriptor(
                    id: source.id,
                    name: '延迟源',
                    version: '1',
                    enabled: true,
                  ),
                ],
                opened: {source.id: source},
              ),
              onOpenItem: (_) {},
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.text('2026年'), findsNothing);
        source.gate.complete();
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 30));
        }
        expect(find.text('分类已就绪'), findsOneWidget);
        expect(find.text('2026年'), findsOneWidget);
        final headerOpacity = find.byWidgetPredicate(
          (w) => w is AnimatedOpacity && w.child is AnimatedSlide,
        );
        await tester.dragFrom(const Offset(180, 670), const Offset(0, -260));
        await tester.pumpAndSettle();
        expect(tester.widget<AnimatedOpacity>(headerOpacity).opacity, 0);
        await tester.dragFrom(const Offset(180, 500), const Offset(0, 80));
        await tester.pumpAndSettle();
        expect(tester.widget<AnimatedOpacity>(headerOpacity).opacity, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
