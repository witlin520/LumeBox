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

/// Iwara（iwara.tv）：纯 JSON API 源，用真接口夹具在 **QuickJS 沙箱**里跑。
///
/// 站点是 React 空壳，数据全在 `api.iwara.tv`。这个用例守的是：
///   1. 列表分页：`page` 从 0 开始、32 条/页、`count` 字段不可靠（实测 3/11/33 乱跳），
///      hasMore 只能看「本页是否满 32 条」；
///   2. 播放要**两次接口**：详情里的 `fileUrl` 不是视频地址，而是「清晰度列表」的接口地址，
///      取到 `[{name:"360",src:{view:"//host/view?hash=…"}}]` 后还要补 `https:`；
///      preview（几十秒预览片）不许当正片；
///   3. 缩略图不在接口里：`https://i.iwara.tv/image/thumbnail/<file.id>/thumbnail-<版本号>.jpg`；
///   4. 关键词搜索要**明确报错**（query/search/q 被服务端忽略），不能返回默认列表冒充结果；
///   5. 接口被 Cloudflare 挑战时必须抛 NEED_WEBVIEW_VERIFY（网页验证后 App 才注入 cookie）。
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
    'Iwara视频.js',
    'iwara_list.json',
    'iwara_tags.json',
    'iwara_detail.json',
    'iwara_files.json',
  ];

  test(
    'Iwara：分类 / 列表分页 / 详情 / 清晰度变体 / 无搜索（接口夹具）',
    () async {
      final http = _RouteHttp(<String, String>{
        'api.iwara.tv/tags': _read('iwara_tags.json'),
        'api.iwara.tv/video/': _read('iwara_detail.json'),
        'api.iwara.tv/videos': _read('iwara_list.json'),
        'filesq.iwara.tv': _read('iwara_files.json'),
      });
      final source = await _boot(
        _script('Iwara视频.js'),
        section: Section.video,
        http: http,
      );
      addTearDown(source.dispose);

      // ---- 分类：四个有效排序 + 站点标签（/tags 前 40 个）。
      final categories = await source.data.categories();
      expect(categories.take(4).map((c) => c.id).toList(),
          <String>['sort:date', 'sort:trending', 'sort:likes', 'sort:views']);
      expect(categories.length, greaterThan(20), reason: '标签分类要带上');
      expect(categories.any((c) => c.id.startsWith('tag:')), isTrue);

      // ---- 列表：32 条/页，封面走 i.iwara.tv 的版本号缩略图。
      final page1 = await source.data.list(categoryId: 'sort:date', page: 1);
      expect(page1.items.length, 32);
      expect(page1.hasMore, isTrue);
      expect(page1.items.first.id, 'ZhKNDPX6dobros');
      expect(page1.items.first.title, contains('VR 180'));
      expect(page1.items.first.cover,
          startsWith('https://i.iwara.tv/image/thumbnail/'));
      expect(page1.items.first.cover, endsWith('.jpg'));

      // ---- 详情：标题/封面/副标题（作者 · 播放 · 日期）。
      final detail = await source.data.detail('ZhKNDPX6dobros');
      expect(detail, isNotNull);
      expect(detail!.title, contains('VR 180'));
      expect(detail.cover, startsWith('https://i.iwara.tv/'));
      expect(detail.subtitle, contains('r18vrlover'));

      // ---- 播放：fileUrl → 变体列表 → 取 360（跳过 preview）。
      final content = await source.data.content(
        itemId: 'ZhKNDPX6dobros',
        chapterId: 'play',
      );
      expect(content, isA<VideoContent>());
      final video = content! as VideoContent;
      expect(video.url.toString(), startsWith('https://'));
      expect(video.url.toString(), contains('/view?hash='));
      expect(video.url.toString(), isNot(contains('preview')));

      // ---- 搜索：接口不支持匿名搜索，必须明确报错。
      await expectLater(
        source.data.list(keyword: 'cosplay'),
        throwsA(predicate((Object e) => e.toString().contains('不支持匿名搜索'))),
      );
    },
    skip: skipUnless(assets),
    timeout: const Timeout(Duration(seconds: 120)),
  );
}

/// 按 URL 最长匹配分发（不同 host、同 host 的不同路径都要能区分）。
class _RouteHttp extends LumeHttp {
  _RouteHttp(this.routes) : super();

  final Map<String, String> routes;

  @override
  Future<LumeHttpResponse> send({
    required String url,
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
    int? maxBytes,
    Duration? timeout,
  }) async {
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
