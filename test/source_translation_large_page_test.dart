import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/translation/text_translation.dart';
import 'package:lume_box/shared/widgets/source_translation.dart';

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

  testWidgets('122 条页面继续处理第二批，没有100条总量上限', (tester) async {
    final batches = <List<String>>[];
    messenger.setMockMethodCallHandler(TextTranslationService.channel, (
      call,
    ) async {
      final texts = ((call.arguments as Map)['texts'] as List).cast<String>();
      batches.add(texts);
      return texts.map((text) => '译$text').toList();
    });
    final texts = List.generate(122, (i) => 'large-page-title-$i');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SourceText(texts.first),
              SourceText(texts.last),
              SourceTranslationAction(texts: texts),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('翻译成中文'));
    for (
      var i = 0;
      i < 50 &&
          find
              .byKey(const ValueKey('source-translation-result'))
              .evaluate()
              .isEmpty;
      i++
    ) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
    expect(batches.map((batch) => batch.length), [100, 22]);
    expect(find.text('已翻译 122 条，未完成 0 条'), findsOneWidget);
    expect(find.text('译large-page-title-121'), findsOneWidget);
    var flushed = false;
    TextTranslationService.shared.flush().then((_) => flushed = true);
    for (var i = 0; i < 50 && !flushed; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(flushed, isTrue);
  });
}
