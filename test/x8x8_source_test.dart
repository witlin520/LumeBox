import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/js/lume_js_engine.dart';
import 'package:lume_box/core/js/qjs_bindings.dart';
import 'package:lume_box/core/js/sandbox/sandbox.dart';
import 'package:lume_box/core/net/lume_http.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/source.dart';

import 'support/source_scripts.dart';

/// 8x8x（www.8x8x.fun / 跳板域）：**外壳 + bodyRoot + AES-256-GCM 推荐流**的成人站，用真站点快照跑。
///
/// 站点结构（2026-10-29 复测）：
///   1. 跳板域 302 到真实域；真实域根页面只有 `<script data-body-url=/4rov3/>`，
///      内容页全在 `/<bodyRoot>/...`（正文是服务端渲染，站点根路径会被 SPA 兜底 302 到首页）；
///   2. 推荐流 `/json/recommend/rmd_N` 是 AES-256-GCM 密文（key 由 base64+异或派生），
///      这个用例跑的是源内纯 JS 实现（沙箱没有 crypto/atob）；
///   3. 分类/标签页是 SSR：卡片 `<a href=/vd/123/ class="card group">` + `data-src` 封面 +
///      `<div class=card-title>`，分页 `第 X / Y 页`（23 张/页）；
///   4. 详情页给 `data-m3u8` + `data-route1..3`，播放串 = route + m3u8；线路2 换到另一台媒体机。
void main() {
  final bridge = _resolveBridge();
  if (bridge != null) {
    Qjs.overrideLibrary(bridge);
    Qjs.reclaimRuntime = false;
  }

  String? skipUnless(List<String> names) => Qjs.isAvailable
      ? _skipUnless(names)
      : '未找到可用的 quickjs 原生桥（${Qjs.availabilityDetail}）';

  setUp(() => LumeJsEngine.debugSupportedOverride = true);
  tearDown(() => LumeJsEngine.debugSupportedOverride = null);

  const assets = <String>[
    '8x8x.js',
    'x8x8_shell.html',
    'x8x8_home.html',
    'x8x8_category1.html',
    'x8x8_category1_p2.html',
    'x8x8_tag.html',
    'x8x8_detail.html',
    'x8x8_search.json',
    'x8x8_recommend.txt',
    'x8x8_master.m3u8',
  ];

  test(
    '8x8x：外壳/bodyRoot / 分类 / 标签筛选 / 排序 / 搜索 / 详情 / 三线路（站点快照）',
    () async {
      final http = _RouteHttp(<String, String>{
        '/4rov3/category/1/page/2/': _read('x8x8_category1_p2.html'),
        '/4rov3/category/1/': _read('x8x8_category1.html'),
        '/4rov3/tags/AI%E7%9F%AD%E5%89%A7/': _read('x8x8_tag.html'),
        '/4rov3/vd/68005/': _read('x8x8_detail.html'),
        '/4rov3/': _read('x8x8_home.html'),
        '/json/recommend/rmd_1': _read('x8x8_recommend.txt'),
        '/api/search/video': _read('x8x8_search.json'),
        '/': _read('x8x8_shell.html'),
      }, media: _read('x8x8_master.m3u8'));
      final source = await _boot(
        _script('8x8x.js'),
        section: Section.video,
        http: http,
      );
      addTearDown(source.dispose);

      // ---- 分类：推荐 + 5 个频道（从导航实时抓）。
      final categories = await source.data.categories();
      expect(
        categories.map((category) => category.id).toList(),
        <String>['rec', '1', '2', '3', '4', '5'],
      );
      expect(
        categories.map((category) => category.title).toList(),
        <String>['推荐', '大陆', '日韩', '欧美', '动漫', '三级'],
      );

      // ---- 筛选：排序 + 12 个标签组（站点导航里的标签）。
      final filters = await source.data.filters();
      expect(filters.length, 13);
      expect(filters.first.id, 'sort');
      expect(
        filters.first.options.map((option) => option.id).toList(),
        <String>['new', 'rec'],
      );
      expect(
        filters.map((group) => group.title),
        containsAll(<String>['年龄', '职业', '剧情', '姿势', '场景']),
      );
      final age = filters.firstWhere((group) => group.id == 'tag1');
      expect(
        age.options.take(3).map((option) => option.id).toList(),
        <String>['AI短剧', '年轻萝莉', '人妻熟女'],
      );

      // ---- 首页：推荐（加密 JSON）+ 最新大陆（SSR）。
      final home = await source.data.home();
      expect(home.isBoards, isTrue);
      expect(
        home.boards.map((board) => board.title).toList(),
        <String>['推荐', '最新 · 大陆'],
      );
      expect(home.boards.first.items.length, 11);
      expect(home.boards.first.items.first.id, '66560');
      expect(home.boards.first.items.first.cover, startsWith('https://1vbyhq4.9zbtan36.com/'));
      expect(home.boards.last.moreUrl, '1');
      expect(home.boards.last.items.length, 12);

      // ---- 分类列表：23 张/页，分页信息来自「第 X / Y 页」。
      final page1 = await source.data.list(categoryId: '1', page: 1);
      expect(page1.items.length, 23);
      expect(page1.hasMore, isTrue);
      expect(page1.items.first.id, '68005');
      expect(page1.items.first.subtitle ?? '', '', reason: '频道列表不回填副标题');
      expect(page1.items.first.cover, startsWith('https://1vbyhq4.9zbtan36.com/'));

      final page2 = await source.data.list(categoryId: '1', page: 2);
      expect(page2.items.first.id, '67962', reason: '第 2 页要真的取 /page/2/');

      // ---- 标签筛选：站点只认单标签，走 /tags/<标签>/。
      final tagged = await source.data.list(
        categoryId: '1',
        page: 1,
        filters: const <String, String>{'tag1': 'AI短剧'},
      );
      expect(tagged.items.length, 23);
      expect(tagged.items.first.id, '67931');
      expect(tagged.items.first.subtitle, '标签 · AI短剧');

      // ---- 排序=推荐：走首页推荐流（全局）。
      final recommended = await source.data.list(
        categoryId: '1',
        page: 1,
        filters: const <String, String>{'sort': 'rec'},
      );
      expect(recommended.items.length, 11);
      expect(recommended.items.first.id, '66560');

      // ---- 搜索：/api/search/video（明文 JSON，28 条/页）。
      final searched = await source.data.list(keyword: '内射', page: 1);
      expect(searched.items.length, 28);
      expect(searched.hasMore, isTrue);
      expect(searched.items.first.id, '60231');
      expect(searched.items.first.subtitle, contains('大陆'));

      // ---- 详情：标题/封面/标签都来自详情页 SSR。
      final detail = await source.data.detail('68005');
      expect(detail, isNotNull);
      expect(detail!.title, contains('绝艳舒淇'));
      expect(detail.cover, startsWith('https://1vbyhq4.9zbtan36.com/'));
      expect(detail.subtitle, contains('大陆'));

      // ---- 选集：三条媒体线路。
      final chapters = await source.data.chapters('68005');
      expect(
        chapters.map((chapter) => chapter.title).toList(),
        <String>['线路1', '线路2', '线路3'],
      );

      // ---- 播放：route + data-m3u8；换线路就是换媒体机。
      final content = await source.data.content(itemId: '68005', chapterId: '1');
      expect(content, isA<VideoContent>());
      final video = content! as VideoContent;
      expect(
        video.url.toString(),
        'https://xn0cox.db9bmbe.com:32803/v/127a4c4e77eaf5fc09c89b1413aebe68/m3u8/index.m3u8',
      );
      expect(video.headers['Referer'], 'https://8x.vip/');

      final second = await source.data.content(itemId: '68005', chapterId: '2');
      expect(
        (second! as VideoContent).url.toString(),
        startsWith('https://woyaw00.cxjaa9s8.com:1443/v/'),
      );
    },
    skip: skipUnless(assets),
    timeout: const Timeout(Duration(seconds: 120)),
  );
}

/// 按路径精确分发快照；媒体线路（:32803 / :1443）统一给 master 清单。
class _RouteHttp extends LumeHttp {
  _RouteHttp(this.routes, {required this.media}) : super();

  final Map<String, String> routes;
  final String media;

  /// 每次请求的地址（断言路由用）。
  final List<String> paths = <String>[];

  @override
  Future<LumeHttpResponse> send({
    required String url,
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
    int? maxBytes,
    Duration? timeout,
  }) async {
    paths.add(url);
    String? payload;
    if (url.contains(':32803/v/') || url.contains(':1443/v/')) {
      payload = media;
    } else {
      final uri = Uri.tryParse(url);
      final path = uri == null ? url : uri.path;
      payload = routes[path];
    }
    if (payload == null) {
      return LumeHttpResponse(
        statusCode: 404,
        body: Uint8List.fromList(utf8.encode('not found: $url')),
        headers: const <String, String>{},
      );
    }
    return LumeHttpResponse(
      statusCode: 200,
      body: Uint8List.fromList(utf8.encode(payload)),
      headers: const <String, String>{'content-type': 'text/html; charset=utf-8'},
    );
  }
}

class _SandboxRuntime implements JsSourceRuntime {
  _SandboxRuntime(this._sandbox);

  final LumeSandbox _sandbox;

  @override
  Future<Set<String>> contractMethods() async => const <String>{
        'categories',
        'filters',
        'list',
        'detail',
        'chapters',
        'content',
        'home',
      };

  @override
  Future<Object?> call(String method, [Object? argument]) async {
    final result = await _sandbox.call('LumeSource.$method', argument);
    if (result.isOk) return result.value;
    throw SourceException(SourceErrorKind.callFailed, result.error!.toString());
  }
}

String _read(String file) {
  final direct = File(file);
  if (direct.existsSync()) return direct.readAsStringSync();
  final path = sourceAssetPath(file);
  if (path == null) {
    throw StateError('缓存里没有 $file（先跑 `dart run tool/fetch_sources.dart`）');
  }
  return File(path).readAsStringSync();
}

String _script(String name) => sourceScriptPath(name)!;

String? _skipUnless(List<String> names) {
  for (final name in names) {
    if (sourceAssetPath(name) == null) return sourceScriptsSkipReason(name);
  }
  return null;
}

Future<_BootedSource> _boot(
  String scriptPath, {
  required Section section,
  required LumeHttp http,
}) async {
  final script = _read(scriptPath);
  final host = LumeSourceHost(
    http,
    timeout: const Duration(seconds: 10),
    section: section,
    sourceId: 'snapshot',
  );
  final sandbox = LumeSandbox.create(
    id: host.expectedSandboxId,
    policy: LumeJsEngine.policy.copyWith(allowHostAccess: true),
    host: host,
    polyfills: LumeSourcePolyfills.forSection(section),
  );
  final loaded = await sandbox.load(script);
  expect(loaded.isOk, isTrue, reason: '脚本必须能载入: $scriptPath: ${loaded.error}');
  return _BootedSource(
    data: JsDataSource(
      id: 'snapshot',
      name: 'snapshot',
      section: section,
      runtime: _SandboxRuntime(sandbox),
    ),
    dispose: () {
      sandbox.dispose();
      host.dispose();
    },
  );
}

class _BootedSource {
  _BootedSource({required this.data, required this.dispose});

  final JsDataSource data;
  final void Function() dispose;
}

DynamicLibrary? _resolveBridge() {
  if (!Platform.isWindows) {
    try {
      return DynamicLibrary.process();
    } catch (_) {
      return null;
    }
  }
  for (final config in <String>['Debug', 'Release', 'Profile']) {
    final file = File(
      '${Directory.current.path}/build/windows/x64/runner/$config/'
      'quickjs_c_bridge_plugin.dll',
    );
    if (!file.existsSync()) continue;
    try {
      return DynamicLibrary.open(file.absolute.path);
    } catch (_) {
      continue;
    }
  }
  return null;
}
