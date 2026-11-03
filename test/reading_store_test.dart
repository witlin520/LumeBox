import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/features/comic/comic_settings.dart';

/// 阅读底座的验证：板块独占的库与缓存、归属校验、书架与两套进度口径。
///
/// 全部在 Windows 上跑真实 sqlite 与真实文件：path_provider 用方法通道打桩，
/// 因此「漫画的数据不会出现在小说库里」这类隔离断言是对着真实库文件断言的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lume_box_reading');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? root.path
              : null,
        );
  });

  tearDown(() async {
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await SectionScope.closeAll();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('视频逐集保存、升级回填最近一集，清除历史同时清除逐集记录', () async {
    var library = await ReadingLibrary.open(Section.video);
    VideoProgress progress(String chapter, int index, int position) =>
        VideoProgress(
          section: Section.video,
          itemId: 'movie',
          chapterIndex: index,
          chapterId: chapter,
          chapterTitle: '第${index + 1}集',
          updatedAt: DateTime.now(),
          position: Duration(seconds: position),
          duration: const Duration(seconds: 100),
        );
    library.saveProgress(progress('a1', 0, 98));
    library.saveProgress(progress('a2', 1, 35));
    expect(library.videoProgress('movie')!.chapterId, 'a2');
    expect(library.videoEpisodeProgress('movie', 'a1')!.isFinished, true);
    expect(library.videoEpisodeProgresses('movie').length, 2);
    ReadingLibrary.close(Section.video);
    library = await ReadingLibrary.open(Section.video);
    expect(library.videoEpisodeProgress('movie', 'a2')!.position.inSeconds, 35);
    final scope = await SectionScope.open(Section.video);
    ReadingLibrary.close(Section.video);
    final db = sqlite3.open(scope.resolve('reading.db'));
    db.execute('DROP TABLE video_episode_progress');
    db.execute('PRAGMA user_version = 3');
    db.close();
    library = await ReadingLibrary.open(Section.video);
    expect(library.videoEpisodeProgresses('movie').keys, ['a2']);
    library.removeHistory('movie');
    expect(library.videoEpisodeProgresses('movie'), isEmpty);
    library.setSetting('history.incognito', 'true');
    library.saveProgress(progress('a3', 2, 20));
    expect(library.videoEpisodeProgresses('movie'), isEmpty);
  });

  test('并发打开同一板块共用句柄，关闭后可重新打开', () async {
    final libraries = await Future.wait(
      List.generate(8, (_) => ReadingLibrary.open(Section.video)),
    );
    expect(
      libraries.every((library) => identical(library, libraries.first)),
      isTrue,
    );
    final stores = await Future.wait(
      List.generate(8, (_) => ReadingStore.open(Section.video)),
    );
    expect(stores.every((store) => identical(store, stores.first)), isTrue);
    ReadingLibrary.close(Section.video);
    expect(stores.first.isClosed, isTrue);
    final reopened = await ReadingLibrary.open(Section.video);
    expect(identical(reopened, libraries.first), isFalse);
  });

  test('版本二收藏迁移保留条目，移出收藏后历史在重开后仍可读取', () async {
    var library = await ReadingLibrary.open(Section.video);
    library.shelve(sourceId: 'demo', itemId: 'legacy', title: '原收藏');
    library.saveProgress(
      VideoProgress(
        section: Section.video,
        itemId: 'legacy',
        chapterIndex: 0,
        chapterId: 'ep',
        chapterTitle: '第1集',
        updatedAt: DateTime.now(),
        position: const Duration(seconds: 60),
      ),
    );
    final scope = await SectionScope.open(Section.video);
    ReadingLibrary.close(Section.video);
    final database = sqlite3.open(scope.resolve('reading.db'));
    database.execute('ALTER TABLE library_item DROP COLUMN favorite');
    database.execute('PRAGMA user_version=2');
    database.close();
    library = await ReadingLibrary.open(Section.video);
    expect(library.onShelf('legacy'), isTrue);
    expect(library.videoProgress('legacy')?.position.inSeconds, 60);
    library.removeFavorite('legacy');
    ReadingLibrary.close(Section.video);
    library = await ReadingLibrary.open(Section.video);
    expect(library.shelf(), isEmpty);
    expect(library.onShelf('legacy'), isFalse);
    expect(library.continueReading().single.item.title, '原收藏');
    library.removeHistory('legacy');
    expect(library.continueReading(), isEmpty);
    expect(library.videoProgress('legacy'), isNull);
  });

  test('版本一阅读库迁移保留原有视频进度', () async {
    final library = await ReadingLibrary.open(Section.video);
    library.saveProgress(
      VideoProgress(
        section: Section.video,
        itemId: 'legacy',
        chapterIndex: 0,
        chapterId: 'old',
        chapterTitle: '旧集',
        updatedAt: DateTime.now(),
        position: const Duration(seconds: 60),
      ),
    );
    final scope = await SectionScope.open(Section.video);
    ReadingLibrary.close(Section.video);
    final database = sqlite3.open(scope.resolve('reading.db'));
    database.execute('ALTER TABLE reading_progress DROP COLUMN progress_kind');
    database.execute('PRAGMA user_version=1');
    database.close();
    final restored = await ReadingLibrary.open(Section.video);
    expect(
      restored.videoProgress('legacy')?.position,
      const Duration(seconds: 60),
    );
  });
  test('猫源按内容类型保存进度，重开后视频漫画小说均可续读', () async {
    final library = await ReadingLibrary.open(Section.cat);
    final now = DateTime.now();
    library.saveProgress(
      VideoProgress(
        section: Section.cat,
        itemId: 'video',
        chapterIndex: 1,
        chapterId: 'line-a-2',
        chapterTitle: '第二集',
        updatedAt: now,
        position: const Duration(seconds: 90),
        duration: const Duration(minutes: 40),
      ),
    );
    library.saveProgress(
      ComicProgress(
        section: Section.cat,
        itemId: 'comic',
        chapterIndex: 2,
        chapterId: 'chapter3',
        chapterTitle: '第三话',
        updatedAt: now,
        page: 7,
        pageFraction: .25,
      ),
    );
    library.saveProgress(
      VideoProgress(
        section: Section.cat,
        itemId: 'novel',
        chapterIndex: 3,
        chapterId: 'chapter4',
        chapterTitle: '第四章',
        updatedAt: now,
        position: const Duration(milliseconds: 600),
        duration: const Duration(milliseconds: 3000),
      ),
    );
    ReadingLibrary.close(Section.cat);
    final restored = await ReadingLibrary.open(Section.cat);
    expect(
      restored.videoProgress('video')?.position,
      const Duration(seconds: 90),
    );
    expect(restored.progress('comic'), isA<ComicProgress>());
    expect(
      (restored.progress('novel') as VideoProgress).position.inMilliseconds,
      600,
    );
    expect(restored.progress('video')?.section, Section.cat);
  });

  ComicProgress comicProgress({
    String itemId = 'book',
    int chapterIndex = 2,
    int page = 5,
    double fraction = 0.4,
  }) => ComicProgress(
    section: Section.comic,
    itemId: itemId,
    chapterIndex: chapterIndex,
    chapterId: 'c$chapterIndex',
    chapterTitle: '第 ${chapterIndex + 1} 章',
    updatedAt: DateTime.now(),
    page: page,
    pageFraction: fraction,
  );

  VideoProgress videoProgress({
    String itemId = 'book',
    int chapterIndex = 2,
    Duration position = const Duration(milliseconds: 1200),
    Duration duration = const Duration(milliseconds: 4800),
  }) => VideoProgress(
    section: Section.video,
    itemId: itemId,
    chapterIndex: chapterIndex,
    chapterId: 'c$chapterIndex',
    chapterTitle: '第 ${chapterIndex + 1} 章',
    updatedAt: DateTime.now(),
    position: position,
    duration: duration,
  );

  group('板块隔离', () {
    test('阅读库与图源库分文件，且落在本板块目录下', () async {
      final library = await ReadingLibrary.open(Section.comic);
      final comicDir = Directory('${root.path}/sections/comic');

      expect(comicDir.existsSync(), isTrue);
      expect(File('${comicDir.path}/reading.db').existsSync(), isTrue);
      // 图源库是另一个文件，阅读数据不写进图源库。
      expect(File('${comicDir.path}/comic.db').existsSync(), isFalse);
      // 缓存目录独立且已建好。
      expect(Directory(library.imageCacheDir).existsSync(), isTrue);
      expect(Directory(library.exportDir).existsSync(), isTrue);
      expect(library.imageCacheDir, contains('sections'));
      expect(library.imageCacheDir, contains('reading_cache'));
    });

    test('漫画与小说各存各的：同一个 itemId 互不影响', () async {
      final comic = await ReadingLibrary.open(Section.comic);
      final novel = await ReadingLibrary.open(Section.video);

      comic.shelve(
        sourceId: 'comic-src',
        itemId: 'shared-id',
        title: '漫画书',
        chapterCount: 10,
      );
      novel.shelve(
        sourceId: 'novel-src',
        itemId: 'shared-id',
        title: '小说书',
        chapterCount: 20,
      );
      comic.saveProgress(comicProgress(itemId: 'shared-id', page: 7));
      novel.saveProgress(
        videoProgress(
          itemId: 'shared-id',
          position: const Duration(milliseconds: 900),
        ),
      );

      expect(comic.shelf().single.title, '漫画书');
      expect(novel.shelf().single.title, '小说书');
      expect(comic.comicProgress('shared-id')!.page, 7);
      expect(novel.videoProgress('shared-id')!.position.inMilliseconds, 900);
      // 形状不对的进度不会被当成本板块的进度。
      expect(novel.comicProgress('shared-id'), isNull);
      expect(comic.videoProgress('shared-id'), isNull);
      // 缓存目录也不交叉。
      expect(comic.imageCacheDir, isNot(novel.imageCacheDir));
    });

    test('库内自证归属：标记不符时拒绝打开', () async {
      final scope = await SectionScope.open(Section.video);
      final path = '${scope.root.path}/reading.db';
      final raw = sqlite3.open(path);
      raw.execute(
        'CREATE TABLE IF NOT EXISTS reading_setting (key TEXT PRIMARY KEY, '
        'value TEXT NOT NULL)',
      );
      raw.execute(
        "INSERT INTO reading_setting (key, value) VALUES ('owner_section', ?)",
        <Object?>[Section.comic.id],
      );
      raw.close();

      await expectLater(
        ReadingStore.open(Section.video),
        throwsA(isA<StateError>()),
      );
    });

    test('跨板块写入书架与进度都被拒绝', () async {
      final library = await ReadingLibrary.open(Section.video);

      // 进度带归属标记，跨板块直接抛错。
      expect(
        () => library.saveProgress(
          ComicProgress(
            section: Section.comic,
            itemId: 'x',
            chapterIndex: 0,
            chapterId: 'c',
            chapterTitle: 'c',
            updatedAt: DateTime.now(),
            page: 0,
          ),
        ),
        throwsArgumentError,
      );
      expect(library.shelf(), isEmpty);
      expect(library.progress('x'), isNull);
    });
  });

  group('书架与进度', () {
    test('入架、补全信息、移出', () async {
      final library = await ReadingLibrary.open(Section.comic);

      final shelved = library.shelve(
        sourceId: 'src',
        itemId: 'a',
        title: '甲',
        cover: 'https://example.invalid/a.jpg',
        chapterCount: 5,
      );
      expect(shelved.chapterCount, 5);
      expect(shelved.readChapterIndex, -1);
      expect(library.onShelf('a'), isTrue);

      // 再次入架只补信息，不重置阅读记录。
      library.saveProgress(comicProgress(itemId: 'a', chapterIndex: 3));
      final again = library.shelve(
        sourceId: 'src',
        itemId: 'a',
        title: '甲（新）',
        chapterCount: 8,
      );
      expect(again.title, '甲（新）');
      expect(again.chapterCount, 8);
      expect(again.readChapterIndex, 3);

      library.unshelve('a');
      expect(library.onShelf('a'), isFalse);
      expect(library.progress('a'), isNull, reason: '移出书架会连进度一起清掉');
    });
    test('未读角标口径：章节总数 - 已读章节 - 1，未知章节数时不显示', () async {
      final library = await ReadingLibrary.open(Section.comic);

      final unknown = library.shelve(
        sourceId: 'src',
        itemId: 'unknown',
        title: '还没同步章节',
      );
      expect(unknown.unreadChapters, 0, reason: '章节总数未知时不猜数字');

      final fresh = library.shelve(
        sourceId: 'src',
        itemId: 'fresh',
        title: '从未读',
        chapterCount: 12,
      );
      expect(fresh.unreadChapters, 12);

      library.shelve(
        sourceId: 'src',
        itemId: 'reading',
        title: '读到一半',
        chapterCount: 12,
      );
      library.saveProgress(comicProgress(itemId: 'reading', chapterIndex: 4));
      expect(library.item('reading')!.unreadChapters, 7);

      library.shelve(
        sourceId: 'src',
        itemId: 'done',
        title: '读完',
        chapterCount: 12,
      );
      library.saveProgress(comicProgress(itemId: 'done', chapterIndex: 11));
      expect(library.item('done')!.unreadChapters, 0);

      // 回翻旧章节不会让未读重新涨起来（只记「最远读到」）。
      library.saveProgress(comicProgress(itemId: 'done', chapterIndex: 2));
      expect(library.item('done')!.readChapterIndex, 11);
      expect(library.item('done')!.unreadChapters, 0);
    });

    test('书架按最近阅读排序', () async {
      final library = await ReadingLibrary.open(Section.video);
      library.shelve(
        sourceId: 'src',
        itemId: 'first',
        title: '先入架',
        chapterCount: 3,
      );
      // 排序键是毫秒时间戳，两次入架之间留一毫秒，断言才确定。
      await Future<void>.delayed(const Duration(milliseconds: 5));
      library.shelve(
        sourceId: 'src',
        itemId: 'second',
        title: '后入架',
        chapterCount: 3,
      );
      expect(library.shelf().first.itemId, 'second');

      library.saveProgress(
        VideoProgress(
          section: Section.video,
          itemId: 'first',
          chapterIndex: 1,
          chapterId: 'c1',
          chapterTitle: '第 2 章',
          updatedAt: DateTime.now().add(const Duration(seconds: 1)),
          position: const Duration(milliseconds: 100),
          duration: const Duration(milliseconds: 1000),
        ),
      );
      expect(library.shelf().first.itemId, 'first', reason: '刚读过的排最前');
    });

    test('章节同步：非零值才覆盖，避免图源少返章节把角标算错', () async {
      final library = await ReadingLibrary.open(Section.comic);
      library.shelve(
        sourceId: 'src',
        itemId: 'a',
        title: '甲',
        chapterCount: 20,
      );

      library.syncChapters('a', 24);
      expect(library.item('a')!.chapterCount, 24);
      library.syncChapters('a', 0);
      expect(library.item('a')!.chapterCount, 24, reason: '0 视为未知，不覆盖');
    });

    test('小说进度记录字符偏移，比例由章节长度算出', () async {
      final library = await ReadingLibrary.open(Section.video);
      library.shelve(
        sourceId: 'src',
        itemId: 'n',
        title: '小说',
        chapterCount: 10,
      );
      final saved = videoProgress(
        itemId: 'n',
        position: const Duration(milliseconds: 600),
        duration: const Duration(milliseconds: 2400),
      );
      library.saveProgress(saved);

      final loaded = library.videoProgress('n')!;
      expect(loaded.position.inMilliseconds, 600);
      expect(loaded.duration.inMilliseconds, 2400);
      expect(loaded.ratio, closeTo(0.25, 0.0001));
      expect(loaded.chapterTitle, '第 3 章');
    });
  });

  group('历史与收藏严格隔离', () {
    test('只看详情只写历史：不进收藏，history 可见，收藏查询为空', () async {
      final library = await ReadingLibrary.open(Section.video);
      library.recordHistoryItem(
        sourceId: 'src',
        itemId: 'viewed',
        title: '只看过详情',
        chapterCount: 3,
      );

      expect(library.onShelf('viewed'), isFalse);
      expect(library.favorites(), isEmpty, reason: '收藏页不能出现历史行');
      expect(library.shelf(), isEmpty);
      expect(library.history().map((item) => item.itemId), <String>[
        'viewed',
      ], reason: '看过详情也要出现在历史里');
      expect(library.continueReading(), isEmpty, reason: '没有进度不算续读');
      expect(library.item('viewed')!.chapterCount, 3);
    });

    test('显式收藏后记历史保留收藏；收藏但没读不进历史', () async {
      final library = await ReadingLibrary.open(Section.comic);
      library.shelve(sourceId: 'src', itemId: 'fav', title: '手点收藏');

      expect(library.favorites().single.itemId, 'fav');
      expect(library.history(), isEmpty, reason: '收藏了但没读只在收藏页');

      library.recordHistoryItem(sourceId: 'src', itemId: 'fav', title: '手点收藏');
      expect(library.onShelf('fav'), isTrue, reason: '历史写入不能冲掉收藏');
      expect(library.favorites().single.itemId, 'fav');
      expect(library.history(), isEmpty);

      library.saveProgress(comicProgress(itemId: 'fav'));
      expect(
        library.history().map((item) => item.itemId),
        contains('fav'),
        reason: '收藏作品有进度后同时出现在历史里（但收藏位仍是 1）',
      );
      expect(library.onShelf('fav'), isTrue);
    });

    test('删历史：普通历史行连元数据删除，收藏行只清进度保留收藏', () async {
      final library = await ReadingLibrary.open(Section.comic);

      library.recordHistoryItem(
        sourceId: 'src',
        itemId: 'viewed',
        title: '历史行',
      );
      library.removeHistory('viewed');
      expect(library.item('viewed'), isNull, reason: '没有收藏的历史行应彻底删除');
      expect(library.history(), isEmpty);

      library.shelve(sourceId: 'src', itemId: 'fav', title: '收藏行');
      library.saveProgress(comicProgress(itemId: 'fav'));
      library.removeHistory('fav');
      expect(library.progress('fav'), isNull);
      expect(library.onShelf('fav'), isTrue, reason: '删历史不能删收藏');
      expect(library.favorites().single.itemId, 'fav');
      expect(library.history(), isEmpty);
    });

    test('无痕模式下连历史都不写；显式收藏仍然允许', () async {
      final library = await ReadingLibrary.open(Section.video);
      library.setSetting('history.incognito', 'true');
      library.recordHistoryItem(
        sourceId: 'src',
        itemId: 'private',
        title: '无痕',
      );
      expect(library.item('private'), isNull);

      library.shelve(sourceId: 'src', itemId: 'private', title: '无痕');
      expect(library.onShelf('private'), isTrue, reason: '显式收藏不受无痕影响');
    });
  });

  group('阅读偏好与缓存', () {
    test('漫画阅读器设置往返', () async {
      final library = await ReadingLibrary.open(Section.comic);
      const settings = ComicReaderSettings(
        mode: ComicReadingMode.doublePage,
        marginRatio: 0.2,
        doubleTapZoom: true,
      );
      settings.save(library);

      final loaded = ComicReaderSettings.load(library);
      expect(loaded.mode, ComicReadingMode.doublePage);
      expect(loaded.marginRatio, closeTo(0.2, 0.0001));
      expect(loaded.doubleTapZoom, isTrue);
      // 侧边距上限 50%，越界值会被收敛。
      expect(loaded.copyWith(marginRatio: 0.9).marginRatio, 0.5);
    });

    test('缓存键稳定、无路径字符，且同一 URL 得到同一文件', () async {
      final library = await ReadingLibrary.open(Section.comic);
      const url = 'https://example.invalid/a/b/c.jpg?x=1&y=2';

      final key = ReadingStore.cacheKey(url);
      expect(key, ReadingStore.cacheKey(url));
      expect(key, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(key, isNot(contains('/')));

      final store = await ReadingStore.open(Section.comic);
      expect(store.imageCacheFile(url), contains(library.imageCacheDir));
      expect(store.imageCacheFile(url), store.imageCacheFile(url));
      expect(store.imageCacheFile(url), isNot(store.imageCacheFile('$url#2')));
    });

    test('清理缓存只删图片缓存，不动用户保存的图片', () async {
      final library = await ReadingLibrary.open(Section.comic);
      File('${library.imageCacheDir}/cached.img')
          .writeAsBytesSync(<int>[1, 2, 3]);
      final saved = library.saveImage(
        'page1.jpg',
        Uint8List.fromList(<int>[9, 9, 9]),
      );
      final savedAgain = library.saveImage(
        'page1.jpg',
        Uint8List.fromList(<int>[8, 8]),
      );

      expect(File(saved.path).existsSync(), isTrue);
      expect(savedAgain.path, isNot(saved.path), reason: '同名不覆盖，自动加序号');
      expect(library.cacheBytes(), greaterThan(0));

      library.clearCache();
      expect(library.cacheBytes(), 0);
      expect(File(saved.path).existsSync(), isTrue);
      expect(File(savedAgain.path).existsSync(), isTrue);
    });
  });

  group('板块库生命周期', () {
    test('关闭后可重开：数据在磁盘上，旧引用的读写静默降级', () async {
      final library = await ReadingLibrary.open(Section.comic);
      library.shelve(sourceId: 'src', itemId: 'a', title: '甲', chapterCount: 3);

      // 关闭：释放 sqlite 句柄与内存，门面缓存里不再有它。
      ReadingLibrary.close(Section.comic);
      expect(ReadingLibrary.find(Section.comic), isNull);

      // 页面上仍握着旧引用：读写都不能抛，写也不落库（库已释放）。
      expect(library.shelf(), isEmpty);
      expect(library.progress('a'), isNull);
      library.saveProgress(comicProgress(itemId: 'a', chapterIndex: 1));
      expect(library.cacheBytes(), 0, reason: '缓存统计不依赖库句柄，仍然可用');

      // 重新打开：同一库文件，之前入架的数据还在；关闭期间的写入没有落库。
      final reopened = await ReadingLibrary.open(Section.comic);
      expect(reopened.onShelf('a'), isTrue);
      expect(reopened.item('a')!.title, '甲');
      expect(reopened.progress('a'), isNull, reason: '关闭期间的写入不落库');

      reopened.saveProgress(comicProgress(itemId: 'a', chapterIndex: 1));
      expect(reopened.comicProgress('a')!.chapterIndex, 1);
      expect(reopened.shelf().single.itemId, 'a');
      // 旧引用仍指向已关闭的库，不会把新库带坏。
      expect(library.shelf(), isEmpty);

      // 重复关闭安全。
      ReadingLibrary.close(Section.comic);
      ReadingLibrary.close(Section.comic);
    });
  });
}
