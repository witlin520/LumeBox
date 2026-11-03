import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/comic_image_tools_settings.dart';
import 'package:lume_box/core/translation/text_translation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'legacy unchanged cache entries cannot suppress a fresh translation',
    () async {
      final root = await Directory.systemTemp.createTemp('legacy-noop-cache');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/cache.json');
      final key = sha256
          .convert(
            utf8.encode(jsonEncode([1, 'auto', 'zh-Hans', 'Foreign title'])),
          )
          .toString();
      await file.writeAsString(jsonEncode({key: 'Foreign title'}));
      final service = TextTranslationService(
        file: file,
        translator: (_) async => ['外文标题'],
      );
      addTearDown(service.dispose);
      await service.boot();
      expect(service.lookup('Foreign title'), isNull);
      expect(await service.translate(['Foreign title']), ['外文标题']);
      await service.flush();
    },
  );
  test(
    'Chinese fallback retries unchanged foreign titles but preserves Chinese',
    () async {
      final result = await translateWithPolicy(
        ['Hello world', '中文标题', 'こんにちは'],
        mode: TextTranslationMode.fallback,
        native: (texts) async => texts,
        ai: (texts) async {
          expect(texts, ['Hello world', 'こんにちは']);
          return ['你好世界', '你好'];
        },
      );
      expect(result, ['你好世界', '中文标题', '你好']);
      expect(unresolvedTranslation('Hello', 'Hello', 'en'), isFalse);
      expect(unresolvedTranslation('中文', '中文', 'zh-Hans'), isFalse);
      expect(unresolvedTranslation('Hello', 'Hello', 'zh-Hans'), isTrue);
    },
  );

  test(
    'unchanged foreign results are retryable rather than cached successes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'unchanged-translation',
      );
      addTearDown(() => root.delete(recursive: true));
      var calls = 0;
      final service = TextTranslationService(
        file: File('${root.path}/cache.json'),
        translator: (texts) async {
          calls++;
          return calls == 1 ? texts : ['你好世界'];
        },
      );
      addTearDown(service.dispose);
      await expectLater(
        service.translate(['Hello world']),
        throwsA(isA<PlatformException>()),
      );
      expect(service.lookup('Hello world'), isNull);
      expect(await service.translate(['Hello world']), ['你好世界']);
      expect(calls, 2);
      await service.flush();
    },
  );
  test('全局AI模式由标题翻译使用，与系统模式缓存隔离且可跨启动复用', () async {
    final root = await Directory.systemTemp.createTemp('global-translation');
    addTearDown(() => root.delete(recursive: true));
    final settings = ComicImageToolsSettings()
      ..translationMode = TextTranslationMode.ai;
    var nativeCalls = 0, aiCalls = 0;
    final file = File('${root.path}/cache.json');
    final service = TextTranslationService(
      file: file,
      settings: settings,
      useGlobalSettings: true,
      translator: (texts) async {
        nativeCalls++;
        return ['系统译文'];
      },
      aiTranslator: (texts) async {
        aiCalls++;
        return ['AI译文'];
      },
    );
    addTearDown(service.dispose);
    expect(await service.translate(['Hello']), ['AI译文']);
    expect(nativeCalls, 0);
    settings.translationMode = TextTranslationMode.system;
    expect(service.lookup('Hello'), isNull);
    expect(await service.translate(['Hello']), ['系统译文']);
    settings.translationMode = TextTranslationMode.ai;
    expect(await service.translate(['Hello']), ['AI译文']);
    expect(aiCalls, 1);
    await service.flush();
    final restarted = TextTranslationService(
      file: file,
      settings: settings,
      useGlobalSettings: true,
      aiTranslator: (_) async => throw StateError('不应重复请求'),
    );
    addTearDown(restarted.dispose);
    expect(await restarted.translate(['Hello']), ['AI译文']);
    settings.target = 'ja';
    expect(restarted.lookup('Hello'), isNull);
  });

  test('请求期间更换AI配置不会把旧配置译文写入新配置缓存', () async {
    final root = await Directory.systemTemp.createTemp('translation-profile');
    addTearDown(() => root.delete(recursive: true));
    final settings = ComicImageToolsSettings()
      ..translationMode = TextTranslationMode.ai
      ..endpoint = 'https://a.test/v1/chat/completions';
    final started = Completer<void>(), response = Completer<List<String>>();
    final service = TextTranslationService(
      file: File('${root.path}/cache.json'),
      useGlobalSettings: true,
      settings: settings,
      aiTranslator: (_) {
        started.complete();
        return response.future;
      },
    );
    addTearDown(service.dispose);
    final pending = service.translate(['Hello']);
    await started.future;
    settings.endpoint = 'https://b.test/v1/chat/completions';
    response.complete(['旧配置译文']);
    expect(await pending, ['旧配置译文']);
    expect(service.lookup('Hello'), isNull);
    settings.endpoint = 'https://a.test/v1/chat/completions';
    expect(service.lookup('Hello'), '旧配置译文');
    await service.flush();
  });

  test('补译只发送系统失败条目，保留成功顺序和内容', () async {
    final result = await translateWithPolicy(
      ['Hello', 'Bonjour', 'World'],
      mode: TextTranslationMode.fallback,
      native: (_) async => throw PlatformException(
        code: 'translation_partial',
        details: ['你好', '', '世界'],
      ),
      ai: (texts) async {
        expect(texts, ['Bonjour']);
        return ['您好'];
      },
    );
    expect(result, ['你好', '您好', '世界']);
  });

  test('AI partial fallback retains both native and AI successes', () async {
    await expectLater(
      translateWithPolicy(
        ['Hello', 'World', 'Title'],
        mode: TextTranslationMode.fallback,
        native: (_) async => throw PlatformException(
          code: 'translation_partial',
          details: ['你好', '', ''],
        ),
        ai: (_) async => throw PlatformException(
          code: 'translation_partial',
          details: ['世界', ''],
        ),
      ),
      throwsA(
        isA<PlatformException>().having((e) => e.details, 'retained', [
          '你好',
          '世界',
          '',
        ]),
      ),
    );
  });

  test('系统不可用时整批交AI，系统全部成功时不联网', () async {
    expect(
      await translateWithPolicy(
        ['Hi'],
        mode: TextTranslationMode.fallback,
        native: (_) async => throw MissingPluginException(),
        ai: (_) async => ['你好'],
      ),
      ['你好'],
    );
    expect(
      await translateWithPolicy(
        ['Hi'],
        mode: TextTranslationMode.fallback,
        native: (_) async => ['你好'],
        ai: (_) async => throw StateError('不应联网'),
      ),
      ['你好'],
    );
  });

  test('AI补译失败保留系统成功条目，用户取消不会触发AI', () async {
    await expectLater(
      translateWithPolicy(
        ['Hello', 'Bonjour'],
        mode: TextTranslationMode.fallback,
        native: (_) async => throw PlatformException(
          code: 'translation_partial',
          details: ['你好', ''],
        ),
        ai: (_) async => throw const FormatException('未填写Key'),
      ),
      throwsA(
        isA<PlatformException>().having((e) => e.details, '保留译文', ['你好', '']),
      ),
    );
    await expectLater(
      translateWithPolicy(
        ['Hello'],
        mode: TextTranslationMode.fallback,
        native: (_) async => throw PlatformException(code: 'cancelled'),
        ai: (_) async => throw StateError('不应联网'),
      ),
      throwsA(isA<PlatformException>()),
    );
  });

  test('补译策略持久化且旧AI配置不丢失', () async {
    final root = await Directory.systemTemp.createTemp('global-policy');
    addTearDown(() => root.delete(recursive: true));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      ),
    );
    await File('${root.path}/${ComicImageToolsSettings.fileName}')
        .writeAsString(
          jsonEncode({
            'ai': true,
            'endpoint': 'https://fixture.test/v1/chat/completions',
            'model': 'existing-model',
            'target': 'ja',
          }),
        );
    final settings = ComicImageToolsSettings();
    await settings.boot();
    expect(settings.translationMode, TextTranslationMode.ai);
    settings.translationMode = TextTranslationMode.fallback;
    await settings.save();
    final restored = ComicImageToolsSettings();
    await restored.boot();
    expect(restored.translationMode, TextTranslationMode.fallback);
    expect(restored.endpoint, settings.endpoint);
    expect(restored.model, 'existing-model');
    expect(restored.target, 'ja');
  });
}
