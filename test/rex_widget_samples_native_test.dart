import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume_box/core/js/source_engine.dart';
import 'package:lume_box/core/js/source_script.dart';
import 'package:lume_box/core/net/lume_http.dart';
import 'package:lume_box/core/net/network_settings.dart';
import 'package:lume_box/core/reading/reading_library.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source_package.dart';

import 'js_sandbox/support/js_sandbox_support.dart';

/// User samples stay outside the repository. Every request is answered offline.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final available = installBridge();
  final directory =
      Platform.environment['LUME_REX_SAMPLE_DIR'] ??
      '.cache/rex-compat/samples';
  for (final sample in <String, String>{
    '大师兄(rex).js':
        '9a9760448b53aebdf95003e6c292a3ff32db6ccb8a6cc2e380968ba6c7d000d9',
    '采集聚合(rex).js':
        'a85cb5ca6a301517c6134cdb943dc053614ea53112e7fcd8d86a4e38fbabe74f',
    '荐片(rex).js':
        '71b5c7b6c771242a3966fd9d7023b18310eb8e6e28ea8234ccd84176a8574b33',
  }.entries) {
    final file = File('$directory/${sample.key}');
    test(
      '用户原文件 ${sample.key}：真实 QuickJS 搜索、详情、选线、播放地址',
      () async {
        final root = Directory.systemTemp.createTempSync('lume_rex_sample');
        enableEngineOnThisPlatform();
        await installTempSectionRoot(root);
        QuickJsSourceEngine? engine;
        final requests = <http.Request>[];
        var dsPosts = 0;
        http.Response json(Object value) => http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
        final client = MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/ndsx.php/v7/logs') {
            expect(request.method, 'POST');
            expect(request.body, isNotEmpty);
            dsPosts++;
            if (dsPosts.isOdd) {
              return json({
                'code': 1,
                'data': [
                  {'vod_id': 7, 'vod_name': '示例影片', 'type_id': 1},
                ],
              });
            }
            return json({
              'code': 1,
              'data': {
                'vod_info': {
                  'vod_id': 7,
                  'vod_name': '示例影片',
                  'type_id': 1,
                  'vod_url_with_player': [
                    {
                      'code': 'direct',
                      'name': '示例线路',
                      'headers': {'Referer': 'https://fixture.invalid/'},
                      'url': r'正片$https://media.invalid/dsx.mp4',
                    },
                  ],
                },
              },
            });
          }
          if (request.url.host == 'media.invalid') {
            expect(request.headers['Range'], isNotEmpty);
            return http.Response.bytes(
              [0, 0, 0, 24, ...ascii.encode('ftyp'), ...List.filled(1016, 0)],
              206,
              headers: {'content-type': 'video/mp4'},
            );
          }
          if (request.url.path == '/api/v2/search/videoV2') {
            return json({
              'code': 1,
              'data': [
                {'id': 7, 'title': '示例影片'},
              ],
            });
          }
          if (request.url.path == '/api/video/detailv2') {
            return json({
              'code': 1,
              'data': {
                'title': '示例影片',
                'source_list_source': [
                  {
                    'name': '高清线路',
                    'source_list': [
                      {
                        'url': 'https://media.invalid/jp.m3u8',
                        'source_name': '正片',
                      },
                    ],
                  },
                ],
              },
            });
          }
          expect(request.url.queryParameters['wd'], '示例影片');
          return json({
            'list': [
              {
                'vod_name': '示例影片',
                'vod_play_from': '高清',
                'vod_play_url': r'正片$https://media.invalid/vod.m3u8',
              },
            ],
          });
        });
        try {
          final bytes = file.readAsBytesSync();
          expect(
            sha256.convert(bytes).toString(),
            sample.value,
            reason: '验收样本版本已变更',
          );
          final script = SourcePackage.fromBytes(bytes, name: sample.key),
              id = SourceMetadata.parseHeader(
                SourcePackage.fromBytes(bytes, name: sample.key),
              )!.id;
          engine = (await SourceEngineRegistry.createForScript(
            script: script,
            kind: CatEngineKind.quickjs,
            sourceId: id,
            http: LumeHttp(
              client: client,
              settings: const NetworkSettings(maxRetries: 0),
            ),
            section: Section.video,
          )) as QuickJsSourceEngine;
          expect(
            await engine.loadScript(script),
            isTrue,
            reason: engine.loadFailure,
          );
          Future<dynamic> call(String name, Object args) async {
            final r = await engine!.callResult(name, args);
            expect(r.isOk, isTrue, reason: r.error?.message);
            return r.value;
          }

          final result = await call('list', {'keyword': '示例影片'});
          expect(result['items'], isNotEmpty);
          final item = result['items'][0];
          expect((await call('detail', {'id': item['id']}))['title'], '示例影片');
          final chapters = await call('chapters', {'id': item['id']});
          expect(chapters, isNotEmpty);
          final video = await call('content', {
            'itemId': item['id'],
            'chapterId': chapters[0]['id'],
          });
          expect(video['kind'], 'video');
          expect(video['url'], startsWith('https://media.invalid/'));
          if (sample.key.startsWith('大师兄')) {
            expect(video['headers']['Referer'], 'https://fixture.invalid/');
          }
          if (sample.key.startsWith('采集')) {
            final count = requests.length;
            expect(
              (await call('list', {'keyword': '示例影片'}))['items'],
              isNotEmpty,
            );
            expect(requests.length, count, reason: '同步对象缓存应在第二次搜索命中');
          }
          engine.dispose();
          engine = (await SourceEngineRegistry.createForScript(
            script: script,
            kind: CatEngineKind.quickjs,
            sourceId: id,
            http: LumeHttp(
              client: client,
              settings: const NetworkSettings(maxRetries: 0),
            ),
            section: Section.video,
          )) as QuickJsSourceEngine;
          expect(
            await engine.loadScript(script),
            isTrue,
            reason: engine.loadFailure,
          );
          final reopened = await call('content', {
            'itemId': item['id'],
            'chapterId': chapters[0]['id'],
          });
          expect(reopened['url'], video['url']);
          expect(reopened['headers'], video['headers']);
        } finally {
          engine?.dispose();
          client.close();
          ReadingLibrary.disposeAll();
          await SectionScope.closeAll();
          restoreEnginePlatformGate();
          root.deleteSync(recursive: true);
        }
      },
      skip: !available
          ? 'QuickJS 原生桥不可用'
          : !file.existsSync()
          ? '设置 LUME_REX_SAMPLE_DIR 可验证用户原文件'
          : null,
    );
  }
}
