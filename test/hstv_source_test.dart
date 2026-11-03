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

/// 好色TV（hstv.fun）：**加密接口**源，用真密文夹具跑生产调用链。
///
/// 站点是 Angular SPA（6KB 空壳，无 SSR），数据来自 `POST <v2 集群>/js`，响应是
/// CryptoJS AES 密文（口令 "xxx"，AES-256-CBC + OpenSSL 派生）。所以这个用例守的是：
///   1. **沙箱里能解密**：脚本自带纯 JS 的 MD5 + AES-256-CBC（沙箱没有 atob/crypto），
///      22KB 密文在 QuickJS 里也要解得动、解出的第一条要与真数据一致；
///   2. 列表路由是 `/sevenVideos?page=N&type=<分类>`，搜索是 `/searchSevenVideos`
///      （filter 参数塞在 body 顶层），详情是 `/sevenVideos/<id>`——三条路由都在
///      请求体里断言，拼错了这里就红；
///   3. 详情里 `m3u8s[0]` 才是播放地址（`m3u8` 是旧字段），VIP/下架要如实报错；
///   4. 条目字段按站点自己的口径落：封面取 thumbnails[0]、副标题是「作者 · 播放量 · 时间」。
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
    '好色TV.js',
    'hstv_list_enc.json',
    'hstv_detail_enc.json',
  ];

  test(
    '好色TV：解密 / 分类 / 列表 / 搜索 / 详情 / m3u8（接口密文夹具）',
    () async {
      final http = _BodyHttp(
        listBody: _read('hstv_list_enc.json'),
        detailBody: _read('hstv_detail_enc.json'),
      );
      final source = await _boot(
        _script('好色TV.js'),
        section: Section.video,
        http: http,
      );
      addTearDown(source.dispose);

      // ---- 分类：站点自己的 type，一个不落（54 个）。
      final categories = await source.data.categories();
      expect(categories.length, 54);
      expect(categories.first.id, 'recent');
      expect(categories.first.title, '最近更新');
      expect(
        categories.map((category) => category.id),
        containsAll(<String>[
          'hd', 'hot', 'c0', 'c1', 'swag', 'west', 'torture_all', 't_high_gaoqing',
        ]),
      );

      // ---- 列表：密文解密 → 24 条；封面/副标题按站点字段落。
      final page1 = await source.data.list(categoryId: 'hd', page: 1);
      expect(page1.items.length, 24);
      expect(page1.hasMore, isTrue, reason: '整页 24 条 = 还有下一页');
      final first = page1.items.first;
      expect(first.id, 'wpNEAItz4');
      expect(first.title, contains('肥臀熟女'));
      expect(first.cover, startsWith('https://tp.pppsuccess.com/'));
      expect(first.subtitle, contains('少妇批发商'));
      expect(first.subtitle, contains('次播放'));
      expect(first.duration, const Duration(minutes: 23, seconds: 41),
          reason: '接口给 durationStr（23:41），App 按时长解析');
      expect(
        http.posts.last['url'],
        '/sevenVideos?page=1&type=hd',
        reason: '列表路由必须走 /sevenVideos?page=&type=',
      );

      // ---- 搜索：/searchSevenVideos，关键词与过滤参数在 body 顶层。
      final searched = await source.data.list(keyword: '麻豆', page: 2);
      expect(searched.items.length, 24);
      final searchBody = http.posts.last;
      expect(searchBody['url'], '/searchSevenVideos');
      expect(searchBody['page'], 2);
      expect(searchBody['keywords'], '麻豆');
      expect(searchBody['filterCategory'], 'all');
      expect(searchBody['keywordLogic'], 'or');

      // ---- 详情：/sevenVideos/<id>；标题/简介来自解密后的对象。
      final detail = await source.data.detail('wpNEAItz4');
      expect(detail, isNotNull);
      expect(detail!.title, contains('肥臀熟女'));
      expect(detail.cover, startsWith('https://tp.pppsuccess.com/'));
      expect(detail.description, contains('肥臀熟女'));
      expect(http.posts.last['url'], '/sevenVideos/wpNEAItz4');

      // ---- 播放：m3u8s[0]，带 Referer（站点播放器不看 Referer，但带上更稳）。
      final content = await source.data.content(
        itemId: 'wpNEAItz4',
        chapterId: 'play',
      );
      expect(content, isA<VideoContent>());
      final video = content! as VideoContent;
      expect(video.url.toString(), startsWith('https://tm.pppsuccess.com/'));
      expect(video.url.toString(), endsWith('index.m3u8'));
      expect(video.headers['Referer'], 'https://hstv.fun/');

      // ---- 请求体本身：app 跟着站点域名走、带 uuid 与版本号。
      final body = http.rawBodies.last;
      expect(body['app'], 'hstv.fun');
      expect(body['version'], '260901');
      expect(body['uuid'], matches(RegExp(r'^U\d{16,20}$')));
    },
    skip: skipUnless(assets),
    timeout: const Timeout(Duration(seconds: 120)),
  );
}

/// 按请求体里的 `url` 字段分发（列表/搜索/详情都打同一个 /js 地址）。
class _BodyHttp extends LumeHttp {
  _BodyHttp({required this.listBody, required this.detailBody}) : super();

  final String listBody;
  final String detailBody;

  /// 每次 POST 解密前 body（断言路由与参数用）。
  final List<Map<String, dynamic>> rawBodies = <Map<String, dynamic>>[];

  /// 其中 url/page/keywords 这几个常用字段的扁平视图。
  final List<Map<String, dynamic>> posts = <Map<String, dynamic>>[];

  @override
  Future<LumeHttpResponse> send({
    required String url,
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
    int? maxBytes,
    Duration? timeout,
  }) async {
    Map<String, dynamic> parsed = <String, dynamic>{};
    try {
      parsed = jsonDecode(body ?? '{}') as Map<String, dynamic>;
    } catch (_) {}
    rawBodies.add(parsed);
    posts.add(<String, dynamic>{
      'url': parsed['url'],
      'page': parsed['page'],
      'keywords': parsed['keywords'],
      'filterCategory': parsed['filterCategory'],
      'keywordLogic': parsed['keywordLogic'],
    });
    final logical = (parsed['url'] ?? '') as String;
    String? payload;
    if (logical.startsWith('/sevenVideos?')) payload = listBody;
    if (logical.startsWith('/sevenVideos/')) payload = detailBody;
    if (logical.startsWith('/searchSevenVideos')) payload = listBody;
    if (payload == null) {
      return LumeHttpResponse(
        statusCode: 404,
        body: Uint8List.fromList(utf8.encode('not found: $logical')),
        headers: const <String, String>{},
      );
    }
    return LumeHttpResponse(
      statusCode: 200,
      body: Uint8List.fromList(utf8.encode(payload)),
      headers: const <String, String>{'content-type': 'application/json'},
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
