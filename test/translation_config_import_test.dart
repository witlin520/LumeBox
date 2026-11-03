import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/comic_image_tools.dart';
import 'package:lume_box/features/comic/comic_image_tools_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'one connection file fills settings and stores its secret only in the native key store',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('translation-import');
      addTearDown(() => root.deleteSync(recursive: true));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => root.path,
      );
      String? savedKey;
      messenger.setMockMethodCallHandler(ComicImageTools.channel, (call) async {
        if (call.method == 'setKey') {
          savedKey = (call.arguments as Map)['key'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(ComicImageTools.channel, null),
      );
      final config = utf8.encode(
        jsonEncode({
          'format': 'lumebox.translation-connection',
          'version': 1,
          'endpoint': 'https://translation.test/v1/chat/completions',
          'model': 'lumebox-translation',
          'apiKey': 'private-example-key',
          'target': 'zh-Hans',
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ComicImageToolsSettingsPage(
            translation: true,
            pickTranslationConfig: () async =>
                XFile.fromData(config, name: 'connection.json'),
          ),
        ),
      );
      await tester.tap(find.text('导入翻译配置文件'));
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(savedKey, 'private-example-key');
      final settings = ComicImageToolsSettings.instance;
      expect(settings.ai, isTrue);
      expect(settings.serverTranslation, isFalse);
      expect(settings.endpoint, 'https://translation.test/v1/chat/completions');
      expect(
        File('${root.path}/${ComicImageToolsSettings.fileName}')
            .readAsStringSync(),
        isNot(contains('private-example-key')),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
