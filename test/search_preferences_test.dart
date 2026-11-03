import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/search/search_settings.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/features/reading/search_results_page.dart';
import 'package:lume_box/features/reading/section_toolbar.dart';

import 'support/fake_reading_source.dart';
import 'support/fake_source_manager.dart';

class SearchFixture extends FakeReadingDataSource {
  SearchFixture() : super(section: Section.video);
  String? received;
  @override
  Future<SourceList> list({
    String? categoryId,
    String? keyword,
    int page = 1,
    Map<String, String>? filters,
  }) async {
    received = keyword;
    return const SourceList(
      items: [
        SourceItem(id: 'match', title: '龍馬'),
        SourceItem(id: 'other', title: '龙马第二部'),
      ],
      hasMore: false,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('search-prefs');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    await SearchSettings.instance.boot();
    await SearchSettings.instance.update(simplify: true, exact: true);
  });
  tearDown(() {
    SearchSettings.instance.simplify = true;
    SearchSettings.instance.exact = false;
    root.deleteSync(recursive: true);
  });
  test('开关落盘重读', () async {
    await SearchSettings.instance.update(simplify: false, exact: true);
    SearchSettings.instance.simplify = true;
    SearchSettings.instance.exact = false;
    await SearchSettings.instance.boot();
    expect(SearchSettings.instance.simplify, isFalse);
    expect(SearchSettings.instance.exact, isTrue);
  });
  for (final mode in SearchMode.values) {
    testWidgets('${mode.label}真实结果页下发简体关键词并筛选同名标题', (tester) async {
      final source = SearchFixture();
      final manager = FakeSourceManager(
        sources: [
          SourceDescriptor(
            id: source.id,
            name: source.name,
            version: '1',
            enabled: true,
          ),
        ],
        opened: {source.id: source},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SearchResultsPage(
            section: Section.video,
            keyword: '龍馬',
            mode: mode,
            manager: manager,
            sourceId: source.id,
            onOpenItem: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(source.received, '龙马');
      expect(find.text('龙马第二部'), findsNothing);
      expect(find.text('龍馬'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
