import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume_box/core/tmdb/tmdb.dart';
import 'package:lume_box/core/tmdb/tmdb_connection_failure.dart';

void main() {
  test('网络诊断区分 DNS、超时和 TLS，异常中的密钥不进入提示', () {
    String describe(Object e, {bool proxy = false}) =>
        TmdbConnectionFailure.describe(
          e,
          api: true,
          customEndpoint: proxy,
          globalProxy: false,
        );
    final dns = describe(
      http.ClientException(
        'Failed host lookup',
        Uri.parse('https://tmdb.test?api_key=secret'),
      ),
    );
    expect(dns, contains('DNS'));
    expect(dns, contains('官方API地址'));
    expect(dns, isNot(contains('secret')));
    expect(describe(TimeoutException('secret')), contains('超时'));
    expect(
      describe(const HandshakeException('secret'), proxy: true),
      contains('TLS'),
    );
    expect(describe(const FormatException('secret')), contains('地址格式'));
    expect(
      describe(StateError('https://tmdb.test?api_key=secret')),
      isNot(contains('secret')),
    );
  });

  for (final status in [401, 403, 429, 503]) {
    test('API HTTP $status 返回可操作诊断且不包含请求密钥', () async {
      final client = TmdbClient(
        TmdbSettings()..apiKey = 'secret-fixture',
        client: MockClient((_) async => http.Response('{}', status)),
      );
      addTearDown(client.dispose);
      await expectLater(
        client.testApi(),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'status', contains('$status'))
              .having(
                (e) => e.message,
                'redacted',
                isNot(contains('secret-fixture')),
              ),
        ),
      );
    });
  }
}
