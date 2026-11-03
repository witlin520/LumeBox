import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume_box/core/net/lume_http.dart';
import 'package:lume_box/core/net/network_settings.dart';

void main() {
  test('验证后的 UA 优先于脚本 UA，与 clearance 配套发送', () async {
    late http.Request sent;
    final transport = LumeHttp(
      client: MockClient((request) async {
        sent = request;
        return http.Response('', 200);
      }),
      sessionCookies: () => 'cf_clearance=92-session',
      sessionUserAgent: () => 'verified-Safari-UA',
    );
    addTearDown(transport.dispose);
    await transport.send(url: 'https://www.92mh.com/list/update/',
        headers: {'user-agent': 'old-script-UA'});
    expect(sent.headers['user-agent'], 'verified-Safari-UA');
    expect(sent.headers['cookie'], 'cf_clearance=92-session');
  });
  test('会话 Cookie 在同一站点树内放行（www / api / 裸域都带上）', () async {
    final sent = <String, Map<String, String>>{};
    final transport = LumeHttp(
      client: MockClient((request) async {
        sent[request.url.host] = request.headers;
        return http.Response('', 200);
      }),
      sessionCookies: () => 'login=1',
    );
    addTearDown(transport.dispose);

    await transport.send(url: 'https://www.example.com/list');
    await transport.send(url: 'https://example.com/detail');
    await transport.send(url: 'https://api.example.com/v1');

    expect(sent['www.example.com']!['cookie'], contains('login=1'));
    expect(
      sent['example.com']!['cookie'],
      contains('login=1'),
      reason: '裸域与 www 视为同一站',
    );
    expect(
      sent['api.example.com']!['cookie'],
      contains('login=1'),
      reason: '子域同样是同一站',
    );
  });

  test('会话 Cookie 不发给别的站点（防仿冒域）', () async {
    final sent = <String, Map<String, String>>{};
    final transport = LumeHttp(
      client: MockClient((request) async {
        sent[request.url.host] = request.headers;
        return http.Response('', 200);
      }),
      sessionCookies: () => 'login=1',
    );
    addTearDown(transport.dispose);

    await transport.send(url: 'https://www.example.com/list');
    await transport.send(url: 'https://evil-example.com/x');
    expect(sent['evil-example.com']!['cookie'], isNull);
  });

  test('小写请求头保留脚本 UA 与 Cookie，并补上验证会话', () async {
    late http.Request sent;
    final client = MockClient((request) async {
      sent = request;
      return http.Response('', 200);
    });
    final transport = LumeHttp(
      client: client,
      profile: const NetworkProfile(userAgent: 'profile-UA', cookie: 'profile=1'),
      sessionCookies: () => 'cf_clearance=fresh',
    );
    addTearDown(transport.dispose);

    await transport.send(
      url: 'https://example.com/list',
      headers: {'user-agent': 'script-UA', 'cookie': 'login=script'},
    );
    expect(sent.headers['user-agent'], 'script-UA');
    expect(sent.headers['cookie'], contains('login=script'));
    expect(sent.headers['cookie'], contains('profile=1'));
    expect(sent.headers['cookie'], contains('cf_clearance=fresh'));
  });

  test('新验证会话覆盖配置中失效的同名 Cookie', () async {
    late http.Request sent;
    final transport = LumeHttp(
      client: MockClient((request) async {
        sent = request;
        return http.Response('', 200);
      }),
      profile: const NetworkProfile(cookie: 'cf_clearance=expired; profile=1'),
      sessionCookies: () => 'cf_clearance=fresh',
    );
    addTearDown(transport.dispose);

    await transport.send(url: 'https://example.com/list');
    expect(sent.headers['cookie'], contains('cf_clearance=fresh'));
    expect(sent.headers['cookie'], isNot(contains('expired')));
  });
}
