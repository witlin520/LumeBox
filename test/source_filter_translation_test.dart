import 'dart:io';

import 'package:lume_box/core/reading/reading.dart';

import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/features/reading/source_filter_page.dart';

import 'support/fake_reading_source.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/translation/text_translation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('source-translation-');
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    await TextTranslationService.shared.boot();
  });
  tearDownAll(() async {
    messenger.setMockMethodCallHandler(TextTranslationService.channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await directory.delete(recursive: true);
  });

  testWidgets('筛选翻译包含分类、分组和选项，更新标签但保留原站ID', (tester) async {
    final sent = <String>[];
    messenger.setMockMethodCallHandler(TextTranslationService.channel, (
      call,
    ) async {
      final texts = List<String>.from((call.arguments as Map)['texts']);
      sent.addAll(texts);
      return texts
          .map(
            (s) =>
                {
                  'Mystery category': '神秘分类',
                  'Collection label': '集合',
                  'Rare option': '稀有选项',
                }[s] ??
                s,
          )
          .toList();
    });
    final source = _FilterTranslationSource();
    final pipeline = SectionImagePipeline(
      cacheDir: directory.path,
      diskCache: false,
    );
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
    await tester.tap(find.byTooltip('翻译成中文'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(
      sent,
      containsAll(['Mystery category', 'Collection label', 'Rare option']),
    );
    expect(find.text('神秘分类'), findsOneWidget);
    expect(find.text('稀有选项'), findsOneWidget);
    await tester.tap(find.text('神秘分类'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(source.lastCategory, 'original-id');
    await tester.pumpWidget(const SizedBox());
    var flushed = false;
    TextTranslationService.shared.flush().then((_) => flushed = true);
    for (var i = 0; i < 30 && !flushed; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(flushed, isTrue);
    if (TextTranslationService.shared.displayOriginal) {
      TextTranslationService.shared.toggleOriginal();
    }
  });
}

class _FilterTranslationSource extends FakeReadingDataSource
    implements FilterCapable {
  _FilterTranslationSource() : super(section: Section.comic);
  String? lastCategory;
  @override
  Future<bool> supportsFilters() async => true;
  @override
  Future<List<SourceCategory>> categories() async => const [
    SourceCategory(id: 'original-id', title: 'Mystery category'),
  ];
  @override
  Future<List<SourceFilterGroup>> filters() async => const [
    SourceFilterGroup(
      id: 'group-id',
      title: 'Collection label',
      options: [SourceFilterOption(id: 'option-id', title: 'Rare option')],
    ),
  ];
  @override
  Future<SourceList> list({
    String? categoryId,
    String? keyword,
    int page = 1,
    Map<String, String>? filters,
  }) async {
    lastCategory = categoryId;
    return const SourceList(items: [], hasMore: false);
  }
}
