import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/net/network_queue.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/session/section.dart';

void main() {
  test('独立图片域名CF不重复重试并保留准确验证地址', () async {
    var calls = 0;
    const url = 'https://images.example/cover.jpg?signature=current';
    final dir = Directory.systemTemp.createTempSync('lume-image-cf');
    final pipeline = SectionImagePipeline(
      cacheDir: dir.path,
      diskCache: false,
      requestSender: (_) async {
        calls++;
        return NetworkResponse(
          statusCode: 403,
          body: '<html><title>Attention Required! | Cloudflare</title></html>'
              .codeUnits,
          headers: const {},
        );
      },
    );
    addTearDown(() {
      pipeline.dispose();
      dir.deleteSync(recursive: true);
    });
    expect(await pipeline.bytes(url), isNull);
    expect(calls, 1);
    expect(pipeline.failureFor(url), '图片需要网页验证');
    expect(pipeline.canRetry(url), false);
    expect(pipeline.verificationTargetFor(url), url);
  });

  test('签名时间按UTC判定，读取前刷新即将过期的地址', () {
    final url =
        'https://images.example/a.jpg?X-Amz-Date=20261013T224940Z&X-Amz-Expires=60';
    expect(
      SectionImagePipeline.signedUrlExpired(
        url,
        now: DateTime.utc(2026, 10, 13, 22, 50, 38),
      ),
      true,
    );
    expect(
      SectionImagePipeline.signedUrlExpired(
        url,
        now: DateTime.utc(2026, 10, 13, 22, 49, 50),
      ),
      false,
    );
    expect(
      SectionImagePipeline.signedUrlExpired('https://images.example/a.jpg'),
      false,
    );
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('cover-recovery'));
  tearDown(() => root.deleteSync(recursive: true));
  test('签名图片403后重新读取来源页，元数据不发给图床', () async {
    const old = 'https://images.example/a.jpg?signature=expired';
    const fresh = 'https://images.example/a.jpg?signature=fresh';
    final source = _RefreshingSource(fresh);
    final requests = <NetworkRequest>[];
    final pipeline = SectionImagePipeline(
      cacheDir: root.path,
      maxRetries: 0,
      requestSender: (request) async {
        requests.add(request);
        return NetworkResponse(
          statusCode: request.url == fresh ? 200 : 403,
          body: request.url == fresh ? [1, 2, 3] : [],
          headers: {},
        );
      },
    );
    addTearDown(pipeline.dispose);
    pipeline.bindSource(source);
    pipeline.configureImageHeaders({
      old: {
        'Referer': 'https://site.example/',
        'X-Lume-Image-Page': 'https://site.example/page/1',
      },
    });
    expect(await pipeline.bytes(old), [1, 2, 3]);
    expect(source.calls, 1);
    expect(source.page, 'https://site.example/page/1');
    expect(requests.map((r) => r.url), [old, fresh]);
    for (final request in requests) {
      expect(request.headers.containsKey('X-Lume-Image-Page'), false);
      expect(request.headers['Referer'], 'https://site.example/');
    }
  });
  test('证书过期仅兼容已验证的公开缩略图，不携带凭证且沿用原缓存键', () async {
    const url =
        'https://imgcdn01.dycp444.com/pic8/e/9/e9a9905693e273094531d96d935fc330.320.255.jpg';
    final requests = <NetworkRequest>[];
    final pipeline = SectionImagePipeline(
      cacheDir: root.path,
      maxRetries: 0,
      requestSender: (request) async {
        requests.add(request);
        if (request.url.startsWith('https:')) {
          throw const HandshakeException('CERTIFICATE_VERIFY_FAILED: expired');
        }
        return const NetworkResponse(
          statusCode: 200,
          body: [1, 2, 3],
          headers: {},
        );
      },
    );
    addTearDown(pipeline.dispose);
    pipeline.configureImageHeaders({
      url: {'X-Image-Token': 'private'},
    });
    expect(await pipeline.bytes(url), [1, 2, 3]);
    expect(requests.length, 2);
    expect(requests.last.url, url.replaceFirst('https:', 'http:'));
    expect(requests.last.headers.containsKey('X-Image-Token'), false);
    expect(requests.last.headers.containsKey('Cookie'), false);
    expect(File(pipeline.cachePathFor(url)).existsSync(), true);
    expect(pipeline.failureFor(url), isNull);
    expect(
      SectionImagePipeline.publicThumbnailFallback(
        url,
        headers: {'Authorization': 'private'},
      ),
      isNull,
    );
    expect(
      SectionImagePipeline.publicThumbnailFallback('$url?token=private'),
      isNull,
    );
    expect(
      SectionImagePipeline.publicThumbnailFallback(
        url.replaceFirst('imgcdn01.dycp444.com', 'cdn.example'),
      ),
      isNull,
    );
    expect(
      SectionImagePipeline.publicThumbnailFallback(
        'https://imgcdn01.dycp444.com/account/profile.jpg',
      ),
      isNull,
    );
  });
  test('TMDB 图片域名失败时使用官方备用域名，缓存仍归原地址且不透传认证头', () async {
    final requests = <NetworkRequest>[];
    final pipeline = SectionImagePipeline(
      cacheDir: root.path,
      maxRetries: 0,
      requestSender: (request) async {
        requests.add(request);
        if (Uri.parse(request.url).host == 'image.tmdb.org') {
          throw const SocketException('fixture blocked domain');
        }
        return const NetworkResponse(
          statusCode: 200,
          body: [1, 2, 3],
          headers: {},
        );
      },
    );
    addTearDown(pipeline.dispose);
    const url = 'https://image.tmdb.org/t/p/w300/cover.jpg';
    pipeline.configureImageHeaders({
      url: {'Cookie': 'private', 'Authorization': 'private'},
    });
    expect(await pipeline.bytes(url), [1, 2, 3]);
    expect(
      requests.last.url,
      'https://media.themoviedb.org/t/p/w300/cover.jpg',
    );
    expect(requests.last.headers.containsKey('Cookie'), false);
    expect(requests.last.headers.containsKey('Authorization'), false);
    expect(File(pipeline.cachePathFor(url)).existsSync(), true);
    expect(pipeline.failureFor(url), isNull);
  });
  test('403 后确实移除源指定的 Referer，不重复发送同一请求头', () async {
    final requests = <NetworkRequest>[];
    final pipeline = SectionImagePipeline(
      cacheDir: root.path,
      maxRetries: 1,
      requestSender: (request) async {
        requests.add(request);
        return NetworkResponse(
          statusCode: requests.length == 1 ? 403 : 200,
          body: requests.length == 1 ? [] : [1, 2, 3],
          headers: {},
        );
      },
    );
    addTearDown(pipeline.dispose);
    const url = 'https://cdn.example/cover.jpg';
    pipeline.configureImageHeaders({
      url: {'Referer': 'https://source.example/', 'X-Image': 'keep'},
    });
    expect(await pipeline.bytes(url), [1, 2, 3]);
    expect(requests.first.headers['Referer'], 'https://source.example/');
    expect(
      requests.last.headers.keys.where((k) => k.toLowerCase() == 'referer'),
      isEmpty,
    );
    expect(requests.last.headers['X-Image'], 'keep');
  });
  test('200 校验网页不写入图片缓存；证书错误不反复排队', () async {
    var attempts = 0;
    final pipeline = SectionImagePipeline(
      cacheDir: root.path,
      requestSender: (request) async {
        attempts++;
        if (request.url.contains('expired')) {
          throw const HandshakeException(
            'CERTIFICATE_VERIFY_FAILED: certificate has expired',
          );
        }
        return NetworkResponse(
          statusCode: 200,
          body: '<!DOCTYPE html><html>challenge</html>'.codeUnits,
          headers: {},
        );
      },
    );
    addTearDown(pipeline.dispose);
    const html = 'https://cdn.example/challenge.jpg';
    expect(await pipeline.bytes(html), isNull);
    expect(File(pipeline.cachePathFor(html)).existsSync(), false);
    expect(pipeline.failureFor(html), '非图片响应');
    expect(await pipeline.bytes('https://cdn.example/expired.jpg'), isNull);
    expect(pipeline.canRetry('https://cdn.example/expired.jpg'), false);
    expect(attempts, 2);
  });
  testWidgets('旧损坏封面缓存被移除并重新下载解码', (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 4, 4),
        Paint()..color = Colors.purple,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(4, 4);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      var requests = 0;
      final pipeline = SectionImagePipeline(
        cacheDir: root.path,
        requestSender: (_) async {
          requests++;
          return NetworkResponse(
            statusCode: 200,
            body: png!.buffer.asUint8List(),
            headers: {},
          );
        },
      );
      const url = 'https://cdn.example/cover.png';
      File(pipeline.cachePathFor(url))
          .writeAsStringSync('<html>old cached challenge</html>');
      final decoded = await pipeline.image(url);
      expect(decoded?.width, 4);
      expect(requests, 1);
      expect(pipeline.failureFor(url), null);
      pipeline.release(url);
      pipeline.dispose();
    });
  });
}

class _RefreshingSource extends MockDataSource
    implements RefreshingImageCapable {
  _RefreshingSource(this.fresh) : super(section: Section.comic);
  final String fresh;
  int calls = 0;
  String? page;
  @override
  Future<String?> refreshImage(String url, String origin) async {
    calls++;
    page = origin;
    return fresh;
  }
}
