import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:lume_box/core/net/lume_http.dart';
import 'package:lume_box/core/source/source_favicon.dart';
import 'package:lume_box/core/source/lume_sources.dart';
import 'package:lume_box/shared/widgets/source_icon.dart';

/// 源图标（真机反馈「源图标好多都没有」）：候选地址、首页解析、图片校验、缓存。
///
/// 这一份把「图标怎么被找出来」钉住——站点把 /favicon.ico 写成 404 页、
/// 换成 PNG、或只写在首页 `<link rel=icon>` 里，都要能走到真图标；
/// 全都拿不到时必须老实回退首字母，不许把 HTML 当图片画出来。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SVG 图标转为静态 PNG，自动加载与主动获取均可持久缓存', (tester) async {
    await tester.runAsync(() async {
      const svg =
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" fill="#ff3300"/></svg>';
      final root = Directory.systemTemp.createTempSync('source-svg-');
      try {
        var calls = 0;
        final resolver = SourceFavicon(
          cacheDirectory: () async => root,
          http: LumeHttp(
            client: MockClient((request) async {
              calls++;
              if (request.url.path == '/') {
                return http.Response(
                  '<link rel="icon" href="/images/favicon.svg">',
                  200,
                  headers: {'content-type': 'text/html; charset=utf-8'},
                );
              }
              if (request.url.path.endsWith('.svg')) {
                return http.Response(
                  svg,
                  200,
                  headers: {'content-type': 'image/svg+xml'},
                );
              }
              return http.Response('not found', 404);
            }),
          ),
        );
        final bytes = await resolver.load(origin: 'https://svg.test');
        final image = img.decodePng(bytes!);
        expect(image!.width, 192);
        expect(image.getPixel(96, 96).r, 255);
        expect(image.numFrames, 1);
        expect(await resolver.loadBest(origin: 'https://svg.test'), isNotNull);
        final after = calls;
        final restarted = SourceFavicon(
          cacheDirectory: () async => root,
          http: LumeHttp(
            client: MockClient((_) async {
              calls++;
              return http.Response('offline', 503);
            }),
          ),
        );
        expect(await restarted.load(origin: 'https://svg.test'), isNotNull);
        expect(calls, after);
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  });

  testWidgets('SVG 1.1 内嵌 PNG 图标可转换，支持站点实际使用的格式', (tester) async {
    await tester.runAsync(() async {
      final image = img.Image(width: 2, height: 2)
        ..setPixelRgba(0, 0, 255, 51, 0, 255);
      final encoded = base64Encode(img.encodePng(image));
      final svg =
          '<?xml version="1.0"?>'
          '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">'
          '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="2" height="2" viewBox="0 0 2 2">'
          '<image width="2" height="2" xlink:href="data:image/png;base64,$encoded"/></svg>';
      final resolver = SourceFavicon(
        fetchHtmlHomepage: false,
        http: LumeHttp(
          client: MockClient(
            (_) async => http.Response(
              svg,
              200,
              headers: {'content-type': 'image/svg+xml'},
            ),
          ),
        ),
      );
      final png = await resolver.load(origin: 'https://embedded.test');
      expect(png, isNotNull);
      expect(img.decodePng(png!)!.width, 192);
    });
  });

  testWidgets('SVG 外链图片不产生隐式网络请求', (tester) async {
    await tester.runAsync(() async {
      final resolver = SourceFavicon(
        fetchHtmlHomepage: false,
        http: LumeHttp(
          client: MockClient(
            (_) async => http.Response(
              '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><image href="https://external.test/tracker.png"/></svg>',
              200,
              headers: {'content-type': 'image/svg+xml'},
            ),
          ),
        ),
      );
      expect(await resolver.load(origin: 'https://svg.test'), isNull);
    });
  });

  for (final logo in [false, true]) {
    test('首页图标失效时回退到${logo ? "站点 logo" : "本站同路径"}，不抓内容封面', () async {
      final asked = <String>[];
      final png = img.encodePng(img.Image(width: 64, height: 64));
      final resolver = SourceFavicon(
        http: LumeHttp(
          client: MockClient((request) async {
            asked.add(request.url.toString());
            if (request.url.path == '/') {
              return http.Response(
                logo
                    ? '<link rel="icon" href="/missing.ico"><a href="/"><img src="/theme/picture/logo.png" alt="站名"></a><img src="/cover.png">'
                    : '<link rel="icon" href="https://old.test/theme/favicon.png">',
                200,
                headers: {'content-type': 'text/html; charset=utf-8'},
              );
            }
            if (request.url.host == 'site.test' &&
                request.url.path ==
                    (logo ? '/theme/picture/logo.png' : '/theme/favicon.png')) {
              return http.Response.bytes(
                png,
                200,
                headers: {'content-type': 'image/png'},
              );
            }
            return http.Response(
              '<html>not an icon</html>',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }),
        ),
      );
      expect(await resolver.load(origin: 'https://site.test'), isNotNull);
      expect(asked.any((url) => url.endsWith('/cover.png')), isFalse);
    });
  }

  test('主动获取比较网页和 manifest 实际像素，替换低清缓存并持久保存高清图标', () async {
    final root = Directory.systemTemp.createTempSync('best-source-icon-');
    addTearDown(() => root.deleteSync(recursive: true));
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      final path = request.url.path;
      if (path == '/') {
        return http.Response(
          '''
        <link rel="apple-touch-icon" sizes="180x180" href="/apple.png">
        <link rel="icon" sizes="2048x2048" href="/claimed-large.png">
        <link rel="manifest" href="/app/manifest.json">
      ''',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
      if (path == '/app/manifest.json') {
        return http.Response(
          jsonEncode({
            'icons': [
              {'src': 'icon512.png', 'sizes': '512x512'},
              {'src': 'icon192.png', 'sizes': '48x48 192x192'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final size = {
        '/favicon.ico': 16,
        '/apple.png': 180,
        '/claimed-large.png': 32,
        '/app/icon512.png': 512,
        '/app/icon192.png': 192,
      }[path];
      if (size == null) return http.Response('not found', 404);
      return http.Response.bytes(
        img.encodePng(img.Image(width: size, height: size)),
        200,
        headers: {'content-type': 'image/png'},
      );
    });
    addTearDown(client.close);
    final resolver = SourceFavicon(
      http: LumeHttp(client: client),
      cacheDirectory: () async => root,
    );
    final small = await resolver.load(origin: 'https://fixture.test');
    expect(img.decodePng(small!)!.width, 16);
    final large = await resolver.loadBest(origin: 'https://fixture.test');
    expect(
      img.decodePng(large!)!.width,
      512,
      reason: '按实际像素，而不是不可信的 sizes=2048',
    );
    final after = calls;
    expect(
      img
          .decodePng((await resolver.load(origin: 'https://fixture.test'))!)!
          .width,
      512,
    );
    final restarted = SourceFavicon(
      http: LumeHttp(client: client),
      cacheDirectory: () async => root,
    );
    expect(
      img
          .decodePng((await restarted.load(origin: 'https://fixture.test'))!)!
          .width,
      512,
    );
    expect(calls, after, reason: '高清结果复用内存与磁盘缓存，不重复扫站点');
  });

  test('高清候选不可用时保留已有小图，重复点击共用一次解析', () async {
    final gate = Completer<void>(), homeStarted = Completer<void>();
    var homeCalls = 0;
    var findingBest = false;
    final png = img.encodePng(img.Image(width: 32, height: 32));
    final resolver = SourceFavicon(
      http: LumeHttp(
        client: MockClient((request) async {
          if (request.url.path == '/') {
            homeCalls++;
            homeStarted.complete();
            await gate.future;
          }
          if (!findingBest) {
            return http.Response.bytes(
              png,
              200,
              headers: {'content-type': 'image/png'},
            );
          }
          return http.Response('not found', 404);
        }),
      ),
    );
    await resolver.load(origin: 'https://fixture.test');
    findingBest = true;
    final a = resolver.loadBest(origin: 'https://fixture.test');
    await homeStarted.future;
    final b = resolver.loadBest(origin: 'https://fixture.test');
    gate.complete();
    expect(identical(a, b), true);
    expect(img.decodePng((await a)!)!.width, 32);
    expect(homeCalls, 1);
  });
  test('图标路径按网页目录和 base 解析，处理实体并排除伪 rel 与凭据地址', () {
    expect(
      SourceFavicon.iconLinksFromHtml('''
      <base href="/assets/ui/">
      <link rel="icon" href="../brand.png?x=1&amp;y=2">
      <link data-rel="icon" href="/wrong.png">
      <link rel="not-an-icon" href="/wrong2.png">
      <link rel="icon" href="https://user:pass@elsewhere.test/a.png">
    ''', 'https://site.test/app/index.html'),
      ['https://site.test/assets/brand.png?x=1&y=2'],
    );
    expect(
      SourceFavicon.iconLinksFromHtml(
        '<link rel="icon" href="../icon.png">',
        'https://site.test/app/sub/page.html',
      ),
      ['https://site.test/app/icon.png'],
    );
  });
  test('Kazumi 及普通声明镜像的源使用真实站址，不把规则仓库当站点', () {
    const header =
        '// LumeSource: {"id":"kazumi_fixture","name":"Example","version":"1","category":"video","mirrors":["https://anime.example/path/"]}';
    expect(
      LumeSources.siteUrlFromScript('$header\nconst kazumiRule = {};'),
      'https://anime.example',
    );
    expect(
      LumeSources.siteUrlFromScript(
        "$header\nvar BASE_URL = 'https://current.example';",
      ),
      'https://current.example',
    );
    expect(LumeSources.siteUrlFromScript('var LumeSource = {};'), '');
    expect(
      LumeSources.siteUrlFromScript("var HOST = 'https://fixture.test';"),
      'https://fixture.test',
    );
    expect(
      LumeSources.siteUrlFromScript(
        "const baseURL = 'https://fixture.test/path';",
      ),
      'https://fixture.test',
    );
    expect(
      LumeSources.siteUrlFromScript(
        "const config = {base: 'https://fixture.test/path'};",
      ),
      'https://fixture.test',
    );
    expect(
      LumeSources.siteUrlFromScript(
        "var base_url = 'https://fixture.test/path';",
      ),
      'https://fixture.test',
    );
    expect(
      LumeSources.siteUrlFromScript(
        "var HOST = 'https://user:secret@fixture.test';",
      ),
      isEmpty,
    );
  });
  test('图标后台解析最多同时两站，避免抽屉占满业务请求队列', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    var calls = 0, active = 0, peak = 0;
    final png = img.encodePng(img.Image(width: 2, height: 2));
    final resolver = SourceFavicon(
      http: LumeHttp(
        client: MockClient((request) async {
          calls++;
          active++;
          if (active > peak) peak = active;
          if (calls == 2) started.complete();
          await gate.future;
          active--;
          return http.Response.bytes(
            png,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      ),
    );
    final loads = [
      for (var i = 0; i < 6; i++) resolver.load(origin: 'https://icon$i.test'),
    ];
    await started.future;
    expect(calls, 2);
    gate.complete();
    expect(await Future.wait(loads), everyElement(isNotNull));
    expect(peak, 2);
  });

  test('多尺寸 ICO 只输出最大尺寸的静态 PNG，不把图标尺寸轮播为动画', () async {
    final image = img.Image(width: 16, height: 16)
      ..addFrame(img.Image(width: 48, height: 48));
    final resolver = SourceFavicon(
      http: LumeHttp(
        client: MockClient(
          (_) async => http.Response.bytes(
            img.encodeIco(image),
            200,
            headers: {'content-type': 'image/x-icon'},
          ),
        ),
      ),
    );
    final bytes = await resolver.load(origin: 'https://sizes.test');
    final decoded = img.decodePng(bytes!);
    expect(decoded!.width, 48);
    expect(decoded.numFrames, 1);
  });

  test('GIF 站点图标冻结为静态 PNG，避免动态闪烁', () async {
    final image = img.Image(width: 16, height: 16)
      ..addFrame(img.Image(width: 16, height: 16));
    final resolver = SourceFavicon(
      http: LumeHttp(
        client: MockClient(
          (_) async => http.Response.bytes(
            img.encodeGif(image),
            200,
            headers: {'content-type': 'image/gif'},
          ),
        ),
      ),
    );
    final bytes = await resolver.load(origin: 'https://animated.test');
    expect(img.decodePng(bytes!)!.numFrames, 1);
  });

  test('重新创建解析器后从磁盘读取成功图标，不重复请求网站', () async {
    final root = Directory.systemTemp.createTempSync('source-icon-cache-');
    addTearDown(() => root.deleteSync(recursive: true));
    var calls = 0;
    SourceFavicon resolver() => SourceFavicon(
      cacheDirectory: () async => root,
      http: LumeHttp(
        client: MockClient((_) async {
          calls++;
          return http.Response.bytes(
            img.encodePng(img.Image(width: 16, height: 16)),
            200,
          );
        }),
      ),
    );
    final first = await resolver().load(origin: 'https://cache.test');
    final second = await resolver().load(origin: 'https://cache.test');
    expect(second, first);
    expect(calls, 1);
  });
  test('ICO 站点图标转换为 Flutter 可解码的 PNG', () async {
    final ico = img.encodeIco(img.Image(width: 16, height: 16));
    final resolver = SourceFavicon(
      http: LumeHttp(
        source: 'ICO',
        client: MockClient(
          (_) async => http.Response.bytes(
            ico,
            200,
            headers: {'content-type': 'image/x-icon'},
          ),
        ),
      ),
    );
    final bytes = await resolver.load(origin: 'https://ico.example');
    expect(bytes!.take(4), [0x89, 0x50, 0x4e, 0x47]);
    expect(img.decodePng(bytes)?.width, 16);
  });

  test('失败的图标不永久缓存，网络恢复后能再次获取', () async {
    var ready = false;
    var now = DateTime(2026, 10, 24);
    var calls = 0;
    final data = img.encodePng(img.Image(width: 2, height: 2));
    final resolver = SourceFavicon(
      now: () => now,
      http: LumeHttp(
        source: 'retry',
        client: MockClient((_) async {
          calls++;
          return http.Response.bytes(
            ready ? data : [],
            ready ? 200 : 403,
            headers: {'content-type': 'image/png'},
          );
        }),
      ),
    );
    expect(await resolver.load(origin: 'https://retry.example'), isNull);
    final failedCalls = calls;
    ready = true;
    expect(await resolver.load(origin: 'https://retry.example'), isNull);
    expect(calls, failedCalls);
    now = now.add(const Duration(minutes: 2));
    expect(await resolver.load(origin: 'https://retry.example'), isNotNull);
  });

  /// 1x1 PNG（最小可解码图片）：用来当「真图标」。
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAF/gH8YQ3G'
    'AAAAAElFTkSuQmCC',
  );

  test('首页解析：apple-touch-icon 优先、相对地址补全、保留 SVG 候选', () {
    final html = '''
<html><head>
<link rel="icon" type="image/svg+xml" href="/favicon.svg">
<link rel="icon" sizes="32x32" href="/img/icon32.png">
<link rel="apple-touch-icon-precomposed" sizes="180x180" href="/img/logo256.png">
<link rel="shortcut icon" href="favicon.ico">
</head></html>''';
    final links = SourceFavicon.iconLinksFromHtml(html, 'https://a.com');
    // apple-touch-icon 排第一；SVG 留给下载后的静态 PNG 转换。
    expect(links.first, 'https://a.com/img/logo256.png');
    expect(links, contains('https://a.com/favicon.svg'));
    expect(links.toSet(), <String>{
      'https://a.com/favicon.svg',
      'https://a.com/img/logo256.png',
      'https://a.com/img/icon32.png',
      'https://a.com/favicon.ico',
    });
    // 站点没给图标时给空列表（调用方据此收手，不再瞎猜）。
    expect(
      SourceFavicon.iconLinksFromHtml('<html></html>', 'https://a.com'),
      isEmpty,
    );
  });

  test('候选顺序：声明图标失效先读网页，再回退约定路径', () async {
    final asked = <String>[];
    final resolver = SourceFavicon(
      http: LumeHttp(
        source: '测试',
        client: MockClient((request) async {
          asked.add(request.url.toString());
          return http.Response.bytes(<int>[], 404);
        }),
      ),
    );
    await resolver.load(
      origin: 'https://a.com',
      explicit: <String>['https://cdn.example.com/my.png'],
    );
    expect(asked, <String>[
      'https://cdn.example.com/my.png',
      'https://a.com/',
      'https://a.com/favicon.ico',
      'https://a.com/favicon.png',
      'https://a.com/apple-touch-icon.png',
      'https://a.com/static/favicon.ico',
    ]);
  });

  test('favicon.ico 是 404 页：继续找首页 <link rel=icon> 里的真图标', () async {
    final asked = <String>[];
    final resolver = SourceFavicon(
      http: LumeHttp(
        source: '测试',
        client: MockClient((request) async {
          final url = request.url.toString();
          asked.add(url);
          if (url == 'https://a.com/') {
            return http.Response(
              '<html><head><link rel="icon" href="/img/logo256.png"></head></html>',
              200,
              headers: <String, String>{
                'content-type': 'text/html; charset=utf-8',
              },
            );
          }
          if (url == 'https://a.com/img/logo256.png') {
            return http.Response.bytes(
              png,
              200,
              headers: <String, String>{'content-type': 'image/png'},
            );
          }
          // /favicon.ico 回的是站点的 404 HTML 页（很多站都这样）。
          return http.Response(
            '<html><body>not found</body></html>',
            404,
            headers: <String, String>{'content-type': 'text/html'},
          );
        }),
      ),
    );
    final bytes = await resolver.load(origin: 'https://a.com');
    expect(asked, [
      'https://a.com/favicon.ico',
      'https://a.com/',
      'https://a.com/img/logo256.png',
    ], reason: '自动加载不再等待其余两个无效猜测路径');
    expect(bytes, isNotNull);
    expect(bytes!.length, png.length);
    expect(asked.last, 'https://a.com/img/logo256.png');
  });

  test('内容不是图片就当没有：HTML / 无效 SVG / 空响应都不算图标', () async {
    Future<Uint8List?> load(http.Response Function(http.Request) respond) {
      final resolver = SourceFavicon(
        http: LumeHttp(
          source: '测试',
          client: MockClient((r) async => respond(r)),
        ),
      );
      return resolver.load(origin: 'https://a.com');
    }

    // 状态码 200、content-type 说自己是 png，内容却是 HTML——不许当图片画。
    expect(
      await load(
        (_) => http.Response(
          '<html><body>nginx</body></html>',
          200,
          headers: <String, String>{'content-type': 'image/png'},
        ),
      ),
      isNull,
    );
    // SVG：Flutter 画不了，当作没有。
    expect(
      await load(
        (_) => http.Response(
          '<svg xmlns="http://www.w3.org/2000/svg"></svg>',
          200,
          headers: <String, String>{'content-type': 'image/svg+xml'},
        ),
      ),
      isNull,
    );
    expect(
      await load(
        (_) => http.Response.bytes(
          <int>[],
          200,
          headers: <String, String>{'content-type': 'image/png'},
        ),
      ),
      isNull,
    );
  });

  test('同一个源只请求一次：结果（含失败）都进缓存', () async {
    var calls = 0;
    final resolver = SourceFavicon(
      http: LumeHttp(
        source: '测试',
        client: MockClient((request) async {
          calls++;
          return http.Response.bytes(
            png,
            200,
            headers: <String, String>{'content-type': 'image/png'},
          );
        }),
      ),
    );
    final first = await resolver.load(origin: 'https://a.com');
    final second = await resolver.load(origin: 'https://a.com');
    expect(first, isNotNull);
    expect(second, same(first));
    expect(calls, 1, reason: '列表滚动 / 切页签不该把同一个站重打一遍');

    // 并发调用也只发一次（在飞表去重）。
    resolver.clearCache();
    calls = 0;
    await Future.wait(<Future<Uint8List?>>[
      resolver.load(origin: 'https://a.com'),
      resolver.load(origin: 'https://a.com'),
    ]);
    expect(calls, 1);
  });

  testWidgets('控件：拿不到图标显示首字母，拿到就画图', (tester) async {
    SourceFavicon resolver(Uint8List? bytes) => SourceFavicon(
      http: LumeHttp(
        source: '测试',
        client: MockClient(
          (request) async => bytes == null
              ? http.Response.bytes(<int>[], 404)
              : http.Response.bytes(
                  bytes,
                  200,
                  headers: <String, String>{'content-type': 'image/png'},
                ),
        ),
      ),
      fetchHtmlHomepage: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: <Widget>[
            SourceIcon(
              name: '禁漫天堂',
              siteUrl: 'https://a.com',
              favicon: resolver(null),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('禁'), findsOneWidget, reason: '取不到时回退首字母');
    expect(find.byType(Image), findsNothing);

    final loadedResolver = resolver(png);
    await tester.runAsync(() => loadedResolver.load(origin: 'https://a.com'));
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: <Widget>[
            SourceIcon(
              name: '禁漫天堂',
              siteUrl: 'https://a.com',
              favicon: loadedResolver,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('禁'), findsNothing);
  });
}
