import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/js/source_web_runtime.dart';
import 'package:lume_box/core/net/ios_image_network.dart';
import 'package:lume_box/core/net/network_cancellation.dart';
import 'package:lume_box/core/net/network_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final handshake = PlatformException(
    code: 'tls_handshake',
    details: {'domain': 'NSURLErrorDomain', 'code': -1200},
  );
  const url = 'https://fixture.test/api.php/provide/vod/?ac=detail';
  setUp(() {
    messenger.setMockMethodCallHandler(
      IosImageNetwork.channel,
      (_) async => throw handshake,
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(IosImageNetwork.channel, null);
    messenger.setMockMethodCallHandler(SourceWebRuntime.channel, null);
  });
  Map<String, Object> reply({String body = '{"list":[]}', String at = url}) => {
    'url': at,
    'status': 200,
    'html': '',
    'result': {'body': body, 'contentType': 'application/json', 'url': at},
  };

  test('iOS text GET TLS failure retries once using WebKit and returns original JSON', () async {
    var renders = 0;
    messenger.setMockMethodCallHandler(SourceWebRuntime.channel, (call) async {
      if (call.method != 'render') return null;
      renders++;
      final args = call.arguments as Map;
      expect(args['url'], url);
      expect(args['method'], 'GET');
      expect(args['includeHtml'], false);
      expect(args['allowBadCertificate'], isNull);
      expect((args['headers'] as Map)['Referer'], 'https://fixture.test/');
      return reply(body: '{"list":[{"vod_name":"示例"}]}');
    });
    final response = await IosImageNetwork.send(
      const NetworkRequest(
        url: url,
        textResponse: true,
        headers: {'Referer': 'https://fixture.test/'},
      ),
    );
    expect(response.statusCode, 200);
    expect(
      (jsonDecode(utf8.decode(response.body)) as Map)['list'],
      hasLength(1),
    );
    expect(response.headers['content-type'], contains('charset=utf-8'));
    expect(renders, 1);
  });

  test(
    'certificate errors remain errors and never use the compatibility path',
    () async {
      messenger.setMockMethodCallHandler(
        IosImageNetwork.channel,
        (_) async => throw PlatformException(
          code: 'certificate',
          details: {'domain': 'NSURLErrorDomain', 'code': -1202},
        ),
      );
      messenger.setMockMethodCallHandler(SourceWebRuntime.channel, (_) async {
        fail('certificate failures must not retry in WebKit');
      });
      await expectLater(
        IosImageNetwork.send(
          const NetworkRequest(url: url, textResponse: true),
        ),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test('binary, credential, range, POST and no-redirect requests preserve their original transport', () async {
    messenger.setMockMethodCallHandler(SourceWebRuntime.channel, (_) async {
      fail('this request is not eligible for text retry');
    });
    for (final request in [
      const NetworkRequest(url: url),
      const NetworkRequest(
        url: url,
        textResponse: true,
        method: 'POST',
        body: 'payload',
      ),
      const NetworkRequest(
        url: url,
        textResponse: true,
        headers: {'Cookie': 'session=private'},
      ),
      const NetworkRequest(
        url: url,
        textResponse: true,
        headers: {'Authorization': 'secret'},
      ),
      const NetworkRequest(
        url: url,
        textResponse: true,
        headers: {'Range': 'bytes=0-128'},
      ),
      const NetworkRequest(
        url: url,
        textResponse: true,
        followRedirects: false,
      ),
      const NetworkRequest(
        url: url,
        textResponse: true,
        proxy: 'http://localhost:8080',
      ),
    ]) {
      await expectLater(
        IosImageNetwork.send(request),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'original code',
            'tls_handshake',
          ),
        ),
      );
    }
  });

  test(
    'invalid/oversized WebKit replies preserve the original TLS failure',
    () async {
      for (final result in [
        reply(at: 'https://elsewhere.test/'),
        reply(body: '123456'),
      ]) {
        messenger.setMockMethodCallHandler(
          SourceWebRuntime.channel,
          (call) async => call.method == 'render' ? result : null,
        );
        await expectLater(
          IosImageNetwork.send(
            const NetworkRequest(url: url, textResponse: true, maxBytes: 4),
          ),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'original code',
              'tls_handshake',
            ),
          ),
        );
      }
    },
  );

  test(
    'cancelling a WebKit retry completes promptly and cancels its page',
    () async {
      final started = Completer<void>();
      final delayed = Completer<Object?>();
      var cancelled = false;
      messenger.setMockMethodCallHandler(SourceWebRuntime.channel, (
        call,
      ) async {
        if (call.method == 'render') {
          started.complete();
          return delayed.future;
        }
        if (call.method == 'cancel') cancelled = true;
        return null;
      });
      final token = NetworkCancellation();
      final operation = IosImageNetwork.send(
        NetworkRequest(url: url, textResponse: true, cancellation: token),
      );
      final assertion = expectLater(
        operation,
        throwsA(isA<NetworkCancelled>()),
      );
      await started.future;
      token.cancel();
      await assertion.timeout(const Duration(seconds: 1));
      expect(cancelled, isTrue);
      delayed.complete(reply());
      await Future<void>.delayed(Duration.zero);
    },
  );
}
