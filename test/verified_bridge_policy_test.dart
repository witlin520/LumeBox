import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/net/verified_bridge_policy.dart';
import 'package:lume_box/core/js/source_web_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final policy = VerifiedBridgePolicy({
    'origin': 'https://source.example',
    'paths': ['/api/search'],
  });
  test('仅允许精确同源路径，拒绝跨域、凭据、编码与方法绕过', () {
    for (final value in [
      {'url': 'https://evil.example/api/search'},
      {'url': 'https://source.example.evil/api/search'},
      {'url': 'https://user:secret@source.example/api/search'},
      {'url': 'https://source.example/other'},
      {'url': 'https://source.example/%2fapi/search'},
      {'url': 'https://source.example/api/search', 'method': 'DELETE'},
      for (final header in [
        'Cookie',
        'Authorization',
        'Host',
        'Origin',
        'Referer',
        'Sec-Fetch-Site',
      ])
        {
          'url': 'https://source.example/api/search',
          'headers': {header: 'secret'},
        },
    ]) {
      expect(() => policy.validate(value), throwsFormatException);
    }
    final result = policy.validate({
      'url': 'https://source.example/api/search?q=test',
      'method': 'post',
      'body': 'query',
      'headers': {'x-source-sign': 'signature'},
      'timeoutMs': 99999,
    });
    expect(result['timeoutMs'], 8000);
    expect(result['method'], 'POST');
    for (final paths in [
      [],
      ['/*'],
      ['//elsewhere'],
      ['/a/../b'],
      ['/a/./b'],
      ['/a%2fb'],
    ]) {
      expect(
        () => VerifiedBridgePolicy({
          'origin': 'https://source.example',
          'paths': paths,
        }),
        throwsFormatException,
      );
    }
  });
  test('请求桥验证失败不能配置；声明前和释放后不能请求，且限制并发', () async {
    var verified = false;
    final waiting = Completer<Object?>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SourceWebRuntime.channel, (call) async {
      if (call.method == 'bridge.configure' && !verified) {
        throw PlatformException(code: 'bridge_unverified');
      }
      if (call.method == 'bridge.request') return waiting.future;
      return true;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SourceWebRuntime.channel, null),
    );
    final runtime = SourceWebRuntime('source-scope');
    await expectLater(
      runtime.bridge('request', {'url': 'https://source.example/api/search'}),
      throwsStateError,
    );
    final options = {
      'origin': 'https://source.example',
      'paths': ['/api/search'],
    };
    await expectLater(
      runtime.bridge('configure', options),
      throwsA(isA<PlatformException>()),
    );
    verified = true;
    await runtime.bridge('configure', options);
    final a = runtime.bridge('request', {
      'url': 'https://source.example/api/search',
    });
    final b = runtime.bridge('request', {
      'url': 'https://source.example/api/search',
    });
    await expectLater(
      runtime.bridge('request', {'url': 'https://source.example/api/search'}),
      throwsStateError,
    );
    waiting.complete({'status': 200, 'headers': {}, 'bodyText': '{}'});
    await Future.wait([a, b]);
    runtime.dispose();
    await expectLater(
      runtime.bridge('request', {'url': 'https://source.example/api/search'}),
      throwsStateError,
    );
  });
}
