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

  testWidgets('长按实时翻译新加载文字，关闭后停止请求', (tester) async {
    var calls = 0;
    messenger.setMockMethodCallHandler(TextTranslationService.channel, (
      call,
    ) async {
      calls++;
      return [for (final text in (call.arguments as Map)['texts']) '译$text'];
    });
    Widget app(List<String> texts) => MaterialApp(
      home: Scaffold(body: SourceTranslationAction(texts: texts)),
    );
    await tester.pumpWidget(app(['Live first']));
    await tester.longPress(find.byIcon(Icons.translate));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.pumpWidget(app(['Live first', 'Live next']));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(calls, 2);
    await tester.longPress(find.byIcon(Icons.auto_awesome));
    await tester.pumpWidget(app(['Live disabled']));
    await tester.pump(const Duration(milliseconds: 700));
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
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
