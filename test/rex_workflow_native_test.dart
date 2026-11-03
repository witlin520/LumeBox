@Tags(['rex-native-serial'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/js/lume_js_engine.dart';
import 'package:lume_box/core/js/source_engine.dart';
import 'package:lume_box/core/js/source_registry.dart';
import 'package:lume_box/core/reading/reading_library.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source.dart';

import 'js_sandbox/support/js_sandbox_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final available = installBridge();
  late Directory root;
  setUp(() async {
    enableEngineOnThisPlatform();
    root = Directory.systemTemp.createTempSync('rex_workflow');
    await installTempSectionRoot(root);
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
  });
  tearDown(() async {
    SourceRegistry.close(Section.video);
    SourceEngineRegistry.reset();
    ReadingLibrary.disposeAll();
    await SectionScope.closeAll();
    restoreEnginePlatformGate();
    root.deleteSync(recursive: true);
  });

  Future<DataSource> import(String text) async {
    final manager = LumeSources.manager(Section.video);
    final result = await manager.importScript(text);
    expect(result.isSuccess, isTrue, reason: result.message);
    return (await manager.open(result.descriptor!.id))!;
  }

  test('明文样板经真实导入：分页、搜索、详情、演员、两线路六集、播放', () async {
    final source = await import(
      File('assets/rex/lumebox_demo.js').readAsStringSync(),
    );
    expect((await source.categories()).single.id, 'films');
    final list = await source.list(page: 1);
    expect(list.items, hasLength(2));
    expect((await source.list(page: 2)).items, isEmpty);
    final found = (await source.list(keyword: 'Bunny')).items.single;
    expect((await source.list(keyword: '不存在的作品')).items, isEmpty);
    final detail = (await source.detail(found.id))!;
    expect(detail.description, contains('Blender'));
    expect(detail.backdrop, contains('/lumebox-rex-bunny/'));
    expect(detail.cover, contains('/lumebox-rex-bunny/'));
    expect(detail.cast.single.name, '演示角色');
    expect(detail.cast.single.avatar, isNotEmpty);
    final chapters = await source.chapters(found.id);
    expect(chapters, hasLength(6));
    expect(chapters.map((c) => c.line).toSet(), {'HLS 主线路', 'HLS 备用入口'});
    expect(chapters.every((c) => c.cover?.isNotEmpty == true), isTrue);
    final content =
        (await source.content(itemId: found.id, chapterId: chapters[4].id))!
            as VideoContent;
    expect(
      content.url.toString(),
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8?route=backup',
    );
  }, skip: available ? null : 'QuickJS 原生桥不可用');

  test('URL详情按字符串link调用并缓存；竖图/详情图/横图分别映射且保留图片头', () async {
    final source = await import(r'''
WidgetMetadata={id:'workflow.fields',title:'字段回归',modules:[{id:'list',functionName:'list'}]};
async function list(){return [{id:'a',type:'url',title:'列表',link:'owned:a',coverUrl:'https://images.invalid/fallback',posterUrl:'https://images.invalid/poster'}];}
async function loadDetail(link){
  if(link !== 'owned:a')throw new Error('wrong link');
  var calls=Widget.storage.get('calls')||0;if(calls>0)throw new Error('detail called twice');Widget.storage.set('calls',calls+1);
  return {title:'详情',detailPoster:'https://images.invalid/detail',backdropPath:'https://images.invalid/backdrop',
    headers:{Referer:'https://owned.invalid/'},peoples:[{id:7,title:'演员',avatar:'https://images.invalid/avatar',role:'主演'}],
    episodeItems:[{title:'第一集',videoUrl:'https://media.invalid/a.mp4'}]};
}
''');
    final item = (await source.list()).items.single;
    expect(item.cover, 'https://images.invalid/poster');
    final detail = (await source.detail(item.id))!;
    expect(detail.title, '详情');
    expect(detail.cover, 'https://images.invalid/detail');
    expect(detail.backdrop, 'https://images.invalid/backdrop');
    expect(detail.coverHeaders['Referer'], 'https://owned.invalid/');
    expect(detail.cast.single.role, '主演');
    expect((await source.chapters(item.id)).single.title, '第一集');
    // Caching must be shared by detail and chapters, not call the handler twice.
  }, skip: available ? null : 'QuickJS 原生桥不可用');

  test('临时播放地址在起播重新解析，线路名与剧集身份保持对应', () async {
    final source = await import(r'''
WidgetMetadata={id:'workflow.refresh',title:'动态线路',modules:[{id:'loadResource',type:'stream',functionName:'resource'}]};
async function resource(p){var n=Widget.storage.get('calls')||0;Widget.storage.set('calls',++n);
 return [{name:'主线路',url:'https://media.invalid/movie.mp4?call='+n,customHeaders:{Referer:'https://owned.invalid/'}}];}
''');
    final item = (await source.list(keyword: '演示片')).items.single;
    final chapter = (await source.chapters(item.id)).single;
    final first =
        (await source.content(itemId: item.id, chapterId: chapter.id))!
            as VideoContent;
    final second =
        (await source.content(itemId: item.id, chapterId: chapter.id))!
            as VideoContent;
    expect(first.url.toString(), endsWith('call=2'));
    expect(second.url.toString(), endsWith('call=3'));
    expect(second.headers['Referer'], 'https://owned.invalid/');
  }, skip: available ? null : 'QuickJS 原生桥不可用');
}
