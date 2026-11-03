import 'package:lume_box/core/js/source_script_storage.dart';

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/cache/section_memory_cache.dart';
import 'package:lume_box/core/net/waf.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/source/source_preferences.dart';
import 'package:lume_box/core/source/source_subscription_sync.dart';
import 'package:lume_box/features/source/source_maintenance.dart';

import 'support/fake_source_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('station-cleanup');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
  });
  tearDown(() async {
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    WafSessions.resetForTesting();
    SectionMemoryCache.instance.clearAll();
    await SectionScope.closeAll();
    root.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });
  test('移除全部站点数据按版块隔离，保留书架、进度、界面设置和导出图片', () async {
    final novel = await ReadingLibrary.open(Section.video);
    final comic = await ReadingLibrary.open(Section.comic);
    novel.shelve(sourceId: 'a', itemId: 'book', title: '保留作品', chapterCount: 3);
    novel.saveProgress(
      VideoProgress(
        section: Section.video,
        itemId: 'book',
        chapterIndex: 1,
        chapterId: 'ch2',
        chapterTitle: '第二章',
        updatedAt: DateTime(2026),
        position: const Duration(milliseconds: 40),
      ),
    );
    await const SourcePreferences(
      pinned: true,
      customOrigin: 'https://mirror.example',
    ).save(Section.video, 'a');
    await const SourcePreferences(pinned: true).save(Section.comic, 'a');
    novel.setSetting('source.runtime.storage.old-orphan', '{}');
    comic.setSetting('source.runtime.storage.other', 'keep');
    novel.setSetting('source.preferences.old-orphan', '{}');
    novel.setSetting('player.unrelated', 'keep');
    WafSessions.save(Section.video, 'a', {'cf_clearance': 'test'});
    WafSessions.saveUserAgent(Section.video, 'a', 'test-UA');
    WafSessions.save(Section.comic, 'a', {'cf_clearance': 'other'});
    final cached = File('${novel.imageCacheDir}/test.img')
      ..writeAsStringSync('cache');
    final other = File('${comic.imageCacheDir}/test.img')
      ..writeAsStringSync('keep');
    final saved = novel.saveImage('saved.png', Uint8List.fromList([1, 2, 3]));
    SectionMemoryCache.instance.write(Section.video, 'a', 'test', 'cached');
    SectionMemoryCache.instance.write(Section.comic, 'a', 'test', 'keep');
    final manager = FakeSourceManager(
      sources: const [
        SourceDescriptor(
          id: 'a',
          name: '站点甲',
          version: '1',
          enabled: true,
          siteUrl: 'https://novel.example',
        ),
      ],
    );
    final scope = await SectionScope.open(Section.video);
    final subscriptions = SourceSubscriptionSync(
      section: Section.video,
      manager: manager,
      file: File(scope.resolve('subscriptions.json')),
    );
    await subscriptions.register(['https://example.com/novels']);
    final domains = <String>{};
    final result = await SourceMaintenance(
      section: Section.video,
      manager: manager,
      subscriptions: subscriptions,
      clearWebData: (hosts, protected) async {
        domains.addAll(hosts);
      },
    ).remove(List.of(manager.sources), clearData: true);
    expect(result.errors, isEmpty);
    expect(manager.sources, isEmpty);
    expect(subscriptions.subscriptions, isEmpty);
    expect(novel.onShelf('book'), true);
    expect(
      (novel.progress('book') as VideoProgress).position.inMilliseconds,
      40,
    );
    expect(novel.setting('player.unrelated'), 'keep');
    expect(novel.setting('source.runtime.storage.old-orphan'), isNull);
    expect(comic.setting('source.runtime.storage.other'), 'keep');
    expect(novel.setting('source.preferences.old-orphan'), isNull);
    expect(SourcePreferences.read(Section.video, 'a').pinned, false);
    expect(WafSessions.cookiesFor(Section.video, 'a'), isNull);
    expect(WafSessions.userAgentFor(Section.video, 'a'), isNull);
    expect(SourcePreferences.read(Section.comic, 'a').pinned, true);
    expect(WafSessions.cookiesFor(Section.comic, 'a'), contains('other'));
    expect(cached.existsSync(), false);
    expect(other.existsSync(), true);
    expect(saved.existsSync(), true);
    expect(SectionMemoryCache.instance.usageOf(Section.video).isEmpty, true);
    expect(SectionMemoryCache.instance.usageOf(Section.comic).isEmpty, false);
    expect(domains, containsAll(['novel.example', 'mirror.example']));
  });
  test('部分源清理失败时只删除成功来源的持久脚本数据', () async {
    final a = SourceScriptStorage(Section.video, 'a');
    final b = SourceScriptStorage(Section.video, 'b');
    await a.invoke({'operation': 'set', 'key': 'state', 'value': 'A'});
    await b.invoke({'operation': 'set', 'key': 'state', 'value': 'B'});
    final manager = _FailingManager(
      sources: const [
        SourceDescriptor(id: 'a', name: 'A', version: '1', enabled: true),
        SourceDescriptor(id: 'b', name: 'B', version: '1', enabled: true),
      ],
    );
    final result = await SourceMaintenance(
      section: Section.video,
      manager: manager,
    ).remove(List.of(manager.sources), clearData: true);
    expect(result.errors, isNotEmpty);
    expect(await a.invoke({'operation': 'get', 'key': 'state'}), isNull);
    expect(await b.invoke({'operation': 'get', 'key': 'state'}), 'B');
  });

  test('普通卸载保留源设置，部分失败逐项报告', () async {
    await ReadingLibrary.open(Section.video);
    await const SourcePreferences(pinned: true).save(Section.video, 'a');
    final manager = _FailingManager(
      sources: const [
        SourceDescriptor(id: 'a', name: '甲站', version: '1', enabled: true),
        SourceDescriptor(id: 'b', name: '乙站', version: '1', enabled: true),
      ],
    );
    final result = await SourceMaintenance(
      section: Section.video,
      manager: manager,
    ).remove(List.of(manager.sources));
    expect(result.removed.map((source) => source.id), ['a']);
    expect(result.errors.single, contains('乙站'));
    expect(manager.sources.single.id, 'b');
    expect(SourcePreferences.read(Section.video, 'a').pinned, true);
  });
}

class _FailingManager extends FakeSourceManager {
  _FailingManager({required super.sources});
  @override
  Future<void> remove(String id) async {
    if (id == 'b') throw StateError('test failure');
    await super.remove(id);
  }
}
