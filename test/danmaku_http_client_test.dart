import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume_box/core/net/network_queue.dart';
import 'package:lume_box/features/video/danmaku/dandanplay_client.dart';
import 'package:lume_box/features/video/danmaku/danmaku_http_client.dart';

class _ProxyOverride extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'PROXY 127.0.0.1:1';
}

void main() {
  test('本机服务绕过 HTTP 代理，且不发往远程系统网络', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.write('{"ok":true}');
      await request.response.close();
    });
    await HttpOverrides.runWithHttpOverrides(() async {
      final client = DanmakuHttpClient(
        nativeSender: (_) async {
          fail('回环请求不应送往系统代理');
        },
      );
      addTearDown(client.close);
      final result = await client.get(
        Uri.parse('http://127.0.0.1:${server.port}/token/_health'),
      );
      expect(result.statusCode, 200);
      expect(result.body, '{"ok":true}');
    }, _ProxyOverride());
  });

  test('系统网络保留手动跳转，规范化响应头且不向 CDN 转发签名', () async {
    final requests = <NetworkRequest>[];
    final transport = DanmakuHttpClient(
      nativeSender: (request) async {
        requests.add(request);
        expect(request.followRedirects, isFalse);
        if (requests.length == 1) {
          expect(request.headers['X-Signature'], isNotEmpty);
          return const NetworkResponse(
            statusCode: 302,
            body: [],
            headers: {'Location': 'https://cdn.example/comments.json'},
          );
        }
        expect(
          request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('x-signature')),
        );
        return NetworkResponse(
          statusCode: 200,
          body: '{"comments":[{"p":"1,1,16777215,user","m":"test"}]}'.codeUnits,
          headers: const {'Content-Type': 'application/json'},
        );
      },
    );
    final client = DandanplayClient(
      credentials: const DandanplayCredentials(
        'app',
        'secret',
        baseUrl: DandanplayCredentials.officialBase,
      ),
      client: transport,
    );
    addTearDown(client.close);
    expect((await client.comments('123')).length, 1);
    expect(requests, hasLength(2));
    client.close();
    await expectLater(
      transport.get(Uri.parse('https://example.org')),
      throwsA(isA<http.ClientException>()),
    );
  });
}
