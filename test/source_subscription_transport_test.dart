import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume_box/core/net/lume_http.dart';
import 'package:lume_box/core/net/network_settings.dart';
import 'package:lume_box/core/net/source_subscription.dart';
import 'package:lume_box/core/source/source_subscription_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('GitHub 拉取失败自动用 CDN，仍保留原始地址和强制更新请求头', () async {
    const url = 'https://raw.githubusercontent.com/example/sources/main/源.js';
    final calls = <Uri>[];
    final client = LumeHttp(
      client: MockClient((request) async {
        calls.add(request.url);
        expect(request.headers['Cache-Control'], 'no-cache');
        if (request.url.host == 'raw.githubusercontent.com') {
          throw const SocketException('offline');
        }
        return http.Response('var LumeSource = {};', 200);
      }),
      settings: const NetworkSettings(maxRetries: 0),
    );
    addTearDown(client.dispose);
    final resolver = SourceSubscription(
      fetch: (url) =>
          SourceSubscription.fetchSubscription(client, url, force: true),
    );
    final refs = await resolver.resolveRefs([url]);
    expect(refs.single.url, url);
    expect(calls.map((u) => u.host), [
      'raw.githubusercontent.com',
      'cdn.jsdelivr.net',
    ]);
    expect(
      Uri.decodeComponent(calls.last.path),
      '/gh/example/sources@main/源.js',
    );
  });
  test('真实 404 不用缓存 CDN 掩盖，自定义私有查询地址不改写', () async {
    var calls = 0;
    final client = LumeHttp(
      client: MockClient((_) async {
        calls++;
        return http.Response('missing', 404);
      }),
    );
    addTearDown(client.dispose);
    await expectLater(
      SourceSubscription.fetchSubscription(
        client,
        'https://raw.githubusercontent.com/example/sources/main/gone.js',
      ),
      throwsStateError,
    );
    expect(calls, 1);
    expect(
      SourceSubscription.githubCdnUrl('https://private.test/list'),
      isNull,
    );
    expect(
      SourceSubscription.githubCdnUrl(
        'https://raw.githubusercontent.com/a/b/main/file?token=secret',
      ),
      isNull,
    );
    expect(
      SourceSubscription.githubCdnUrl(
        'https://raw.githubusercontent.com/a/b/refs/heads/main/file',
      ),
      'https://cdn.jsdelivr.net/gh/a/b@main/file',
    );
  });
  test('官方 GitHub 清单网络失败时使用当前 CDN 专用清单', () async {
    final calls = <Uri>[];
    final client = LumeHttp(
      client: MockClient((request) async {
        calls.add(request.url);
        if (request.url.host == 'raw.githubusercontent.com') {
          throw const SocketException('offline');
        }
        if (request.url.path.endsWith('/all.json')) {
          return http.Response(
            jsonEncode({
              'format': 'lume.total-subscription',
              'version': 1,
              'sections': {
                'video': [
                  '${SubscriptionCatalog.cdnBase}subscriptions/cdn/video.22222222.txt',
                ],
              },
            }),
            200,
          );
        }
        return http.Response('# empty authoritative list', 200);
      }),
      settings: const NetworkSettings(maxRetries: 0),
    );
    addTearDown(client.dispose);
    await SourceSubscription.fetchSubscription(
      client,
      'https://raw.githubusercontent.com/teng662858/LumeBox-Sources/main/subscriptions/video.txt',
    );
    expect(
      calls.last.path,
      '/gh/teng662858/LumeBox-Sources@main/subscriptions/cdn/video.22222222.txt',
    );
  });

  test('旧固定快照每次同步跟随当前指针，视频汇总只展开视频清单', () async {
    var revision = '22222222';
    final calls = <String>[];
    final client = LumeHttp(
      client: MockClient((request) async {
        calls.add(request.url.toString());
        if (request.url.path.endsWith('/all.json')) {
          return http.Response(
            jsonEncode({
              'format': 'lume.total-subscription',
              'version': 1,
              'sections': {
                'comic': [
                  '${SubscriptionCatalog.cdnBase}subscriptions/cdn/comic.$revision.txt',
                ],
                'video': [
                  '${SubscriptionCatalog.cdnBase}subscriptions/cdn/video.$revision.txt',
                ],
              },
            }),
            200,
          );
        }
        return http.Response(
          request.url.path.endsWith('video.$revision.txt')
              ? '# current $revision'
              : '# stale',
          200,
        );
      }),
    );
    addTearDown(client.dispose);
    const old =
        '${SubscriptionCatalog.cdnBase}subscriptions/cdn/video.11111111.txt';
    expect(
      (await SourceSubscription.fetchSubscription(client, old)).text,
      '# current 22222222',
    );
    revision = '33333333';
    expect(
      (await SourceSubscription.fetchSubscription(client, old)).text,
      '# current 33333333',
    );
    expect(calls, isNot(contains(old)));
    final aggregate = await SourceSubscription.fetchSubscription(
      client,
      '${SubscriptionCatalog.cdnBase}subscriptions/cdn/videos.txt',
    );
    expect((jsonDecode(aggregate.text) as Map)['sections'], {
      'video': [
        '${SubscriptionCatalog.cdnBase}subscriptions/cdn/video.33333333.txt',
      ],
    });
  });

  test('当前 CDN 指针失败不会采用可能过期的旧清单', () async {
    final calls = <String>[];
    final client = LumeHttp(
      client: MockClient((request) async {
        calls.add(request.url.toString());
        return http.Response('stale or invalid', 200);
      }),
    );
    addTearDown(client.dispose);
    await expectLater(
      SourceSubscription.fetchSubscription(
        client,
        '${SubscriptionCatalog.cdnBase}subscriptions/cdn/video.11111111.txt',
      ),
      throwsStateError,
    );
    expect(calls, [SubscriptionCatalog.totalCdnUrl]);
  });
}
