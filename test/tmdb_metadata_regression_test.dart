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
TmdbSettings configured() => TmdbSettings()
  ..enabled = true
  ..apiKey = 'test-only-key'
  ..apiProxy = 'https://proxy.test/prefix/3'
  ..imageProxy = 'https://images.test/t/p';
http.Response response(Uri uri, {bool alias = false}) {
  if (uri.path.endsWith('/configuration')) return json({'images': {}});
  if (uri.path.endsWith('/search/multi')) {
    return json({
      'results': [
        {'id': 42, 'media_type': 'movie', 'title': alias ? '另一译名' : '影片'},
      ],
    });
  }
  if (uri.path.endsWith('/images')) {
    return json({
      'posters': [
        {'file_path': '/poster.jpg'},
      ],
      'logos': [
        {'file_path': '/logo.png'},
      ],
      'stills': [
        {'file_path': '/still.jpg'},
      ],
      'backdrops': [
        {'file_path': '/background.jpg'},
      ],
    });
  }
  return json({
    'title': alias ? '另一译名' : '影片',
    'overview': '官方剧情',
    'vote_average': 8.6,
    'vote_count': 128,
    'release_date': '2026-10-25',
    'genres': [
      {'id': 18, 'name': '剧情'},
    ],
    'credits': {
      'cast': [
        {'name': '演员甲', 'profile_path': '/actor.jpg'},
        {'name': '演员乙'},
      ],
    },
    'alternative_titles': {
      'titles': [
        {'title': '影片'},
      ],
    },
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('测试与业务的搜索详情图片请求全部使用同一代理和Key', () async {
    final settings = configured();
    final urls = <Uri>[];
    final client = TmdbClient(
      settings,
      client: MockClient((r) async {
        urls.add(r.url);
        return response(r.url);
      }),
    );
    await client.testApi();
    final data = await client.lookup('影片');
    expect(urls.length, 4);
    expect(
      urls.every(
        (u) =>
            u.host == 'proxy.test' &&
            u.path.startsWith('/prefix/3/') &&
            u.queryParameters['api_key'] == 'test-only-key',
      ),
      isTrue,
    );
    expect(data!.rating, 8.6);
    expect(data.cast, ['演员甲', '演员乙']);
    expect(data.overview, '官方剧情');
    expect(data.year, '2026');
    expect(data.genres, ['剧情']);
    expect(data.episodeCount, 0, reason: '电影不虚构集数');
    final restored = TmdbMetadata.fromJson(data.toJson());
    expect(restored.year, '2026');
    expect(restored.genres, ['剧情']);
    expect(TmdbMetadata.fromJson({}).year, isEmpty);
    expect(data.backdrops, ['https://images.test/t/p/w1280/background.jpg']);
    expect(data.logos, ['https://images.test/t/p/w500/logo.png']);
    expect(data.profiles, ['https://images.test/t/p/w185/actor.jpg', '']);
    expect(data.videoCovers, ['https://images.test/t/p/w300/still.jpg']);
    settings.setImageSize(TmdbImageKind.backdrop, 'original');
    settings.setImageSize(TmdbImageKind.profile, 'w632');
    settings.setImageSize(TmdbImageKind.video, 'w500');
    await settings.save();
    final changed = (await client.lookup('影片'))!;
    expect(changed.backdrops, [
      'https://images.test/t/p/original/background.jpg',
    ]);
    expect(changed.profiles, ['https://images.test/t/p/w632/actor.jpg', '']);
    expect(changed.videoCovers, ['https://images.test/t/p/w500/still.jpg']);
    client.dispose();
  });
  test('标题清理和繁简匹配，不盲选不相干候选', () async {
    expect(TmdbClient.cleanTitle('2001太空漫游'), '2001太空漫游');
    expect(TmdbClient.cleanTitle('蓝光之恋'), '蓝光之恋');
    expect(TmdbClient.cleanTitle('影片 (2024) 1080p'), '影片');
    final client = TmdbClient(
      configured(),
      client: MockClient((r) async => response(r.url)),
    );
    expect(await client.lookup('影片 (2024) 1080p'), isNull);
    expect(await client.lookup('影片 (2026) 1080p'), isNotNull);
    expect(await client.lookup('完全无关'), isNull);
    client.dispose();
  });
  test('搜索别名通过详情中的替代标题确认后匹配', () async {
    final client = TmdbClient(
      configured(),
      client: MockClient((r) async => response(r.url, alias: true)),
    );
    expect((await client.lookup('影片'))?.rating, 8.6);
    client.dispose();
  });
  test('成功缓存跨重启读取无请求，强制重匹配重新请求且覆盖缓存', () async {
    final root = Directory.systemTemp.createTempSync('tmdb-cache-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    try {
      var requests = 0;
      final first = configured();
      await first.boot();
      final client = TmdbClient(
        first,
        client: MockClient((r) async {
          requests++;
          return response(r.url);
        }),
      );
      await client.lookup('影片');
      expect(requests, 3);
      await first.flush();
      client.dispose();
      final next = configured();
      await next.boot();
      final reopened = TmdbClient(
        next,
        client: MockClient((r) async {
          requests++;
          return response(r.url);
        }),
      );
      expect((await reopened.lookup('影片'))?.cast, ['演员甲', '演员乙']);
      expect(requests, 3);
      await reopened.lookup('影片', force: true);
      expect(requests, 6);
      next.enabled = false;
      expect(await reopened.lookup('影片'), isNull);
      expect(requests, 6);
      await next.flush();
      reopened.dispose();
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      root.deleteSync(recursive: true);
    }
  });
  test('图片接口失败仍保留评分演员简介，网络错误不暴露Key', () async {
    final client = TmdbClient(
      configured(),
      client: MockClient(
        (r) async => r.url.path.endsWith('/images')
            ? http.Response('error', 503)
            : response(r.url),
      ),
    );
    expect((await client.lookup('影片'))?.rating, 8.6);
    expect(client.lastError, contains('图片'));
    client.dispose();
    final failed = TmdbClient(
      configured(),
      client: MockClient((r) async => throw Exception(r.url.toString())),
    );
    expect(await failed.lookup('影片'), isNull);
    expect(failed.lastError, contains('网络'));
    expect(failed.lastError, isNot(contains('test-only-key')));
    failed.dispose();
  });
  testWidgets('详情资料展示评分演员官方简介和背景图，更多可手动重匹配', (tester) async {
    var calls = 0;
    final settings = configured();
    final controller = TmdbDetailController(
      '影片',
      settings: settings,
      client: TmdbClient(
        settings,
        client: MockClient((r) async {
          calls++;
          return response(r.url);
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [TmdbRematchMenu(controller: controller)]),
          body: SingleChildScrollView(
            child: TmdbInformation(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('8.6'), findsOneWidget);
    expect(find.text('演员甲'), findsOneWidget);
    expect(find.text('官方剧情'), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
    final background = find.byKey(const Key('tmdb-backdrop'));
    expect(tester.getSize(background).height, 220);
    expect(tester.getTopLeft(background).dx, 0);
    expect(tester.getSize(background).width, 800);
    expect(
      tester
          .widget<Image>(
            find.descendant(of: background, matching: find.byType(Image)).first,
          )
          .fit,
      BoxFit.cover,
    );
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新匹配TMDB'));
    await tester.pumpAndSettle();
    expect(calls, 6);
    settings.enabled = false;
    await settings.save();
    await tester.pump();
    expect(find.textContaining('8.6'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
