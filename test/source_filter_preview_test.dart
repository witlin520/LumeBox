import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/features/reading/poster_card.dart';
import 'package:lume_box/features/reading/source_filter_page.dart';

import 'support/fake_reading_source.dart';

void main() {
  testWidgets('筛选上拉页展示源封面，切条件后晚返回的旧结果不会覆盖新结果', (tester) async {
    final source = _PreviewSource();
    final pipeline = _PreviewPipeline();
    addTearDown(pipeline.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SourceFilterPage(
          source: source,
          cache: SourceFilterCache(),
          pipeline: pipeline,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final covers = tester.widgetList<PosterCover>(find.byType(PosterCover));
    expect(covers.single.url, 'https://img.example/default.jpg');
    expect(covers.single.pipeline, same(pipeline));
    await tester.tap(find.text('慢分类'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('新分类'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    source.slow.complete(
      const SourceList(
        items: [
          SourceItem(
            id: 'old',
            title: '旧结果',
            cover: 'https://img.example/old.jpg',
          ),
        ],
      ),
    );
    await tester.pump();
    expect(
      tester.widget<PosterCover>(find.byType(PosterCover)).url,
      'https://img.example/new.jpg',
    );
    expect(find.text('旧结果'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

class _PreviewPipeline extends SectionImagePipeline {
  _PreviewPipeline() : super(cacheDir: 'unused', diskCache: false);
  @override
  Future<ui.Image?> image(
    String url, {
    int? targetWidth,
    bool Function()? isForeground,
  }) async => null;
}

class _PreviewSource extends FakeReadingDataSource {
  _PreviewSource() : super(section: Section.comic);
  final slow = Completer<SourceList>();
  @override
  Future<List<SourceCategory>> categories() async => const [
    SourceCategory(id: 'slow', title: '慢分类'),
    SourceCategory(id: 'new', title: '新分类'),
  ];
  @override
  Future<SourceList> list({
    String? categoryId,
    String? keyword,
    int page = 1,
    Map<String, String>? filters,
  }) async {
    if (categoryId == 'slow') return slow.future;
    return SourceList(
      items: [
        SourceItem(
          id: 'item',
          title: '结果',
          cover: 'https://img.example/${categoryId ?? 'default'}.jpg',
        ),
      ],
    );
  }
}
