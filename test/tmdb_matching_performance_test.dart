import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume_box/core/tmdb/tmdb.dart';
import 'package:lume_box/features/video/tmdb_artwork.dart';

http.Response json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
TmdbSettings settings() => TmdbSettings()
  ..enabled = true
  ..apiKey = 'fixture-key';

void main() {
  test('重复标题请求合并，合并图片响应后冷加载只需搜索和详情两次请求', () async {
    final ready = Completer<void>();
    final paths = <String>[];
    final config = settings();
    final client = TmdbClient(
      config,
      client: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/search/multi')) {
          await ready.future;
          return json({
            'results': [
              {
                'id': 1,
                'media_type': 'tv',
                'name': '同名剧',
                'first_air_date': '2026-01-01',
              },
            ],
          });
        }
        expect(
          request.url.queryParameters['append_to_response'],
          contains('images'),
        );
        return json({
          'name': '同名剧',
          'first_air_date': '2026-01-01',
          'images': {
            'posters': [
              {'file_path': '/poster.jpg'},
            ],
            'backdrops': [
              {'file_path': '/backdrop.jpg'},
            ],
            'logos': [
              {'file_path': '/logo.png'},
            ],
          },
        });
      }),
    );
    addTearDown(client.dispose);
    final one = client.lookup('同名剧 1080p', year: '2026', mediaType: 'tv');
    final two = client.lookup('同名剧', year: '2026', mediaType: 'tv');
    ready.complete();
    expect((await one)?.logos.single, endsWith('/logo.png'));
    expect(await two, isNotNull);
    expect(paths, hasLength(2));
    await client.lookup('同名剧', year: '2026', mediaType: 'tv');
    expect(paths, hasLength(2));
  });

  test('同名翻拍和电影版按年份类型核验，无上下文歧义不盲选', () async {
    final config = settings();
    final fetched = <String>[];
    final client = TmdbClient(
      config,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/search/multi')) {
          return json({
            'results': [
              {
                'id': 1,
                'media_type': 'tv',
                'name': '同名剧',
                'first_air_date': '1998-01-01',
              },
              {
                'id': 2,
                'media_type': 'tv',
                'name': '同名剧',
                'first_air_date': '2026-01-01',
              },
              {
                'id': 3,
                'media_type': 'movie',
                'title': '同名剧',
                'release_date': '2026-01-01',
              },
            ],
          });
        }
        fetched.add(request.url.path);
        return json({
          'name': '同名剧',
          'first_air_date': '2026-01-01',
          'overview': '正确剧版',
          'images': {},
        });
      }),
    );
    addTearDown(client.dispose);
    expect(await client.lookup('同名剧'), isNull);
    expect(client.lastError, contains('多个同名版本'));
    expect(fetched, isEmpty);
    expect(
      (await client.lookup('同名剧', year: '2026', mediaType: 'tv'))?.overview,
      '正确剧版',
    );
    expect(fetched.single, endsWith('/tv/2'));
    expect(await client.lookup('同名剧', year: '2025', mediaType: 'tv'), isNull);
  });

  test('短暂503自动重试一次，401不重试，不需要手动点击重新匹配', () async {
    for (final status in [503, 401]) {
      var searchCalls = 0;
      final client = TmdbClient(
        settings(),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/search/multi')) {
            if (++searchCalls == 1) return http.Response('{}', status);
            return json({
              'results': [
                {'id': 1, 'media_type': 'tv', 'name': '测试剧'},
              ],
            });
          }
          return json({'images': {}});
        }),
      );
      final result = await client.lookup('测试剧');
      expect(searchCalls, status == 503 ? 2 : 1);
      expect(result, status == 503 ? isNotNull : isNull);
      client.dispose();
    }
  });

  test('等待源详情再匹配，同一标题不因清晰度后缀重复启动', () async {
    var searches = 0;
    final config = settings();
    final client = TmdbClient(
      config,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/search/multi')) {
          searches++;
          return json({
            'results': [
              {'id': 1, 'media_type': 'tv', 'name': '测试剧'},
            ],
          });
        }
        return json({'images': {}});
      }),
    );
    final controller = TmdbDetailController(
      '测试剧',
      settings: config,
      client: client,
      autoLoad: false,
    );
    expect(searches, 0);
    controller.updateTitles(['测试剧 1080p', '测试剧']);
    for (var i = 0; i < 20 && controller.loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(controller.metadata, isNotNull);
    controller.updateTitles(['测试剧']);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(searches, 1);
    controller.dispose();
  });
}
