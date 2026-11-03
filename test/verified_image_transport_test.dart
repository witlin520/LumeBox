import 'package:lume_box/core/net/ios_verified_webview.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/net/ios_image_network.dart';
import 'package:lume_box/core/net/network_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('媒体只取匹配域名的验证Cookie，不带主站登录Cookie', () {
    final headers = IosVerifiedWebView.scopedResourceHeaders(
      'https://cdn.example/video.mp4',
      const {},
      [
        {
          'name': 'cf_clearance',
          'value': 'source-token',
          'domain': 'source.example',
          'path': '/',
        },
        {
          'name': 'cf_clearance',
          'value': 'cdn-token',
          'domain': 'cdn.example',
          'path': '/',
        },
        {
          'name': 'login',
          'value': 'private',
          'domain': 'cdn.example',
          'path': '/',
        },
      ],
    );
    expect(headers, {'Cookie': 'cf_clearance=cdn-token'});
  });

  test('验证后的POST保留方法和请求体，不误改为GET', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late MethodCall nativeCall;
    late MethodCall browserCall;
    messenger.setMockMethodCallHandler(
      const MethodChannel('lumebox/image_network'),
      (call) async {
        nativeCall = call;
        return {
          'status': 403,
          'body': Uint8List.fromList('<title>Just a moment</title>'.codeUnits),
          'headers': <String, String>{},
        };
      },
    );
    messenger.setMockMethodCallHandler(const MethodChannel('lumebox/webview'), (
      call,
    ) async {
      browserCall = call;
      return {
        'status': 200,
        'body': Uint8List.fromList([123, 125]),
        'contentType': 'application/json',
      };
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('lumebox/image_network'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('lumebox/webview'),
        null,
      );
    });
    final response = await IosImageNetwork.send(
      const NetworkRequest(
        url: 'https://site.example/api/list',
        method: 'POST',
        body: 'page=1',
        source: 'video:site',
        reuseVerifiedSession: true,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      ),
    );
    expect(nativeCall.arguments['method'], 'POST');
    expect(nativeCall.arguments['body'], 'page=1');
    expect(browserCall.arguments['method'], 'POST');
    expect(browserCall.arguments['body'], 'page=1');
    expect(response.statusCode, 200);
    expect(response.body, [123, 125]);
  });

  test('已验证图片CF转入WebKit，保持二进制响应且不复制请求Cookie', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('lumebox/image_network'),
      (_) async => {
        'status': 403,
        'body': Uint8List.fromList('<title>Just a moment</title>'.codeUnits),
        'headers': <String, String>{},
      },
    );
    late MethodCall browserCall;
    messenger.setMockMethodCallHandler(const MethodChannel('lumebox/webview'), (
      call,
    ) async {
      browserCall = call;
      return {
        'status': 200,
        'body': Uint8List.fromList([0, 255, 128, 1]),
        'contentType': 'image/webp',
      };
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('lumebox/image_network'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('lumebox/webview'),
        null,
      );
    });
    final response = await IosImageNetwork.send(
      const NetworkRequest(
        url: 'https://images.example/a.webp',
        source: '封面:comic:test',
        reuseVerifiedSession: true,
        headers: {'User-Agent': 'verified-UA', 'Cookie': 'source-private=1'},
      ),
    );
    expect(response.body, [0, 255, 128, 1]);
    expect(browserCall.method, 'readVerifiedResource');
    expect(browserCall.arguments['requestId'], startsWith('verified-'));
    expect(Map.of(browserCall.arguments as Map)..remove('requestId'), {
      'url': 'https://images.example/a.webp',
      'userAgent': 'verified-UA',
      'method': 'GET',
      'headers': <String, String>{},
    });
  });
}
