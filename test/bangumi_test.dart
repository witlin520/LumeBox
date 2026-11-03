import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume_box/core/bangumi/bangumi_client.dart';
import 'package:lume_box/core/bangumi/bangumi_sync.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';

http.Response jsonResponse(Object data) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lumebox-bangumi');
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
  });

  tearDown(() {
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    root.deleteSync(recursive: true);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(BangumiSettings.channel, null);
  });

  test(
    'client authenticates, searches, reads episodes and writes progress',
    () async {
      final requests = <http.Request>[];
      final client = BangumiClient(
        'test-token',
        client: MockClient((request) async {
          requests.add(request);
          switch (request.url.path) {
            case '/v0/me':
              return jsonResponse({
                'id': 9,
                'username': 'alice',
                'nickname': '爱丽丝',
              });
            case '/v0/search/subjects':
              return jsonResponse({
                'data': [
                  {
                    'id': 7,
                    'name': 'Sousou no Frieren',
                    'name_cn': '葬送的芙莉莲',
                    'date': '2023-09-29',
                    'images': {'large': 'https://example.test/cover.jpg'},
                  },
                ],
              });
            case '/v0/episodes':
              return jsonResponse({
                'data': [
                  {'id': 12, 'sort': 2, 'name': '', 'name_cn': ''},
                  {'id': 11, 'sort': 1, 'name': '', 'name_cn': ''},
                ],
              });
            default:
              return jsonResponse({});
          }
        }),
      );

      final user = await client.me();
      expect(user.id, 9);
      expect(user.displayName, '爱丽丝');
      final results = await client.search('芙莉莲');
      expect(results.single.id, 7);
      expect(results.single.displayName, '葬送的芙莉莲');
      final episodes = await client.episodes(7);
      expect([for (final episode in episodes) episode.id], [11, 12]);
      await client.updateCollection(7, 3);
      await client.markEpisodes(7, [11, 12]);

      expect(requests.first.headers['Authorization'], 'Bearer test-token');
      expect(requests.first.followRedirects, false);
      final search = requests.firstWhere(
        (request) => request.url.path == '/v0/search/subjects',
      );
      expect(jsonDecode(search.body)['filter']['type'], [2]);
      final episode = requests.firstWhere(
        (request) => request.url.path == '/v0/episodes',
      );
      expect(episode.url.queryParameters['subject_id'], '7');
      final mark = requests.last;
      expect(mark.url.path, '/v0/users/-/collections/7/episodes');
      expect(jsonDecode(mark.body), {
        'episode_id': [11, 12],
        'type': 2,
      });
      final collection = requests.firstWhere(
        (request) => request.url.path == '/v0/users/-/collections/7',
      );
      expect(jsonDecode(collection.body), {'type': 3});
      client.close();
    },
  );

  test('binding JSON round-trips and rejects corrupt values', () {
    const value = BangumiBinding(
      subjectId: 7,
      name: '葬送的芙莉莲',
      episodes: [11, 12, 13],
    );
    final decoded = BangumiBinding.decode(value.encode())!;
    expect(decoded.subjectId, 7);
    expect(decoded.name, '葬送的芙莉莲');
    expect(decoded.episodes, [11, 12, 13]);
    expect(BangumiBinding.decode(''), isNull);
    expect(BangumiBinding.decode('{bad json'), isNull);
    expect(BangumiBinding.decode('{"name":"x"}'), isNull);
  });

  test('token uses the keychain and falls back to a local file', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(BangumiSettings.channel, (call) async {
      calls.add(call);
      if (call.method == 'speechGetKey') return null;
      return null;
    });
    final settings = BangumiSettings();
    await settings.setToken('secret-token');
    expect(
      calls.any(
        (call) =>
            call.method == 'speechSetKey' &&
            (call.arguments as Map)['kind'] == 'bangumi',
      ),
      isTrue,
    );
    expect(await settings.token(), 'secret-token');

    messenger.setMockMethodCallHandler(
      BangumiSettings.channel,
      (_) async => throw MissingPluginException(),
    );
    final fallback = BangumiSettings();
    await fallback.setToken('file-token');
    final restored = BangumiSettings();
    expect(await restored.token(), 'file-token');
  });

  test(
    'progress sync marks episodes and switches to watched at the end',
    () async {
      messenger.setMockMethodCallHandler(BangumiSettings.channel, (call) async {
        if (call.method == 'speechGetKey') return 'sync-token';
        return null;
      });
      final settings = BangumiSettings();
      await settings.setToken('sync-token');
      settings.autoSync = true;
      final library = await ReadingLibrary.open(Section.video);
      library.setSetting(
        BangumiBinding.keyFor('item-1'),
        const BangumiBinding(
          subjectId: 7,
          name: '葬送的芙莉莲',
          episodes: [11, 12, 13],
        ).encode(),
      );

      final paths = <String>[];
      final bodies = <String>[];
      final service = BangumiSyncService(
        settings: settings,
        clientFactory: (token) => BangumiClient(
          token,
          client: MockClient((request) async {
            paths.add(request.url.path);
            bodies.add(request.body);
            return http.Response('{}', 200);
          }),
        ),
      );

      VideoProgress progress(int chapter, int seconds) => VideoProgress(
        section: Section.video,
        itemId: 'item-1',
        chapterIndex: chapter,
        chapterId: 'c$chapter',
        chapterTitle: '第 ${chapter + 1} 集',
        updatedAt: DateTime.now(),
        position: Duration(seconds: seconds),
        duration: const Duration(seconds: 100),
      );

      await service.afterProgress(library, progress(1, 10), force: true);
      final mark = bodies[paths.indexOf('/v0/users/-/collections/7/episodes')];
      expect(jsonDecode(mark), {
        'episode_id': [11, 12],
        'type': 2,
      });
      final collection = bodies[paths.indexOf('/v0/users/-/collections/7')];
      expect(jsonDecode(collection)['type'], 3);

      await service.afterProgress(library, progress(2, 96), force: true);
      final finishedMark = bodies.lastWhere(
        (body) => body.contains('episode_id'),
      );
      expect(jsonDecode(finishedMark)['episode_id'], [11, 12, 13]);
      final finishedCollection = bodies.last;
      expect(jsonDecode(finishedCollection)['type'], 2);
    },
  );
}
