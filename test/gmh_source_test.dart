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

/// G社漫画（g-mh.org）：从仓库历史恢复的源，用真快照在**真 QuickJS 沙箱**里跑一遍。
///
/// 这个源的核心风险不在解析，而在两件「只有在沙箱里才成立/不成立」的事：
///   1. **正文图片是加密的**：站点用 `/assets/runtime/chapter-decoder.js` 里的
///      混淆解码器还原（`window.__cimg.r(串)`）。源脚本把这份解码器取回来、配上
///      最小浏览器垫片、在**本源上下文里 eval**——所以这个用例必须真跑一次 eval，
///      否则「Node 里能解、QuickJS 里报错」这类问题根本发现不了。
///   2. 作品页（Astro 静态壳）本身不带章节，章节来自自建接口 `v2.apikk.top`；
///      `data-mid` 只写在作品页上，取不到它就整条链断掉。
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
    'G社漫画.js',
    'gmh_list.html',
    'gmh_manga.html',
    'gmh_manga_api.json',
    'gmh_chapter_api.json',
    'gmh_decoder.txt',
  ];

  test(
    'G社漫画：分类 / 列表 / 详情 / 目录 / 加密正文（快照 + 真解码器）',
    () async {
      final http = _RouteHttp(<String, String>{
        'https://g-mh.org/manga': _read('gmh_list.html'),
        'https://g-mh.org/manga/wujiakegui-yiming': _read('gmh_manga.html'),
        'https://v2.apikk.top/api/v2/manga/get': _read('gmh_manga_api.json'),
        'https://v2.apikk.top/api/v2/chapter/getinfo': _read('gmh_chapter_api.json'),
        '/assets/runtime/chapter-decoder.js': _read('gmh_decoder.txt'),
      });
      final source = await _boot(
        _script('G社漫画.js'),
        section: Section.comic,
        http: http,
      );
      addTearDown(source.dispose);

      // ---- 分类：四个整表栏目 + 站点自己的题材/标签（从 /manga 实时抓）。
      final categories = await source.data.categories();
      expect(categories.length, greaterThan(30));
      expect(
        categories.take(4).map((category) => category.id).toList(),
        <String>['all', 'hots', 'dayup', 'newss'],
      );
      expect(
        categories.any((category) => category.id == 'genre:kr' && category.title == '韩漫'),
        isTrue,
        reason: '题材组要有 genre:kr=韩漫',
      );

      // ---- 列表：18 条/页，id 是 slug，封面在 c-nc-1.6wm.top。
      final page1 = await source.data.list(categoryId: 'all', page: 1);
      expect(page1.items.length, 18);
      expect(page1.hasMore, isTrue);
      expect(page1.items.first.id, 'wuliandianfeng-pikapi');
      expect(page1.items.first.title, '武炼巅峰');
      expect(page1.items.first.cover, startsWith('https://c-nc-1.6wm.top/manga/'));

      // ---- 详情 + 目录：作品页给 data-mid，章节从接口拿（旧→新）。
      final detail = await source.data.detail('wujiakegui-yiming');
      expect(detail, isNotNull);
      expect(detail!.title, '无家可归');
      expect(detail.cover, startsWith('https://c-nc-1.6wm.top/'));

      final chapters = await source.data.chapters('wujiakegui-yiming');
      expect(chapters.length, 20);
      expect(chapters.first.title, contains('第01话'));

      // ---- 正文：站点自己的解码器在这个沙箱里 eval → 解出 38 张图。
      final content = await source.data.content(
        itemId: 'wujiakegui-yiming',
        chapterId: '1266718',
      );
      expect(content, isA<ImageContent>());
      final images = (content! as ImageContent).images;
      expect(images.length, 38);
      // line=2 → 走 nd2 图床（站点自己的路由表）。
      expect(images.first, startsWith('https://c-nd2-1.6wm.top/'));
      // 解码器来源不固定：首次运行会从站点取一份并缓存进本源自己的 fs，
      // 之后的运行直接吃缓存（这是设计内的省流量），所以这里只断言「解出来了」。
    },
    skip: skipUnless(assets),
    timeout: const Timeout(Duration(seconds: 120)),
  );
}

/// 按 URL 前缀分发（同一个 host 下的不同路径、不同 host 都要能区分）。
class _RouteHttp extends LumeHttp {
  _RouteHttp(this.routes) : super();

  final Map<String, String> routes;
  final List<String> hits = <String>[];

  @override
  Future<LumeHttpResponse> send({
    required String url,
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
    int? maxBytes,
    Duration? timeout,
  }) async {
    hits.add(url);
    // 最长匹配优先：`/manga` 是 `/manga/<slug>` 的前缀，按插入顺序取会串。
    String? payload;
    var matched = '';
    for (final entry in routes.entries) {
      if (url.contains(entry.key) && entry.key.length > matched.length) {
        matched = entry.key;
        payload = entry.value;
      }
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
  Future<Set<String>> contractMethods() async =>
      const <String>{'categories', 'list', 'detail', 'chapters', 'content', 'home'};

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
