import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/features/reading/section_toolbar.dart';
import 'package:lume_box/features/reading/source_search_dialog.dart';

import 'support/fake_reading_source.dart';

class _DeferredSource extends FakeReadingDataSource implements SuggestCapable {
  _DeferredSource() : super(section: Section.cat);
  final requests = <String, Completer<List<String>>>{};
  @override
  Future<List<String>> suggest(String keyword) =>
      (requests[keyword] = Completer<List<String>>()).future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'reopening a query immediately restores matching history and calls source suggestions',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('search-reopen');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => root.path,
          );
      final library = (await tester.runAsync(
        () => ReadingLibrary.open(Section.cat),
      ))!;
      addTearDown(() async {
        ReadingLibrary.disposeAll();
        ReadingStore.disposeAll();
        await SectionScope.closeAll();
        root.deleteSync(recursive: true);
      });
      SearchHistoryStore(Section.cat, library).remember('龙马历史');
      final source = _DeferredSource();
      String? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  submitted = await showDialog<String>(
                    context: context,
                    builder: (_) => SourceSearchDialog(
                      source: source,
                      library: library,
                      initialQuery: '龙马',
                      candidateTitles: const ['龙马第二部'],
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('龙马历史'), findsOneWidget);
      expect(find.text('龙马第二部'), findsOneWidget);
      expect(source.requests.containsKey('龙马'), isTrue);
      source.requests['龙马']!.complete(['龙马最新']);
      await tester.pumpAndSettle();
      expect(find.text('龙马最新'), findsOneWidget);
      await tester.tap(find.text('龙马最新'));
      await tester.pumpAndSettle();
      expect(submitted, '龙马最新');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    '300ms debounce, stale responses discarded including clear/retype, local history can be cleared',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('search-race');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => root.path,
          );
      final library = (await tester.runAsync(
        () => ReadingLibrary.open(Section.cat),
      ))!;
      addTearDown(() async {
        ReadingLibrary.disposeAll();
        ReadingStore.disposeAll();
        await SectionScope.closeAll();
        root.deleteSync(recursive: true);
      });
      SearchHistoryStore(Section.cat, library).remember('本机历史');
      final source = _DeferredSource();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SourceSearchDialog(
              source: source,
              library: library,
              initialQuery: '',
            ),
          ),
        ),
      );
      expect(find.text('本机历史'), findsOneWidget);
      await tester.tap(find.text('清空全部历史'));
      await tester.pump();
      expect(SearchHistoryStore(Section.cat, library).load(), isEmpty);
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump(const Duration(milliseconds: 299));
      expect(source.requests, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      final old = source.requests['a']!;
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump(const Duration(milliseconds: 300));
      source.requests['ab']!.complete(['ab 最新标题']);
      await tester.pumpAndSettle();
      expect(find.text('ab 最新标题'), findsOneWidget);
      old.complete(['a 过期标题']);
      await tester.pump();
      expect(find.text('a 过期标题'), findsNothing);
      expect(find.text('ab 最新标题'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump(const Duration(milliseconds: 300));
      final cleared = source.requests['abc']!;
      await tester.enterText(find.byType(TextField), '');
      cleared.complete(['abc 已清空标题']);
      await tester.pump();
      expect(find.text('abc 已清空标题'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
