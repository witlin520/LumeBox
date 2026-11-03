import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/js/source_web_runtime.dart';
import 'package:lume_box/core/net/lume_net.dart';
import 'package:lume_box/core/net/network_cancellation.dart';
import 'package:lume_box/core/net/site_session_pool.dart';
import 'package:lume_box/core/net/web_session_lifecycle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const origin = 'https://lifecycle.example';
  final options = {
    'origin': origin,
    'paths': ['/api/search'],
  };
  final request = {'url': '$origin/api/search'};
  final calls = <MethodCall>[];
  late SourceWebRuntime runtime;
  setUp(() {
    calls.clear();
    runtime = SourceWebRuntime('video:lifecycle');
    messenger.setMockMethodCallHandler(SourceWebRuntime.channel, (call) async {
      calls.add(call);
      return call.method == 'bridge.configure'
          ? true
          : {'status': 200, 'bodyText': '{}'};
    });
  });
  tearDown(() async {
    runtime.dispose();
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(SourceWebRuntime.channel, null);
    LumeNet.resetForTesting();
  });

  test('清除业务域会话撤销旧桥，其他域保持有效', () async {
    await runtime.bridge('configure', options);
    SiteSessionPool.shared.forgetHosts({'unrelated.example'});
    expect((await runtime.bridge('request', request) as Map)['status'], 200);
    SiteSessionPool.shared.forgetHosts({'lifecycle.example'});
    await expectLater(
      runtime.bridge('request', request),
      throwsA(isA<SourceWebFailure>()),
    );
    expect(calls.where((c) => c.method == 'bridge.request').length, 1);
    expect(calls.any((c) => c.method == 'session.invalidate'), true);
  });

  test('修改代理或站点UA撤销旧桥，单纯修改并发不撤销', () async {
    await runtime.bridge('configure', options);
    LumeNet.apply(LumeNet.settings.copyWith(globalConcurrency: 8));
    await runtime.bridge('request', request);
    LumeNet.apply(LumeNet.settings.copyWith(proxy: 'http://127.0.0.1:7890'));
    await expectLater(
      runtime.bridge('request', request),
      throwsA(isA<SourceWebFailure>()),
    );
    await runtime.bridge('configure', options);
    SiteSessionPool.shared.setUserAgent(origin, 'new-browser');
    await expectLater(
      runtime.bridge('request', request),
      throwsA(isA<SourceWebFailure>()),
    );
  });

  test('会话失效时丢弃在途响应，不能把旧结果恢复给页面', () async {
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(SourceWebRuntime.channel, (call) async {
      if (call.method == 'bridge.request') return pending.future;
      return true;
    });
    await runtime.bridge('configure', options);
    final operation = runtime.bridge('request', request);
    final assertion = expectLater(operation, throwsA(isA<SourceWebFailure>()));
    WebSessionLifecycle.invalidate(hosts: {'lifecycle.example'});
    pending.complete({'status': 200, 'bodyText': 'old-result'});
    await assertion;
  });

  test('取消请求立即结束等待并关闭桥，迟到响应无效', () async {
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(SourceWebRuntime.channel, (call) async {
      calls.add(call);
      return call.method == 'bridge.request' ? pending.future : true;
    });
    await runtime.bridge('configure', options);
    final token = NetworkCancellation();
    final operation = token.run(() => runtime.bridge('request', request));
    final assertion = expectLater(operation, throwsA(isA<NetworkCancelled>()));
    token.cancel();
    await assertion;
    pending.complete({'status': 200, 'bodyText': 'late'});
    await Future<void>.delayed(Duration.zero);
    expect(calls.any((c) => c.method == 'bridge.close'), true);
    await expectLater(runtime.bridge('request', request), throwsStateError);
  });

  test('切换源释放时不等待平台返回，迟到响应不会影响新源', () async {
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(
      SourceWebRuntime.channel,
      (call) async => call.method == 'bridge.request' ? pending.future : true,
    );
    await runtime.bridge('configure', options);
    final operation = runtime.bridge('request', request);
    final assertion = expectLater(operation, throwsA(isA<NetworkCancelled>()));
    runtime.dispose();
    await assertion;
    pending.complete({'status': 200, 'bodyText': 'late'});
    final next = SourceWebRuntime('video:next');
    addTearDown(next.dispose);
    await next.bridge('configure', options);
  });

  test('验证中取消不会导入迟到的Cookie或存储', () async {
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(SourceWebRuntime.channel, (call) async {
      calls.add(call);
      if (call.method == 'render') {
        throw PlatformException(code: 'verification');
      }
      if (call.method == 'verify') return pending.future;
      return null;
    });
    await expectLater(
      runtime.invoke('render', {'url': origin}),
      throwsA(isA<SourceWebVerificationException>()),
    );
    final token = NetworkCancellation();
    final operation = token.run(() => SourceWebRuntime.verifyRetained(origin));
    final assertion = expectLater(operation, throwsA(isA<NetworkCancelled>()));
    token.cancel();
    await assertion;
    pending.complete({
      'verified': true,
      'verificationSession': {
        'url': origin,
        'cookies': [],
        'localStorage': {'cancelled-proof': 'secret'},
        'sessionStorage': {},
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(
      SiteSessionPool.shared.storageFor(origin)['localStorage'],
      isNot(contains('cancelled-proof')),
    );
    expect(calls.any((c) => c.method == 'cancel'), true);
  });

  test('403保留拒绝类型，不能据此自动判定验证码失败；平台错误不泄露详情', () async {
    var fail = false;
    messenger.setMockMethodCallHandler(SourceWebRuntime.channel, (call) async {
      if (call.method == 'bridge.configure') return true;
      if (fail) {
        throw PlatformException(
          code: 'bridge_request',
          message: 'Cookie: private-cookie',
        );
      }
      return {'status': 403, 'bodyText': 'signature rejected'};
    });
    await runtime.bridge('configure', options);
    expect(
      (await runtime.bridge('request', request) as Map)['failureKind'],
      'source_rejected',
    );
    fail = true;
    await expectLater(
      runtime.bridge('request', request),
      throwsA(
        predicate(
          (e) =>
              e is SourceWebFailure &&
              e.code == 'bridge_request' &&
              !'$e'.contains('private-cookie') &&
              !'$e'.contains('NEED_WEBVIEW_VERIFY'),
        ),
      ),
    );
  });
}
