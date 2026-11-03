import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/js/source_web_runtime.dart';
import 'package:lume_box/core/net/site_session_pool.dart';
import 'package:lume_box/core/net/waf_auto_verify.dart';
import 'package:lume_box/core/session/section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(SourceWebRuntime.channel, null),
  );

  test('原生保留的验证页自动交接，成功后同步存储并允许恢复源解析', () async {
    const url = 'https://retained.example/list';
    messenger.setMockMethodCallHandler(SourceWebRuntime.channel, (call) async {
      if (call.method == 'render') {
        throw PlatformException(code: 'verification');
      }
      if (call.method == 'verify') {
        return {
          'verified': true,
          'userAgent': 'browser-test',
          'verificationSession': {
            'url': url,
            'cookies': [
              {
                'domain': 'retained.example',
                'path': '/',
                'name': '__Host-proof',
                'value': 'yes',
                'secure': true,
                'httpOnly': true,
              },
            ],
            'localStorage': {'proof': 'local'},
            'sessionStorage': {'proof': 'session'},
          },
        };
      }
      return null;
    });
    final runtime = SourceWebRuntime('video:native');
    addTearDown(() {
      runtime.dispose();
      WafAutoVerify.resetForTesting();
      SiteSessionPool.shared.clear();
    });
    await expectLater(
      runtime.invoke('render', {'url': url}),
      throwsA(isA<SourceWebVerificationException>()),
    );
    expect(SourceWebRuntime.hasRetained(url), true);
    WafAutoVerify.install(({
      required section,
      required sourceId,
      required sourceName,
      required url,
    }) async {
      final result = await SourceWebRuntime.verifyRetained(url);
      return result?['verified'] == true;
    });
    expect(
      await WafAutoVerify.run(
        section: Section.video,
        sourceId: 'native',
        sourceName: '原生验证',
        url: url,
      ),
      true,
    );
    expect(SourceWebRuntime.hasRetained(url), false);
    expect(SiteSessionPool.shared.storageFor(url)['sessionStorage'], {
      'proof': 'session',
    });
    expect(
      SiteSessionPool.shared.headersFor(url, {})['Cookie'],
      '__Host-proof=yes',
    );
  });

  test('动态网页桥保留交互、表单和返回媒体，超时有界', () async {
    late MethodCall sent;
    messenger.setMockMethodCallHandler(SourceWebRuntime.channel, (call) async {
      sent = call;
      return {
        'url': 'https://fixture.invalid/',
        'html': '<h1>完成</h1>',
        'result': 7,
        'media': [
          {
            'url': 'https://cdn.invalid/movie.m3u8',
            'headers': {'Referer': 'https://fixture.invalid/'},
          },
        ],
      };
    });
    final runtime = SourceWebRuntime('video:a');
    final value = await runtime.invoke('render', {
      'url': 'https://fixture.invalid/',
      'method': 'post',
      'body': 'q=hello',
      'timeoutMs': 50000,
      'waitForSelector': '.ready',
      'steps': [
        {'type': 'fill', 'selector': '#q', 'value': "a'\\b"},
        {'type': 'click', 'selector': '#search'},
      ],
      'script': 'return 7;',
    }) as Map;
    expect(sent.method, 'render');
    expect(sent.arguments['timeoutMs'], 8000);
    expect(sent.arguments['method'], 'POST');
    expect(sent.arguments['steps'][0]['value'], "a'\\b");
    expect(value['result'], 7);
    expect(value['media'][0]['headers']['Referer'], 'https://fixture.invalid/');
    runtime.dispose();
  });

  test('非法地址、步骤和过大HTML在进入原生层前拒绝', () async {
    messenger.setMockMethodCallHandler(
      SourceWebRuntime.channel,
      (_) async => fail('不得进入原生层'),
    );
    final runtime = SourceWebRuntime('video:invalid');
    for (final url in [
      'file:///private/a',
      'javascript:1',
      'https://u:p@fixture.invalid',
    ]) {
      await expectLater(
        runtime.invoke('render', {'url': url}),
        throwsFormatException,
      );
    }
    await expectLater(
      runtime.invoke('render', {
        'url': 'https://fixture.invalid',
        'steps': [
          {'type': 'unknown'},
        ],
      }),
      throwsFormatException,
    );
    await expectLater(
      runtime.invoke('extract', {
        'html': 'x' * (2 * 1024 * 1024 + 1),
        'fields': {'x': {}},
      }),
      throwsFormatException,
    );
    await expectLater(
      runtime.invoke('extract', {'html': '', 'fields': {}}),
      throwsFormatException,
    );
    runtime.dispose();
  });

  test('源释放取消未完成网页且拒绝迟到结果', () async {
    final pending = Completer<Object?>();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(SourceWebRuntime.channel, (call) async {
      calls.add(call);
      if (call.method == 'bridge.close') return null;
      if (call.method == 'cancel') {
        pending.complete({'html': 'late'});
        return null;
      }
      return pending.future;
    });
    final runtime = SourceWebRuntime('video:cancel');
    final future = runtime.invoke('render', {'url': 'https://fixture.invalid'});
    await Future<void>.delayed(Duration.zero);
    final expectation = expectLater(future, throwsStateError);
    runtime.dispose();
    await expectation;
    expect(calls.map((e) => e.method), ['render', 'bridge.close', 'cancel']);
    expect(calls[0].arguments['requestId'], calls.last.arguments['requestId']);
    await expectLater(
      runtime.invoke('render', {'url': 'https://fixture.invalid'}),
      throwsStateError,
    );
  });

  test('CSS解析参数与绝对地址规则原样交给SwiftSoup', () async {
    messenger.setMockMethodCallHandler(SourceWebRuntime.channel, (call) async {
      expect(call.method, 'extract');
      expect(call.arguments['rowSelector'], '.card');
      expect(call.arguments['fields']['url']['attribute'], 'abs:href');
      expect(call.arguments['baseUrl'], 'https://fixture.invalid/list/');
      return [
        {'title': '标题', 'url': 'https://fixture.invalid/watch/1'},
      ];
    });
    final runtime = SourceWebRuntime('video:html');
    final rows = await runtime.invoke('extract', {
      'html': '<a href="../watch/1">标题</a>',
      'rowSelector': '.card',
      'baseUrl': 'https://fixture.invalid/list/',
      'fields': {
        'url': {'selector': 'a', 'attribute': 'abs:href'},
      },
    }) as List;
    expect(rows.single['url'], 'https://fixture.invalid/watch/1');
    runtime.dispose();
  });

  test('验证页保留网页视图标记，429单独提示等待，坏响应不伪装空列表', () async {
    Object? response = {'requiresVerification': true};
    messenger.setMockMethodCallHandler(
      SourceWebRuntime.channel,
      (_) async => response,
    );
    final runtime = SourceWebRuntime('video:verify');
    await expectLater(
      runtime.invoke('render', {'url': 'https://fixture.invalid'}),
      throwsA(predicate((e) => '$e'.contains('NEED_WEBVIEW_VERIFY'))),
    );
    response = {'status': 429, 'html': 'busy'};
    await expectLater(
      runtime.invoke('render', {'url': 'https://fixture.invalid'}),
      throwsA(
        predicate(
          (e) => '$e'.contains('429') && !'$e'.contains('NEED_WEBVIEW_VERIFY'),
        ),
      ),
    );
    response = null;
    await expectLater(
      runtime.invoke('render', {'url': 'https://fixture.invalid'}),
      throwsFormatException,
    );
    runtime.dispose();
  });

  test('旧安装包缺少原生能力时明确报错', () async {
    final runtime = SourceWebRuntime('video:legacy');
    await expectLater(
      runtime.invoke('render', {'url': 'https://fixture.invalid'}),
      throwsUnsupportedError,
    );
    runtime.dispose();
  });
}
