import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/net/lume_net.dart';

import 'support/js_sandbox_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = installBridge() ? null : 'QuickJS 原生桥不可用';
  late Directory root;
  setUp(() async {
    enableEngineOnThisPlatform();
    root = Directory.systemTemp.createTempSync('venera-compat');
    await installTempSectionRoot(root);
  });
  tearDown(() async {
    LumeNet.closeSharedClientForTesting();
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await SectionScope.closeAll();
    root.deleteSync(recursive: true);
  });

  test('旧版分区首页字典、两种更多跳转与列表展开', () async {
    final engine = await openEngine(
      sourceId: 'venera-home-shapes',
      section: Section.comic,
      script: r'''
class HomeShapes extends ComicSource {
 key='home-shapes'; name='Home'; version='1';
 explore=[
  {title:'旧首页',type:'singlePageWithMultiPart',load:async page=>{
    if(page!==null) throw Error('wrong page');
    return {'最新':[{id:'1',title:'作品'}], '热门':[{id:'2',title:'作品2'}]};
  }},
  {title:'新首页',type:'multiPartPage',load:async()=>[
   {title:'分类',comics:[{id:'3',title:'作品3'}],viewMore:'category:汉化@/albums-index-cate-1.html'},
   {title:'分类2',comics:[{id:'4',title:'作品4'}],viewMore:{page:'category',attributes:{category:'全彩',param:'color'}}}
  ]}
 ];
 categoryComics={load:async(category,param,options,page)=>({comics:[{id:'more',title:category+'|'+param+'|'+page}],maxPage:3})};
}
''',
    );
    addTearDown(engine.dispose);
    final home = await engine.callResult('home');
    expect(home.isOk, true, reason: home.error?.message);
    final boards = (home.value as Map)['boards'] as List;
    expect(boards.map((b) => b['title']), ['最新', '热门', '分类', '分类2']);
    for (var i = 2; i < 4; i++) {
      final more = await engine.callResult('list', {
        'categoryId': boards[i]['moreUrl'],
        'page': 2,
      });
      expect(more.isOk, true, reason: more.error?.message);
      expect(
        ((more.value as Map)['items'] as List).single['title'],
        i == 2 ? '汉化|/albums-index-cate-1.html|2' : '全彩|color|2',
      );
    }
    final list = await engine.callResult('list', {'categoryId': 'explore:0'});
    expect(((list.value as Map)['items'] as List).length, 2);
  }, skip: skip);

  test('loadNext 首页和搜索游标按查询隔离，缺失页可重放且末页停止', () async {
    final engine = await openEngine(
      sourceId: 'venera-cursors',
      section: Section.comic,
      script: r'''
class Cursors extends ComicSource {
 key='cursors';name='Cursors';version='1';
 explore=[{title:'最新',type:'multiPageComicList',loadNext:async next=>({comics:[{id:next||'first',title:next||'first'}],next:next?null:'second'})}];
 search={loadNext:async(keyword,options,next)=>({comics:[{id:keyword,title:keyword+':'+(next||'first')}],next:next?null:keyword+'-next'})};
}
''',
    );
    addTearDown(engine.dispose);
    final home = await engine.callResult('home');
    expect(((home.value as Map)['boards'] as List).length, 1);
    for (final keyword in ['A', 'B']) {
      final result = await engine.callResult('list', {
        'keyword': keyword,
        'page': 2,
      });
      expect(result.isOk, true, reason: result.error?.message);
      expect(
        ((result.value as Map)['items'] as List).single['title'],
        '$keyword:$keyword-next',
      );
      expect((result.value as Map)['hasMore'], false);
    }
    final last = await engine.callResult('list', {
      'categoryId': 'explore:0',
      'page': 2,
    });
    expect(((last.value as Map)['items'] as List).single['id'], 'second');
    final exhausted = await engine.callResult('list', {
      'categoryId': 'explore:0',
      'page': 3,
    });
    expect((exhausted.value as Map)['items'], isEmpty);
  }, skip: skip);

  test('同步结构化缓存和脚本 Cookie 初始化兼容，Cookie 不越域或越路径', () async {
    final engine = await openEngine(
      sourceId: 'venera-sync-data',
      section: Section.comic,
      script: r'''
class DataFixture extends ComicSource {
 key='sync-data';name='Data';version='1';
 init(){
  if(this.loadData('missing')!==null) throw Error('missing');
  this.saveData('cache',{titles:['一','二'],page:2});
  Network.setCookies('https://www.example.test/',[
   new Cookie({name:'locale',value:'zh',domain:'example.test',path:'/comic',secure:true}),
   new Cookie({name:'hostOnly',value:'1'})
  ]);
 }
 probe(){return {cache:this.loadData('cache'),sync:!(this.loadData('cache') instanceof Promise),
  own:Network.getCookies('https://www.example.test/comic/1').map(c=>c.name),
  sibling:Network.getCookies('https://m.example.test/comic/1').map(c=>c.name),
  other:Network.getCookies('https://other.test/comic/1'),
  path:Network.getCookies('https://m.example.test/comics/1'),
  insecure:Network.getCookies('http://m.example.test/comic/1')};}
}
''',
    );
    addTearDown(engine.dispose);
    final result = await engine.callResult('probe');
    expect(result.isOk, true, reason: result.error?.message);
    final value = result.value as Map;
    expect(value['cache'], {
      'titles': ['一', '二'],
      'page': 2,
    });
    expect(value['sync'], true);
    expect(value['own'], ['locale', 'hostOnly']);
    expect(value['sibling'], ['locale']);
    for (final key in ['other', 'path', 'insecure']) {
      expect(value[key], isEmpty);
    }
  }, skip: skip);

  test('绅士漫画默认旧域名受阻时用发布页的可用镜像，跳过发布页自身', () async {
    final engine = await openEngine(
      sourceId: 'venera-wnacg-mirrors',
      section: Section.comic,
      script: r'''
globalThis.fetch=async url=>({status:url.includes('wnacg.com')?403:200,body:url.includes('release.test')?'release':'<div class="gallary_wrap">ready</div>'});
class WnacgFixture extends ComicSource {
 key='wnacg';name='WNACG';version='1';
 static domains=['release.test','mirror.test'];
 settings={domain0:{default:'wnacg.com'},domainSelection:{default:'0'}};
 get baseUrl(){return 'https://'+(Number(this.loadSetting('domainSelection'))===0?this.loadSetting('domain0'):WnacgFixture.domains[Number(this.loadSetting('domainSelection'))-1]);}
 async probe(){const result=await Network.get(this.baseUrl,{});return {status:result.status,base:this.baseUrl};}
}
''',
    );
    addTearDown(engine.dispose);
    final result = await engine.callResult('probe');
    expect(result.isOk, true, reason: result.error?.message);
    expect(result.value, {'status': 200, 'base': 'https://mirror.test'});
  }, skip: skip);

  test('HTML 重复属性取首值，Map 和数组目录与单本正文保持阅读入口', () async {
    final engine = await openEngine(
      sourceId: 'venera-reader-shapes',
      section: Section.comic,
      script: r'''
class ReaderShapes extends ComicSource {
 key='reader-shapes';name='Reader';version='1';
 comic={
  loadInfo:async id=>({title:'作品',chapters:id==='single'?null:id==='array'?[{id:'a',title:'数组话'}]:new Map([['第一卷',new Map([['2','第二话'],['1','第一话']])]])}),
  loadEp:async(id,ep)=>{if(id==='single'&&ep!==null)throw Error('single ep must be null');return {images:['https://img.test/page.jpg']};}
 };
 probe(){const doc=new HtmlDocument('<div class="title_sort" class="cc"><div class="bodywrap" CLASS="other">内容</div></div>');return {titles:doc.querySelectorAll('div.title_sort').length,bodies:doc.querySelectorAll('div.bodywrap').length};}
}
''',
    );
    addTearDown(engine.dispose);
    final html = await engine.callResult('probe');
    expect(html.value, {'titles': 1, 'bodies': 1});
    final map = await engine.callResult('chapters', {'id': 'map'});
    expect(map.value, [
      {'id': '2', 'title': '第二话'},
      {'id': '1', 'title': '第一话'},
    ]);
    final array = await engine.callResult('chapters', {'id': 'array'});
    expect(array.value, [
      {'id': 'a', 'title': '数组话'},
    ]);
    final single = await engine.callResult('chapters', {'id': 'single'});
    final chapter = (single.value as List).single as Map;
    final content = await engine.callResult('content', {
      'id': 'single',
      'chapterId': chapter['id'],
    });
    expect(content.isOk, true, reason: content.error?.message);
    expect((content.value as Map)['images'], ['https://img.test/page.jpg']);
  }, skip: skip);

  test('部分首页模块失败保留成功内容，全部失败保留真实错误', () async {
    final engine = await openEngine(
      sourceId: 'venera-partial-home',
      section: Section.comic,
      script: r'''
class PartialHome extends ComicSource {
 key='partial';name='Partial';version='1';
 explore=[{title:'失败',load(){throw Error('site unavailable');}},{title:'可用',load:async()=>({comics:[{id:'1',title:'作品'}]})}];
 failAll(){this.explore.pop();}
}
''',
    );
    addTearDown(engine.dispose);
    final home = await engine.callResult('home');
    expect(home.isOk, true, reason: home.error?.message);
    expect(((home.value as Map)['boards'] as List).single['title'], '可用');
    await engine.callResult('failAll');
    final failed = await engine.callResult('home');
    expect(failed.isOk, false);
    expect(failed.error?.message, contains('site unavailable'));
  }, skip: skip);

  test('官方二进制编码与同步摘要、HMAC 使用标准向量', () async {
    final engine = await openEngine(
      sourceId: 'venera-crypto',
      section: Section.comic,
      script: r'''
class CryptoFixture extends ComicSource {
  key = 'crypto-fixture'; name = 'Crypto'; version = '1';
  probe() {
    const bytes = Convert.encodeUtf8('abc');
    const binary = new Uint8Array([0, 255, 128, 65]).buffer;
    return {
      binary: bytes instanceof ArrayBuffer,
      md5: Convert.hexEncode(Convert.md5(bytes)),
      sha1: Convert.hexEncode(Convert.sha1(bytes)),
      sha256: Convert.hexEncode(Convert.sha256(bytes)),
      hmac: Convert.hmacString(Convert.encodeUtf8('key'), Convert.encodeUtf8('The quick brown fox jumps over the lazy dog'), 'sha256'),
      roundtrip: Convert.hexEncode(Convert.decodeBase64(Convert.encodeBase64(binary))),
      utf8: Convert.decodeUtf8(Convert.encodeUtf8('漫画😀'))
    };
  }
}
''',
    );
    addTearDown(engine.dispose);
    final result = await engine.callResult('probe');
    expect(result.isOk, isTrue, reason: result.error?.message);
    final value = result.value as Map;
    expect(value['binary'], true);
    expect(value['md5'], '900150983cd24fb0d6963f7d28e17f72');
    expect(value['sha1'], 'a9993e364706816aba3e25717850c26c9cd0d89d');
    expect(
      value['sha256'],
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      value['hmac'],
      'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8',
    );
    expect(value['roundtrip'], '00ff8041');
    expect(value['utf8'], '漫画😀');
  }, skip: skip);

  test('多模块首页封面与分类筛选映射到真实 Venera 参数', () async {
    final engine = await openEngine(
      sourceId: 'venera-facets',
      section: Section.comic,
      script: r'''
class FacetFixture extends ComicSource {
  key = 'facet-fixture'; name = 'Facets'; version = '1';
  explore = [{title: '推荐', type: 'multiPartPage', load: async (page) => {
    if (page !== null) throw new Error('multiPartPage 必须接收 null');
    return [{title: '最新', comics: [{id:'1', title:'封面', cover:'https://img.example/a.jpg'}]}];
  }}];
  category = {parts: [{categories: ['全部'], groupParam: 'all'}]};
  categoryComics = {
    optionList: [{label: '排序', options: ['new-最新', 'hot-热门']}],
    load: async (category, param, options, page) => ({comics: [{id: '2', title: param + ':' + options[0]}], maxPage: 3})
  };
}
''',
    );
    addTearDown(engine.dispose);
    final home = await engine.callResult('home');
    expect(home.isOk, true, reason: home.error?.message);
    final boards = (home.value as Map)['boards'] as List;
    expect((boards.first as Map)['title'], '最新');
    expect(
      (((boards.first as Map)['items'] as List).first as Map)['cover'],
      'https://img.example/a.jpg',
    );
    final filters = await engine.callResult('filters');
    expect(((filters.value as List).first as Map)['title'], '排序');
    final list = await engine.callResult('list', {
      'categoryId': 'category:0:0',
      'page': 1,
      'filters': {'venera:0': 'hot'},
    });
    expect(list.isOk, true, reason: list.error?.message);
    expect(
      (((list.value as Map)['items'] as List).first as Map)['title'],
      'all:hot',
    );
    final explore = await engine.callResult('list', {
      'categoryId': 'explore:0',
    });
    expect(((explore.value as Map)['items'] as List), hasLength(1));
  }, skip: skip);

  test('官方 comic 对象与图片钩子保留封面和章节的独立请求头', () async {
    final engine = await openEngine(
      sourceId: 'venera-image-headers',
      section: Section.comic,
      script: r'''
class ImageFixture extends ComicSource {
  key = 'image-fixture'; name = 'Images'; version = '1';
  explore = [{title:'推荐', load:async()=>({comics:[new Comic({id:'1',title:'作品',cover:'https://img.example/cover.jpg'})]})}];
  comic = {
    loadInfo: async()=>new ComicDetails({title:'作品', cover:'https://img.example/cover.jpg', chapters:{ep:'第一话'}}),
    loadEp: async()=>({images:['https://img.example/page.jpg']}),
    onThumbnailLoad: url=>new ImageLoadingConfig({url:url,headers:{Referer:'https://site.example/'}}),
    onImageLoad: (url,id,ep)=>new ImageLoadingConfig({url:url,headers:{Referer:'https://site.example/'+id+'/'+ep,Cookie:'image=ok'}})
  };
}
''',
    );
    addTearDown(engine.dispose);
    final list = await engine.callResult('list');
    expect(list.isOk, true, reason: list.error?.message);
    final item = (((list.value as Map)['items'] as List).first as Map);
    expect((item['coverHeaders'] as Map)['Referer'], 'https://site.example/');
    final detail = await engine.callResult('detail', {'id': '1'});
    expect(detail.isOk, true, reason: detail.error?.message);
    expect(
      ((detail.value as Map)['coverHeaders'] as Map)['Referer'],
      'https://site.example/',
    );
    final content = await engine.callResult('content', {
      'id': '1',
      'chapterId': 'ep',
    });
    expect(content.isOk, true, reason: content.error?.message);
    final headers =
        ((content.value as Map)['imageHeaders']
                as Map)['https://img.example/page.jpg']
            as Map;
    expect(headers['Referer'], 'https://site.example/1/ep');
    expect(headers['Cookie'], 'image=ok');
  }, skip: skip);

  test('Network.fetchBytes 保留非 UTF8 字节并支持官方方法签名', () async {
    final saved = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = saved);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final bytes = await request.fold<List<int>>(
        [],
        (all, part) => all..addAll(part),
      );
      expect(bytes, [0, 255, 128, 65]);
      expect(request.headers.value('referer'), 'https://comic.example/');
      request.response.add(bytes);
      await request.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}/image';
    final engine = await openEngine(
      sourceId: 'venera-bytes',
      section: Section.comic,
      script:
          '''
class BytesFixture extends ComicSource {
  key = 'bytes-fixture'; name = 'Bytes'; version = '1';
  async probe() {
    const bytes = new Uint8Array([77, 0, 255, 128, 65, 88]).subarray(1, 5);
    const result = await Network.fetchBytes('POST', '$url', {'Referer':'https://comic.example/'}, bytes);
    const posted = await Network.post('$url', {'Referer':'https://comic.example/'}, bytes);
    return {status: result.status, bytes: Convert.hexEncode(result.body), binary: result.body instanceof ArrayBuffer, posted: posted.status};
  }
}
''',
    );
    addTearDown(engine.dispose);
    final result = await engine.callResult('probe');
    expect(result.isOk, true, reason: result.error?.message);
    expect((result.value as Map)['status'], 200);
    expect((result.value as Map)['bytes'], '00ff8041');
    expect((result.value as Map)['binary'], true);
    expect((result.value as Map)['posted'], 200);
  }, skip: skip);
}
