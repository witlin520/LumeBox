import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/net/network_settings.dart';
import 'package:lume_box/core/net/network_queue.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/source.dart';

void main() {
  test('证书校验失败立即结束请求，不重复占用图片下载队列', () async {
    var attempts = 0;
    final queue = NetworkQueue(
      settings: const NetworkSettings(maxRetries: 3),
      sender: (_) async {
        attempts++;
        throw const HandshakeException('CERTIFICATE_VERIFY_FAILED');
      },
    );
    await expectLater(
      queue.send(
        const NetworkRequest(
          url: 'https://bad.example/cover.jpg',
          source: '图片缓存',
        ),
      ),
      throwsA(isA<HandshakeException>()),
    );
    expect(attempts, 1);
  });
  test('封面管线继承单源配置，同 URL 的不同源缓存隔离且随宿主管线释放', () {
    final root = Directory.systemTemp.createTempSync('image-source-scope');
    addTearDown(() => root.deleteSync(recursive: true));
    final base = SectionImagePipeline(cacheDir: root.path);
    const profile = NetworkProfile(
      userAgent: 'source-UA',
      proxy: 'http://127.0.0.1:8080',
      allowBadCertificate: true,
    );
    final first = base.forSource(Section.video, 'first', profile);
    final second = base.forSource(Section.video, 'second', NetworkProfile.none);
    expect(first.network.userAgent, 'source-UA');
    expect(first.network.proxy, profile.proxy);
    expect(first.network.allowBadCertificate, true);
    expect(second.network.allowBadCertificate, false);
    expect(base.forSource(Section.video, 'first', profile), same(first));
    const cover = 'https://cdn.example/a.jpg';
    expect(first.cachePathFor(cover), isNot(second.cachePathFor(cover)));
    base.dispose();
    expect(first.isDisposed, true);
    expect(second.isDisposed, true);
  });

  test('首页和列表兼容常用 thumbnail / image / poster 封面字段', () {
    for (final field in ['cover', 'thumbnail', 'image', 'poster']) {
      final item = SourceItem.parse({
        'id': '1',
        'title': '作品',
        field: 'https://img.example/a.jpg',
      });
      expect(item?.cover, 'https://img.example/a.jpg', reason: field);
    }
  });
}
