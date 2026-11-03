import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume_box/core/tmdb/tmdb.dart';
import 'package:lume_box/features/video/tmdb_artwork.dart';

http.Response json(Map<String, dynamic> data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const selected = TmdbMatchCandidate(
  id: 22,
  mediaType: 'tv',
  title: '大展宏图',
  year: '2026',
);

http.Response fixture(http.Request request) {
  if (request.url.path.endsWith('/search/multi')) {
    return json({
      'results': [
        {
          'id': 11,
          'media_type': 'movie',
          'title': '大展宏图',
          'release_date': '1990-01-01',
          'overview': '旧电影',
        },
        {
          'id': 22,
          'media_type': 'tv',
          'name': '大展宏图',
          'first_air_date': '2026-01-01',
          'overview': '理发师穿越的剧集',
        },
        {'id': 22, 'media_type': 'tv', 'name': '大展宏图'},
        {'id': 33, 'media_type': 'person', 'name': '大展宏图'},
      ],
    });
  }
  expect(request.url.path, endsWith('/tv/22'));
  return json({
    'name': '大展宏图',
    'first_air_date': '2026-01-01',
    'overview': '所选剧集剧情',
    'number_of_episodes': 24,
    'images': {
      'posters': [
        {'file_path': '/selected.jpg'},
      ],
    },
    'credits': {
      'cast': [
        {'name': '演员甲'},
      ],
    },
  });
}

TmdbSettings configured() => TmdbSettings()
  ..enabled = true
  ..apiKey = 'test-only-key';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同名作品不盲选；手动选择按 ID 加载且覆盖错误年份类型提示', () async {
    final settings = configured();
    var searches = 0;
    var details = 0;
    final client = TmdbClient(
      settings,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/search/multi')) {
          searches++;
        } else {
          details++;
        }
        return fixture(request);
      }),
    );
    addTearDown(client.dispose);
    expect(await client.lookup('大展宏图'), isNull);
    expect(client.lastError, contains('多个同名'));
    expect(details, 0);
    final candidates = await client.searchMatches('大展宏图');
    expect(candidates.map((e) => e.id), [11, 22]);
    expect(candidates.last.label, '剧集 · 2026');
    final result = await client.selectMatch(
      '大展宏图',
      candidates.last,
      year: '1990',
      mediaType: 'movie',
    );
    expect(result!.overview, '所选剧集剧情');
    expect(result.posters.single, endsWith('/w780/selected.jpg'));
    expect(result.cast, ['演员甲']);
    expect(result.episodeCount, 24);
    expect(details, 1);
    expect(searches, 2);
    expect(
      (await client.lookup('大展宏图', year: '1990', mediaType: 'movie'))!.year,
      '2026',
    );
    expect(searches, 2);
  });

  test('手动选择缓存重启后可读取，无须再次进行同名匹配', () async {
    final root = Directory.systemTemp.createTempSync('tmdb-manual-match-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      root.deleteSync(recursive: true);
    });
    final settings = TmdbSettings();
    await settings.boot();
    settings.enabled = true;
    settings.apiKey = 'test-only-key';
    await settings.save();
    final client = TmdbClient(
      settings,
      client: MockClient((r) async => fixture(r)),
    );
    expect(await client.selectMatch('大展宏图', selected), isNotNull);
    await settings.flush();
    client.dispose();

    final reopened = TmdbSettings();
    await reopened.boot();
    final cached = TmdbClient(
      reopened,
      client: MockClient((_) async {
        fail('缓存命中不应再次请求网络');
      }),
    );
    addTearDown(cached.dispose);
    expect((await cached.lookup('大展宏图'))!.overview, '所选剧集剧情');
  });

  test('海报优先中文，同语言保留排名；手选后刷新仍使用选定海报', () async {
    final settings = configured();
    final client = TmdbClient(
      settings,
      client: MockClient((r) async {
        if (r.url.path.endsWith('/search/multi')) return fixture(r);
        return json({
          'images': {
            'posters': [
              {'file_path': '/english.jpg', 'iso_639_1': 'en'},
              {'file_path': '/chinese.jpg', 'iso_639_1': 'zh'},
              {'file_path': '/other-chinese.jpg', 'iso_639_1': 'zh'},
            ],
          },
        });
      }),
    );
    final controller = TmdbDetailController(
      '大展宏图',
      settings: settings,
      client: client,
      autoLoad: false,
    );
    addTearDown(controller.dispose);
    await controller.selectMatch(selected);
    expect(
      controller.metadata!.posters.map(
        (url) => Uri.parse(url).pathSegments.last,
      ),
      ['chinese.jpg', 'other-chinese.jpg', 'english.jpg'],
    );
    final chosen = controller.metadata!.posters.last;
    await controller.selectPoster(chosen);
    expect(controller.metadata!.posters.first, chosen);
    await controller.refresh();
    expect(controller.metadata!.posters.first, chosen);
    expect(controller.index, 0);
  });

  testWidgets('重新匹配显示候选，选定后更新详情并关闭弹窗', (tester) async {
    final settings = configured();
    final client = TmdbClient(
      settings,
      client: MockClient((r) async => fixture(r)),
    );
    final controller = TmdbDetailController(
      '大展宏图',
      settings: settings,
      client: client,
      autoLoad: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showTmdbMatchPicker(context, controller),
              child: const Text('重新匹配'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('重新匹配'));
    await tester.pumpAndSettle();
    expect(find.text('选择 TMDB 条目'), findsOneWidget);
    expect(find.textContaining('电影 · 1990'), findsOneWidget);
    expect(find.textContaining('剧集 · 2026'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tmdb-match-tv-22')));
    await tester.pumpAndSettle();
    expect(find.text('选择 TMDB 条目'), findsNothing);
    expect(controller.metadata!.posters.single, endsWith('/selected.jpg'));
    expect(controller.loading, isFalse);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('搜索失败有可见错误，可以修改片名重试；取消保留已有资料', (tester) async {
    var calls = 0;
    final settings = configured();
    final client = TmdbClient(
      settings,
      client: MockClient((r) async {
        calls++;
        if (calls == 1) return http.Response('{}', 403);
        expect(r.url.queryParameters['query'], '新片名');
        return fixture(r);
      }),
    );
    final controller = TmdbDetailController(
      '大展宏图',
      settings: settings,
      client: client,
      autoLoad: false,
    );
    controller.metadata = const TmdbMetadata(overview: '原有资料', posters: []);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showTmdbMatchPicker(context, controller),
              child: const Text('重新匹配'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('重新匹配'));
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP 403'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tmdb-match-query')), '新片名');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tmdb-match-tv-22')), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.metadata!.overview, '原有资料');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
