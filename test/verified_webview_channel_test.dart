import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/net/ios_verified_webview.dart';
import 'package:lume_box/core/net/network_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(IosVerifiedWebView.channel, null),
  );
  test('保留网页真实状态码与中文正文，不把挑战页误认成成功', () async {
    messenger.setMockMethodCallHandler(IosVerifiedWebView.channel, (
      call,
    ) async {
      expect(call.method, 'readVerifiedPage');
      expect((call.arguments as Map)['userAgent'], 'verified UA');
      expect((call.arguments as Map).containsKey('Cookie'), isFalse);
      return {'status': 403, 'body': '仍需要网页验证', 'contentType': 'text/html'};
    });
    final response = await IosVerifiedWebView.read(
      const NetworkRequest(
        url: 'https://example.com/chapter',
        headers: {'User-Agent': 'verified UA'},
      ),
    );
    expect(response.statusCode, 403);
    expect(utf8.decode(response.body), '仍需要网页验证');
  });
  test('网页正文也遵守源请求读取上限', () async {
    messenger.setMockMethodCallHandler(
      IosVerifiedWebView.channel,
      (_) async => {'status': 200, 'body': '漫画正文', 'contentType': 'text/html'},
    );
    await expectLater(
      IosVerifiedWebView.read(
        const NetworkRequest(url: 'https://example.com/chapter', maxBytes: 4),
      ),
      throwsStateError,
    );
  });
}
