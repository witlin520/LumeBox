import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/services.dart';
import 'package:lume_box/core/net/lume_http.dart';
import 'package:lume_box/core/reading/translation_http_client.dart';

void main() {
  test(
    'TLS handshake retry preserves JSON and authorization without redirecting',
    () async {
      var calls = 0;
      final primary = LumeHttp(
        client: MockClient(
          (_) async => throw PlatformException(
            code: 'tls_handshake',
            details: {'domain': 'NSURLErrorDomain', 'code': -1200},
          ),
        ),
      );
      final client = TranslationHttpClient(
        network: primary,
        handshakeFallback: MockClient((request) async {
          calls++;
          expect(
            request.url.toString(),
            'https://translation.test/v1/chat/completions',
          );
          expect(request.followRedirects, isFalse);
          expect(request.headers['authorization'], 'Bearer fixture-key');
          expect(request.body, '{"messages":[]}');
          return http.Response('{"choices":[]}', 200);
        }),
      );
      addTearDown(client.close);
      final request =
          http.Request(
              'POST',
              Uri.parse('https://translation.test/v1/chat/completions'),
            )
            ..headers.addAll({
              'Content-Type': 'application/json',
              'Authorization': 'Bearer fixture-key',
            })
            ..body = '{"messages":[]}';
      final response = await client.send(request);
      expect(response.statusCode, 200);
      expect(calls, 1);
    },
  );
  test(
    'certificate rejection does not retry through another transport',
    () async {
      final client = TranslationHttpClient(
        network: LumeHttp(
          client: MockClient(
            (_) async => throw PlatformException(
              code: 'certificate',
              details: {'domain': 'NSURLErrorDomain', 'code': -1202},
            ),
          ),
        ),
        handshakeFallback: MockClient((_) async {
          fail('certificate failure must remain a failure');
        }),
      );
      addTearDown(client.close);
      final request =
          http.Request('POST', Uri.parse('https://translation.test'))
            ..headers['Content-Type'] = 'application/json'
            ..body = '{}';
      await expectLater(
        client.send(request),
        throwsA(isA<PlatformException>()),
      );
    },
  );
  test(
    'HTTP failures are not replayed and fallback response remains bounded',
    () async {
      final client = TranslationHttpClient(
        network: LumeHttp(
          client: MockClient((_) async => http.Response('unauthorized', 401)),
        ),
        handshakeFallback: MockClient((_) async {
          fail('401 must not resend credentials');
        }),
      );
      addTearDown(client.close);
      final request =
          http.Request('POST', Uri.parse('https://translation.test'))
            ..headers['Content-Type'] = 'application/json'
            ..body = '{}';
      expect((await client.send(request)).statusCode, 401);
      final bounded = TranslationHttpClient(
        maxBytes: 4,
        network: LumeHttp(
          client: MockClient(
            (_) async => throw PlatformException(code: 'tls_handshake'),
          ),
        ),
        handshakeFallback: MockClient(
          (_) async => http.Response('too-large', 200),
        ),
      );
      addTearDown(bounded.close);
      final second = http.Request('POST', Uri.parse('https://translation.test'))
        ..headers['Content-Type'] = 'application/json'
        ..body = '{}';
      await expectLater(bounded.send(second), throwsFormatException);
    },
  );
  test('translation uses source networking, preserves credentials/body and rejects redirects', () async {
    final transport = TranslationHttpClient(
      network: LumeHttp(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.followRedirects, isFalse);
          expect(
            request.headers['authorization'],
            'Bearer private-example-key',
          );
          expect(request.body, '{"messages":[]}');
          return http.Response(
            '{"choices":[]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    addTearDown(transport.close);
    final request = http.Request('POST', Uri.parse('https://translation.test'))
      ..headers['Authorization'] = 'Bearer private-example-key'
      ..body = '{"messages":[]}';
    final result = await transport.send(request);
    expect(result.statusCode, 200);
    expect(await result.stream.bytesToString(), '{"choices":[]}');
  });
}
