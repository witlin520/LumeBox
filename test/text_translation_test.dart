import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/translation/text_translation.dart';
import 'package:lume_box/core/source/source_labels.dart';
import 'package:lume_box/core/source/source_models.dart';

void main() {
  test('某语种失败仍保存其它译文，重试只处理失败项并跨启动复用', () async {
    final dir = await Directory.systemTemp.createTemp(
      'lume-partial-translations',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/cache.json');
    var retry = false;
    final service = TextTranslationService(
      file: file,
      translator: (texts) async {
        if (!retry) {
          throw PlatformException(
            code: 'translation_partial',
            message: '某语种不支持',
            details: ['你好', '', '世界'],
          );
        }
        expect(texts, ['short-title']);
        return ['短标题'];
      },
    );
    final original = ['Hello', 'short-title', 'World'];
    await expectLater(
      service.translate(original),
      throwsA(isA<PlatformException>()),
    );
    expect(service.lookup('Hello'), '你好');
    expect(service.lookup('World'), '世界');
    expect(service.lookup('short-title'), isNull);
    retry = true;
    expect(await service.translate(original), ['你好', '短标题', '世界']);
    await service.flush();
    final restarted = TextTranslationService(
      file: file,
      translator: (_) async => throw StateError('不应重复翻译'),
    );
    expect(await restarted.translate(original), ['你好', '短标题', '世界']);
    await restarted.flush();
  });
  test('译文跨启动缓存，按原文、源语言和目标语言隔离', () async {
    final dir = await Directory.systemTemp.createTemp('lume-translations');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/cache.json');
    var calls = 0;
    final first = TextTranslationService(
      file: file,
      translator: (texts) async {
        calls++;
        return texts.map((t) => '译$t').toList();
      },
    );
    expect(await first.translate(['Title', 'Title', 'Summary']), [
      '译Title',
      '译Title',
      '译Summary',
    ]);
    expect(calls, 1);
    await first.flush();
    final second = TextTranslationService(
      file: file,
      translator: (_) async => throw StateError('unexpected'),
    );
    expect(await second.translate(['Title']), ['译Title']);
    expect(second.lookup('Title', target: 'ja'), isNull);
    expect(second.lookup('Title', source: 'en'), isNull);
    expect(second.lookup('Title changed'), isNull);
  });

  test('并发调用串行并去重，不同时弹两个系统翻译窗口', () async {
    final dir = await Directory.systemTemp.createTemp('lume-queue');
    addTearDown(() => dir.delete(recursive: true));
    var active = 0, maximum = 0;
    final batches = <List<String>>[];
    final service = TextTranslationService(
      file: File('${dir.path}/cache.json'),
      translator: (texts) async {
        active++;
        if (active > maximum) maximum = active;
        batches.add(texts);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
        return texts.map((t) => '译$t').toList();
      },
    );
    final results = await Future.wait([
      service.translate(['A', 'B']),
      service.translate(['B', 'C']),
    ]);
    expect(results, [
      ['译A', '译B'],
      ['译B', '译C'],
    ]);
    expect(batches, [
      ['A', 'B'],
      ['C'],
    ]);
    expect(maximum, 1);
    await service.flush();
  });

  test('失败与不完整结果不缓存，下次可重试', () async {
    final dir = await Directory.systemTemp.createTemp('lume-retry');
    addTearDown(() => dir.delete(recursive: true));
    var failed = true;
    final service = TextTranslationService(
      file: File('${dir.path}/cache.json'),
      translator: (texts) async => failed ? [] : ['正确译文'],
    );
    await expectLater(service.translate(['Title']), throwsFormatException);
    expect(service.lookup('Title'), isNull);
    failed = false;
    expect(await service.translate(['Title']), ['正确译文']);
    await service.flush();
  });

  test('损坏缓存不阻止翻译，空白文本不发送', () async {
    final dir = await Directory.systemTemp.createTemp('lume-invalid-cache');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/cache.json');
    await file.writeAsString('{invalid');
    final service = TextTranslationService(
      file: file,
      translator: (texts) async {
        expect(texts, ['Hello']);
        return ['你好'];
      },
    );
    expect(await service.translate(['', 'Hello']), ['', '你好']);
    await service.flush();
    await expectLater(service.translate(['a' * 40001]), throwsFormatException);
  });

  test('分类只改变显示文案，未知名称与请求 ID 原样保留', () {
    final category = SourceCategory.parse({
      'id': '/categories/recent?sort=1',
      'title': 'Most Viewed',
    })!;
    expect(sourceLabel(category.title), '最多观看');
    expect(category.id, '/categories/recent?sort=1');
    expect(category.title, 'Most Viewed');
    expect(sourceLabel('unknown-tag'), 'unknown-tag');
    expect(sourceLabel('Sci-Fi'), '科幻');
    expect(sourceLabel('原有中文'), '原有中文');
  });
  test('清理缓存后在途翻译不能把旧译文写回来', () async {
    final dir = await Directory.systemTemp.createTemp('lume-clear');
    addTearDown(() => dir.delete(recursive: true));
    final started = Completer<void>();
    final pending = Completer<List<String>>();
    final service = TextTranslationService(
      file: File('${dir.path}/cache.json'),
      translator: (_) {
        started.complete();
        return pending.future;
      },
    );
    final translation = service.translate(['Private title']);
    final assertion = expectLater(translation, throwsStateError);
    await started.future;
    await service.clear();
    pending.complete(['旧译文']);
    await assertion;
    expect(service.lookup('Private title'), isNull);
    expect(await File('${dir.path}/cache.json').readAsString(), '{}');
  });
}
