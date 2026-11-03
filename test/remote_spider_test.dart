import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/js/source_registry.dart';
import 'package:lume_box/core/net/lume_net.dart';
import 'package:lume_box/core/net/source_import_input.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source.dart';

import 'js_sandbox/support/js_sandbox_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final available = installBridge();
  for (final transport in ['t4', 'rpc']) {
    test('远程 Spider $transport：实际 HTTP 请求到播放地址', () async {
      final saved = HttpOverrides.current;
      HttpOverrides.global = null;
      final root = Directory.systemTemp.createTempSync('lume_remote_spider');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final calls = <String>[];
      enableEngineOnThisPlatform();
      await installTempSectionRoot(root);
      server.listen((request) async {
        final query = request.uri.queryParameters;
        final body = request.method == 'POST'
            ? jsonDecode(await utf8.decoder.bind(request).join()) as Map
            : {};
        final method = transport == 'rpc'
            ? '${body['method']}'
            : query.containsKey('play')
            ? 'playerContent'
            : query.containsKey('ids')
            ? 'detailContent'
            : query.containsKey('wd')
            ? 'searchContent'
            : query.containsKey('t')
            ? 'categoryContent'
            : query['ac'] == 'detail'
            ? 'homeVideoContent'
            : 'homeContent';
        calls.add(method);
        Object value;
        switch (method) {
          case 'playerContent':
            value = {
              'url': 'https://fixture.invalid/video.mp4',
              'header': {'Referer': 'https://fixture.invalid/'},
            };
          case 'detailContent':
            value = {
              'list': [
                {
                  'vod_id': 'one',
                  'vod_name': '详情',
                  'vod_play_url': '第一集\$token',
                  'vod_play_from': '线路',
                },
              ],
            };
          case 'homeContent':
            value = {
              'class': [
                {'type_id': '1', 'type_name': '电影'},
              ],
            };
          default:
            value = {
              'list': [
                {'vod_id': 'one', 'vod_name': method},
              ],
              'page': 1,
              'pagecount': 2,
            };
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(transport == 'rpc' ? {'ok': true, 'value': value} : value),
        );
        await request.response.close();
      });
      try {
        final input = SourceImportInput.classify(
          jsonEncode({
            'format': 'lume.remote-spider.v1',
            'endpoint': 'http://127.0.0.1:${server.port}/api',
            'transport': transport,
            'metadata': {
              'id': 'remote-$transport',
              'name': '远程$transport',
              'category': 'video',
            },
          }),
          name: 'remote.json',
        );
        expect(input.isScript, isTrue);
        final manager = LumeSources.manager(Section.video);
        final result = await manager.importScript(input.text);
        expect(result.isSuccess, isTrue, reason: result.message);
        final source = (await manager.open(result.descriptor!.id))!;
        expect((await source.categories()).single.title, '电影');
        expect((await source.list(categoryId: '1')).hasMore, isTrue);
        final item = (await source.list(keyword: '搜索')).items.single;
        expect(item.id, 'spider:one');
        expect((await source.detail(item.id))!.title, '详情');
        final ep = (await source.chapters(item.id)).single;
        final media = await source.content(
          itemId: item.id,
          chapterId: ep.id,
        ) as VideoContent;
        expect(media.url.path, '/video.mp4');
        expect(media.headers['Referer'], 'https://fixture.invalid/');
        expect(
          calls,
          containsAll([
            'homeContent',
            'categoryContent',
            'searchContent',
            'detailContent',
            'playerContent',
          ]),
        );
      } finally {
        SourceRegistry.close(Section.video);
        await SectionScope.closeAll();
        await server.close(force: true);
        HttpOverrides.global = saved;
        LumeNet.closeSharedClientForTesting();
        restoreEnginePlatformGate();
        root.deleteSync(recursive: true);
      }
    }, skip: available ? null : 'QuickJS 原生桥不可用');
  }
}
