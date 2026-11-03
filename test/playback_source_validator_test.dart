import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/net/lume_http.dart';
import 'package:lume_box/features/video/playback_source_validator.dart';

void main() {
  test('HLS 只检查当前清单，不请求变体或分片', () async {
    final urls = <Uri>[];
    final validator = PlaybackSourceValidator(
      request: (uri, headers) async {
        urls.add(uri);
        expect(headers['Cookie'], 'session=example');
        return LumeHttpResponse(
          statusCode: 200,
          body: Uint8List.fromList(
            '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nlow.m3u8'.codeUnits,
          ),
          headers: const {'content-type': 'application/vnd.apple.mpegurl'},
        );
      },
    );
    expect(
      await validator.check(Uri.parse('https://example.com/master.m3u8'), {
        'Cookie': 'session=example',
      }),
      isNull,
    );
    expect(urls.map((uri) => uri.path), ['/master.m3u8']);
  });
  test('取消时丢弃迟到的失效结果', () async {
    final pending = Completer<LumeHttpResponse>();
    final validator = PlaybackSourceValidator(
      request: (uri, headers) => pending.future,
    );
    final result = validator.check(
      Uri.parse('https://example.com/a.mp4'),
      const {},
    );
    validator.cancel();
    pending.complete(
      LumeHttpResponse(statusCode: 403, body: Uint8List(0), headers: const {}),
    );
    expect(await result, isNull);
  });
  test('200 HTML 登录或挑战页不可当媒体成功', () async {
    final validator = PlaybackSourceValidator(
      request: (uri, headers) async => LumeHttpResponse(
        statusCode: 200,
        body: Uint8List(0),
        headers: const {'Content-Type': 'text/html'},
      ),
    );
    expect(
      await validator.check(Uri.parse('https://example.com/a.mp4'), const {}),
      contains('网页而非媒体'),
    );
  });
}
