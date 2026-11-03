import 'package:lume_box/features/video/source_playback.dart';

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/net/network_queue.dart';
import 'package:lume_box/core/net/source_request_log.dart';
import 'package:lume_box/core/net/site_session_pool.dart';
import 'package:lume_box/core/net/waf.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('图片使用源验证UA并要求原生按图片域名选择验证Cookie，Dart不复制Cookie', () async {
    final root = Directory.systemTemp.createTempSync('lume-image-session');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    final library = await ReadingLibrary.open(Section.comic);
    const source = MockDataSource(section: Section.comic);
    WafSessions.saveUserAgent(Section.comic, source.id, 'verified-device-UA');
    WafSessions.save(Section.comic, source.id, {
      'cf_clearance': 'fixture-cookie',
    });
    NetworkRequest? sent;
    final pipeline = SectionImagePipeline(
      cacheDir: library.imageCacheDir,
      requestSender: (request) async {
        sent = request;
        return const NetworkResponse(
          statusCode: 200,
          body: [1, 2, 3],
          headers: {},
        );
      },
    );
    addTearDown(() async {
      pipeline.dispose();
      ReadingLibrary.disposeAll();
      ReadingStore.disposeAll();
      WafSessions.resetForTesting();
      SiteSessionPool.shared.clear();
      await SectionScope.closeAll();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      root.deleteSync(recursive: true);
    });
    final video = VideoContent(
      url: Uri.parse('https://independent.cdn/video.mp4'),
      headers: const {
        'user-agent': 'source-static-UA',
        'Referer': 'https://source.example/',
      },
      qualities: [
        VideoQuality(
          label: '1080p',
          url: Uri.parse('https://independent.cdn/1080.mp4'),
        ),
      ],
    );
    final mediaHeaders = SourcePlayback.contentHeaders(video, source: source);
    expect(mediaHeaders['User-Agent'], 'verified-device-UA');
    expect(mediaHeaders.containsKey('Cookie'), false, reason: '主站会话不发给独立媒体CDN');
    expect(mediaHeaders.containsKey('user-agent'), false);

    // 媒体地址就在**源站自己的域名**上时：验证过的 Cookie 要一起带上
    // （CF 站点的媒体只带 UA 不带 cf_clearance 同样被拦，真机反馈的「播放链接中断」）。
    SourceRequestLog.record(source.id, 'https://own.example/album/1');
    final own = VideoContent(
      url: Uri.parse('https://own.example/media/a.m3u8'),
      headers: const <String, String>{'Referer': 'https://own.example/'},
    );
    final ownHeaders = SourcePlayback.contentHeaders(own, source: source);
    expect(ownHeaders['Cookie'], 'cf_clearance=fixture-cookie');
    expect(ownHeaders['User-Agent'], 'verified-device-UA');
    expect(ownHeaders['Referer'], 'https://own.example/');
    // 图源脚本自己给了 Cookie 时不覆盖（脚本更清楚这个站要什么）。
    final scripted = VideoContent(
      url: Uri.parse('https://own.example/media/a.m3u8'),
      headers: const <String, String>{'Cookie': 'script=1'},
    );
    expect(
      SourcePlayback.contentHeaders(scripted, source: source)['Cookie'],
      'script=1',
    );
    expect(
      SourcePlayback.contentQualities(video, source: source).single.headers,
      mediaHeaders,
    );
    pipeline.bindSource(source);
    await pipeline.bytes('https://images.example/a.jpg');
    expect(sent!.headers['User-Agent'], 'verified-device-UA');
    expect(sent!.reuseVerifiedSession, true);
    expect(sent!.headers.containsKey('Cookie'), false);
    // The main page issues this Domain cookie without a CAPTCHA. Covers and
    // chapter images must receive it; unrelated and host-only cookies must not.
    SiteSessionPool.shared.importCookies([
      {
        'name': 'jcomic_access',
        'value': 'server-issued',
        'domain': '.jcomic.net',
        'path': '/',
        'secure': true,
      },
      {
        'name': 'main_only',
        'value': 'private',
        'domain': 'jcomic.net',
        'path': '/',
      },
      {
        'name': 'foreign',
        'value': 'private',
        'domain': '.other.test',
        'path': '/',
      },
    ]);
    await pipeline.bytes('https://images.jcomic.net/new-cover.jpg');
    expect(sent!.headers['Cookie'], 'jcomic_access=server-issued');
    await pipeline.bytes('https://unrelated.test/new-cover.jpg');
    expect(sent!.headers.containsKey('Cookie'), false);
  });
}
