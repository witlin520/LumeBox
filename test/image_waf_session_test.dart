import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/net/network_queue.dart';
import 'package:lume_box/core/net/source_request_log.dart';
import 'package:lume_box/core/net/waf.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';

/// 图片请求要不要带源站会话（`cf_clearance` 这类）。
///
/// 真机故障「巴卡漫画首页 / 详情页都没有封面，正文却能看」的根因就在这条口径上：
/// 脚本请求一直带会话（列表 HTML 取得到），图片请求从前一枚 Cookie 都不带——
/// 源站一上 Cloudflare 校验，图片全部 403、封面一片空白。
///
/// 这条链路有两个必须同时成立的半边，谁少了都会翻车：
///   1. **源站自己的图必须带**（不带 → 封面一片空白）；
///   2. **独立图床一枚都不带**（带了 → 把源站会话泄漏给第三方域名）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('image_waf_session');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationSupportDirectory'
          ? root.path
          : null,
    );
    WafSessions.resetForTesting();
    SourceRequestLog.resetForTesting();
    await SectionScope.open(Section.comic);
    await ReadingLibrary.open(Section.comic);
  });

  tearDown(() async {
    WafSessions.resetForTesting();
    SourceRequestLog.resetForTesting();
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await SectionScope.closeAll();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  const sourceId = 'lume.mock.comic';

  /// 造一条「已过网页视图校验」的会话：cookie + UA 成对落库。
  void givenVerifiedSession() {
    WafSessions.save(Section.comic, sourceId, <String, String>{
      'cf_clearance': 'clearance-value',
      '__cf_bm': 'bm-value',
    });
    WafSessions.saveUserAgent(Section.comic, sourceId, 'VerifiedUA/1.0');
  }

  Future<List<NetworkRequest>> capture(String url) async {
    final requests = <NetworkRequest>[];
    final pipeline = SectionImagePipeline(
      cacheDir: root.path,
      maxRetries: 0,
      requestSender: (request) async {
        requests.add(request);
        return const NetworkResponse(
          statusCode: 200,
          body: <int>[1, 2, 3],
          headers: <String, String>{},
        );
      },
    );
    addTearDown(pipeline.dispose);
    pipeline.bindSession(Section.comic, sourceId);
    expect(await pipeline.bytes(url), <int>[1, 2, 3]);
    return requests;
  }

  test('源站自己的封面：带上会话 Cookie，并用验证时的 UA', () async {
    givenVerifiedSession();
    SourceRequestLog.record(sourceId, 'https://baka3.cfd/manhwa/');
    final requests = await capture(
      'https://baka3.cfd/wp-content/uploads/2026/08/cover-270x400.webp',
    );
    expect(requests, hasLength(1));
    expect(
      requests.single.headers['Cookie'],
      'cf_clearance=clearance-value; __cf_bm=bm-value',
    );
    expect(requests.single.headers['User-Agent'], 'VerifiedUA/1.0');
  });

  test('独立图床：一枚 Cookie 都不带（不把源站会话泄漏给第三方域名）', () async {
    givenVerifiedSession();
    SourceRequestLog.record(sourceId, 'https://baka3.cfd/manhwa/');
    final requests = await capture('https://t1.bakamh.de/manga_6a72/aabb.webp');
    expect(requests, hasLength(1));
    expect(requests.single.headers.containsKey('Cookie'), isFalse);
  });

  test('源没请求过的域名：同样不带（判定只看脚本自己请过谁）', () async {
    givenVerifiedSession();
    // 脚本请的是 baka3.cfd，图片却在另一个镜像域名上：不属于「源站自己」。
    SourceRequestLog.record(sourceId, 'https://baka3.cfd/manhwa/');
    final requests = await capture('https://baka1.cfd/wp-content/uploads/a.webp');
    expect(requests.single.headers.containsKey('Cookie'), isFalse);
  });

  test('源自己写死的 Cookie 优先（coverHeaders 比会话更懂那张图）', () async {
    givenVerifiedSession();
    SourceRequestLog.record(sourceId, 'https://baka3.cfd/manhwa/');
    final url = 'https://baka3.cfd/wp-content/uploads/a.webp';
    final requests = <NetworkRequest>[];
    final pipeline = SectionImagePipeline(
      cacheDir: root.path,
      maxRetries: 0,
      requestSender: (request) async {
        requests.add(request);
        return const NetworkResponse(
          statusCode: 200,
          body: <int>[1],
          headers: <String, String>{},
        );
      },
    );
    addTearDown(pipeline.dispose);
    pipeline.bindSession(Section.comic, sourceId);
    pipeline.configureImageHeaders({
      url: {'Cookie': 'explicit=1'},
    });
    await pipeline.bytes(url);
    expect(requests.single.headers['Cookie'], 'explicit=1');
  });

  test('没有会话时行为与从前一致：不带 Cookie、也不动 UA', () async {
    SourceRequestLog.record(sourceId, 'https://baka3.cfd/manhwa/');
    final requests = await capture('https://baka3.cfd/wp-content/uploads/a.webp');
    expect(requests.single.headers.containsKey('Cookie'), isFalse);
    expect(requests.single.headers['User-Agent'], isNot('VerifiedUA/1.0'));
  });

  test('没挂源的管线（书架等）：不带 Cookie', () async {
    givenVerifiedSession();
    SourceRequestLog.record(sourceId, 'https://baka3.cfd/manhwa/');
    final requests = <NetworkRequest>[];
    final pipeline = SectionImagePipeline(
      cacheDir: root.path,
      maxRetries: 0,
      requestSender: (request) async {
        requests.add(request);
        return const NetworkResponse(
          statusCode: 200,
          body: <int>[1],
          headers: <String, String>{},
        );
      },
    );
    addTearDown(pipeline.dispose);
    await pipeline.bytes('https://baka3.cfd/wp-content/uploads/a.webp');
    expect(requests.single.headers.containsKey('Cookie'), isFalse);
  });

  test('域名判定：www 归一、镜像不算同站、没记过就是不带', () {
    SourceRequestLog.record(sourceId, 'https://www.example.com/page/1');
    expect(
      SourceRequestLog.ownsHost(sourceId, 'https://example.com/a.jpg'),
      isTrue,
    );
    expect(
      SourceRequestLog.ownsHost(sourceId, 'https://www.example.com/a.jpg'),
      isTrue,
    );
    expect(
      SourceRequestLog.ownsHost(sourceId, 'https://other.com/a.jpg'),
      isFalse,
    );
    expect(
      SourceRequestLog.ownsHost('nobody', 'https://example.com/a.jpg'),
      isFalse,
    );
    expect(SourceRequestLog.ownsHost(sourceId, '/relative/a.jpg'), isFalse);
    // 域名集合有上限：镜像再多也不会无限膨胀。
    for (var i = 0; i < SourceRequestLog.hostLimit + 5; i++) {
      SourceRequestLog.record(sourceId, 'https://mirror$i.example/a');
    }
    expect(
      SourceRequestLog.ownsHost(sourceId, 'https://mirror0.example/a'),
      isFalse,
    );
    expect(
      SourceRequestLog.ownsHost(sourceId, 'https://mirror6.example/a'),
      isTrue,
    );
  });
}
