@Tags(['rex-native-serial'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume_box/core/js/lume_js_engine.dart';
import 'package:lume_box/core/js/rex_widget_host.dart';
import 'package:lume_box/core/js/source_engine.dart';
import 'package:lume_box/core/js/source_registry.dart';
import 'package:lume_box/core/js/source_script.dart';
import 'package:lume_box/core/net/lume_http.dart';
import 'package:lume_box/core/net/network_settings.dart';
import 'package:lume_box/core/reading/reading_library.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/source/source_package.dart';
import 'package:lume_box/core/tmdb/tmdb.dart';

import 'js_sandbox/support/js_sandbox_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final available = installBridge();
  late Directory root;
  final engines = <QuickJsSourceEngine>[];
  setUp(() async {
    enableEngineOnThisPlatform();
    root = Directory.systemTemp.createTempSync('lume_rex');
    await installTempSectionRoot(root);
  });
  tearDown(() async {
    for (final e in engines) {
      e.dispose();
    }
    engines.clear();
    SourceRegistry.close(Section.video);
    SourceEngineRegistry.reset();
    ReadingLibrary.disposeAll();
    await SectionScope.closeAll();
    restoreEnginePlatformGate();
    root.deleteSync(recursive: true);
  });
  Future<QuickJsSourceEngine> open(String raw, {MockClient? client}) async {
    final script = SourcePackage.prepare(raw, name: 'fixture.js');
    final identity = SourceMetadata.parseHeader(script)!.id;
    final engine = QuickJsSourceEngine(
      await LumeJsEngine.create(
        sourceId: identity,
        http: LumeHttp(
          client: client ?? MockClient((_) async => http.Response('{}', 200)),
          settings: const NetworkSettings(maxRetries: 0),
        ),
        section: Section.video,
      ),
    );
    engines.add(engine);
    expect(await engine.loadScript(script), isTrue, reason: engine.loadFailure);
    return engine;
  }

  Future<dynamic> call(
    QuickJsSourceEngine engine,
    String method, [
    Object? args,
  ]) async {
    final result = await engine.callResult(method, args);
    expect(result.isOk, isTrue, reason: result.error?.message);
    return result.value;
  }

  test('真实 QuickJS：词法函数、目录／搜索／详情／选线／HTTP 参数与请求头', () async {
    final requests = <Uri>[];
    final engine = await open(
      r'''
const WidgetMetadata={id:'rex.catalog',title:'测试目录',version:'1',globalParams:[{name:'kind',title:'类型',type:'enumeration',enumOptions:[{title:'电影',value:'movie'},{title:'全部',value:''}]}],modules:[{id:'latest',title:'最新',functionName:'catalog',params:[{name:'page',type:'page'},{name:'count',type:'count',value:1}]}],search:{functionName:'searcher',params:[{name:'keyword',type:'input'}]}};
const catalog=async p=>{const r=await Widget.http.get('https://fixture.invalid/items',{params:p});return r.data;};
const searcher=async p=>[{id:'detail',type:'detail',title:p.keyword,link:'https://fixture.invalid/detail'}];
async function loadDetail(link){return {id:link,title:'详情',episodeItems:[{id:'ep',title:'第一集',videoUrl:'https://media.invalid/a.m3u8',headers:{Referer:'https://fixture.invalid/'}}]};}
''',
      client: MockClient((r) async {
        requests.add(r.url);
        return http.Response(
          jsonEncode([
            {
              'id': 'one',
              'type': 'detail',
              'title': '条目',
              'link': 'https://fixture.invalid/detail',
            },
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    expect((await call(engine, 'categories') as List).single['title'], '最新');
    final page = await call(engine, 'list', {
      'categoryId': 'latest',
      'page': 2,
    });
    expect(page['hasMore'], isTrue);
    expect(requests.single.queryParameters['page'], '2');
    expect(requests.single.queryParameters['kind'], 'movie');
    final filter = (await call(engine, 'filters', {
      'categoryId': 'latest',
    }) as List).single;
    expect(filter['options'].last['id'], isNotEmpty);
    await call(engine, 'list', {
      'categoryId': 'latest',
      'filters': {'kind': filter['options'].last['id']},
    });
    expect(requests.last.queryParameters['kind'], '');
    final item = (await call(engine, 'list', {'keyword': '片名'}))['items'][0];
    expect(item['title'], '片名');
    expect(item['id'], startsWith('rex:'));
    expect((await call(engine, 'detail', {'id': item['id']}))['title'], '详情');
    final chapter =
        (await call(engine, 'chapters', {'id': item['id']}) as List).single;
    final content = await call(engine, 'content', {
      'id': item['id'],
      'chapterId': chapter['id'],
    });
    expect(content['url'], 'https://media.invalid/a.m3u8');
    expect(content['headers']['Referer'], 'https://fixture.invalid/');
  }, skip: available ? null : 'QuickJS 原生桥不可用');

  test('同步存储可立即读取、重开持久化、按源隔离且命名空间缓存跨 Widget', () async {
    String script(String id) =>
        '''
WidgetMetadata={id:'$id',title:'存储',modules:[{id:'loadResource',type:'stream',functionName:'loadResource'}]};
async function loadResource(p){let n=Widget.storage.get('count')||0;Widget.storage.set('count',n+1);if(Widget.storage.get('count')!==n+1)throw new Error('not synchronous');Widget.sharedCache.set('public','count',(Widget.sharedCache.get('public','count')||0)+1);return [{name:'v'+Widget.storage.get('count')+'-'+Widget.sharedCache.get('public','count'),url:'https://media.invalid/a.mp4'}];}
''';
    Future<String> line(QuickJsSourceEngine e) async {
      final item = (await call(e, 'list', {'keyword': '片名'}))['items'][0];
      return ((await call(e, 'chapters', {
        'id': item['id'],
      })) as List).single['title'];
    }

    final a = await open(script('rex.a'));
    expect(await line(a), startsWith('v1-1'));
    a.dispose();
    engines.remove(a);
    final a2 = await open(script('rex.a'));
    expect(await line(a2), startsWith('v2-2'));
    final b = await open(script('rex.b'));
    expect(await line(b), startsWith('v1-3'));
    final library = await ReadingLibrary.open(Section.video);
    expect(
      library.exportSettings().keys.where((k) => k.startsWith('rex.widget.')),
      isEmpty,
    );
  }, skip: available ? null : 'QuickJS 原生桥不可用');

  test('原生导入保存 Widget 参数声明，设置修改下一次调用生效', () async {
    SourceEngineRegistry.register(
      CatEngineKind.quickjs,
      ({required sourceId, required http, required section}) async =>
          QuickJsSourceEngine(
            await LumeJsEngine.create(
              sourceId: sourceId,
              http: http,
              section: section,
            ),
          ),
    );
    final manager = LumeSources.manager(Section.video);
    final result = await manager.importScript('''
WidgetMetadata={id:'rex.config',title:'参数测试',globalParams:[{name:'kind',title:'开关',type:'enumeration',enumOptions:[{title:'启用',value:'enabled'},{title:'禁用',value:'disabled'}]}],modules:[{id:'loadResource',type:'stream',functionName:'loadResource'}]};
async function loadResource(p){return p.kind==='enabled'?[{name:p.seriesName,url:'https://media.invalid/a.mp4'}]:[];}
''');
    expect(result.isSuccess, isTrue, reason: result.message);
    final id = result.descriptor!.id;
    expect(
      RexWidgetSettings.definitions(Section.video, id).first['name'],
      'kind',
    );
    final source = (await manager.open(id))!;
    expect((await source.list(keyword: '影片')).items.length, 1);
    await RexWidgetSettings.saveParameters(Section.video, id, {
      'kind': 'disabled',
    });
    expect((await source.list(keyword: '影片')).items, isEmpty);
  }, skip: available ? null : 'QuickJS 原生桥不可用');

  test('宿主响应支持 JSON、原样文本、Base64、禁止跳转、二进制与 zlib', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/compressed') {
        return http.Response.bytes(
          ZLibEncoder().convert(utf8.encode('{"ok":true}')),
          200,
        );
      }
      if (request.url.path == '/bytes') {
        expect(request.followRedirects, isFalse);
        expect(request.headers['Range'], 'bytes=0-1');
        return http.Response.bytes([0, 255], 206);
      }
      expect(request.body, '{"title":"影片"}');
      expect(request.url.queryParameters['q'], 'a b');
      return http.Response('{"ok":true}', 200);
    });
    final host = RexWidgetHost(
      LumeHttp(client: client, settings: const NetworkSettings(maxRetries: 0)),
      Section.video,
      'unit',
      const Duration(seconds: 3),
    );
    final json = await host.invoke('rex.request', {
      'url': 'https://fixture.invalid/json',
      'method': 'POST',
      'data': {'title': '影片'},
      'params': {'q': 'a b'},
    }) as Map;
    expect(json['data'], {'ok': true});
    final binary = await host.invoke('rex.request', {
      'url': 'https://fixture.invalid/bytes',
      'base64Data': true,
      'allow_redirects': false,
      'headers': {'Range': 'bytes=0-1'},
    }) as Map;
    expect(binary['statusCode'], 206);
    expect(binary['data'], 'AP8=');
    final zip = await host.invoke('rex.request', {
      'url': 'https://fixture.invalid/compressed',
      'zlibMode': true,
    }) as Map;
    expect(zip['data'], {'ok': true});
  });

  test('剧集季集与敏感参数分离：条目和章节身份不携带密钥或请求头，重开重新解析', () async {
    const raw = r'''
WidgetMetadata={id:'rex.private',title:'私密参数',globalParams:[{name:'api_token',type:'input',value:'never-export-this'}],modules:[{id:'loadResource',type:'stream',functionName:'loadResource'}]};
async function loadResource(p){return [{name:p.type+'-'+p.season+'-'+p.episode,url:'https://media.invalid/a.mp4',headers:{Authorization:'Bearer '+p.api_token}}];}
''';
    final first = await open(raw);
    final item = (await call(first, 'list', {
      'keyword': '示例 S02E03',
    }))['items'][0];
    expect(
      Uri.decodeComponent(item['id']),
      isNot(contains('never-export-this')),
    );
    expect(Uri.decodeComponent(item['id']), isNot(contains('api_token')));
    final chapter =
        ((await call(first, 'chapters', {'id': item['id']})) as List).single;
    expect(chapter['title'], startsWith('tv-2-3'));
    expect(
      Uri.decodeComponent(chapter['id']),
      isNot(contains('Authorization')),
    );
    first.dispose();
    engines.remove(first);
    final reopened = await open(raw);
    final content = await call(reopened, 'content', {
      'itemId': item['id'],
      'chapterId': chapter['id'],
    });
    expect(content['headers']['Authorization'], 'Bearer never-export-this');
    expect(
      (await ReadingLibrary.open(Section.video)).exportSettings().toString(),
      isNot(contains('never-export-this')),
    );
  }, skip: available ? null : 'QuickJS 原生桥不可用');

  test('Widget HTML 支持等待加载及常用查询／遍历链', () async {
    final engine = await open(r'''
WidgetMetadata={id:'rex.html',title:'HTML',modules:[{id:'cards',title:'卡片',functionName:'loadCards'}]};
async function loadCards(){const $=await Widget.html.load('<div class="card"><a href="https://media.invalid/a.mp4"><span>视频一</span></a></div>');const items=[];$('.card').each((i,el)=>{const link=$(el).find('a').first();items.push({id:link.attr('href'),type:'url',title:link.find('span').text()});});return items;}
''');
    final item = (await call(engine, 'list', {
      'categoryId': 'cards',
    }))['items'][0];
    expect(item['title'], '视频一');
    final chapter =
        ((await call(engine, 'chapters', {'id': item['id']})) as List).single;
    expect(
      (await call(engine, 'content', {'chapterId': chapter['id']}))['url'],
      'https://media.invalid/a.mp4',
    );
  }, skip: available ? null : 'QuickJS 原生桥不可用');

  test('Widget TMDB 沿用宿主配置；脚本不能把宿主密钥发送到自选 URL', () async {
    final settings = TmdbSettings.instance;
    final old = (settings.enabled, settings.apiKey, settings.apiProxy);
    addTearDown(() {
      settings.enabled = old.$1;
      settings.apiKey = old.$2;
      settings.apiProxy = old.$3;
    });
    settings.enabled = true;
    settings.apiKey = 'fixture-host-key';
    settings.apiProxy = 'https://tmdb.fixture.invalid';
    var requests = 0;
    final host = RexWidgetHost(
      LumeHttp(
        client: MockClient((request) async {
          requests++;
          expect(request.url.host, 'tmdb.fixture.invalid');
          expect(request.url.path, '/3/trending/movie/day');
          expect(request.url.queryParameters['api_key'], 'fixture-host-key');
          expect(request.url.queryParameters['page'], '2');
          return http.Response('{"results":[]}', 200);
        }),
      ),
      Section.video,
      'tmdb',
      const Duration(seconds: 3),
    );
    final result = await host.invoke('rex.tmdb', {
      'api': '/3/trending/movie/day',
      'params': {'page': 2, 'api_key': 'script-override'},
    });
    expect(result, {'results': []});
    expect(result.toString(), isNot(contains('fixture-host-key')));
    await expectLater(
      host.invoke('rex.tmdb', {'api': 'https://other.invalid/path'}),
      throwsA(isA<Exception>()),
    );
    expect(requests, 1);
  });
}
