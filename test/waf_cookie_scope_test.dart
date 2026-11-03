import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/net/waf.dart';

void main() {
  test('92 漫画会话不被其他站点的同名 clearance 覆盖', () {
    final cookies = webViewCookiesForUrl([
      {'name': 'cf_clearance', 'value': '92-session', 'domain': '.92mh.com', 'path': '/'},
      {'name': 'cf_clearance', 'value': 'other-site', 'domain': '.other.com', 'path': '/'},
      {'name': 'cf_clearance', 'value': 'lookalike', 'domain': '.evil92mh.com', 'path': '/'},
    ], 'https://www.92mh.com/list/update/1/');
    expect(cookies, {'cf_clearance': '92-session'});
  });

  test('Cookie 的路径、过期、Secure 与 host-only 范围均生效', () {
    final future = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch / 1000;
    final cookies = webViewCookiesForUrl([
      {'name': 'valid', 'value': '1', 'domain': '.92mh.com', 'path': '/list', 'secure': true, 'expires': future},
      {'name': 'host', 'value': '1', 'domain': '92mh.com', 'path': '/'},
      {'name': 'expired', 'value': '1', 'domain': '.92mh.com', 'path': '/', 'expires': 1},
      {'name': 'wrong-path', 'value': '1', 'domain': '.92mh.com', 'path': '/listings'},
    ], 'https://www.92mh.com/list/update/');
    expect(cookies, {'valid': '1'});
    expect(webViewCookiesForUrl([
      {'name': 'secure', 'value': '1', 'domain': '.92mh.com', 'path': '/', 'secure': true},
    ], 'http://www.92mh.com/'), isEmpty);
  });

  test('同名 Cookie 优先选择更具体的路径，与仓库返回顺序无关', () {
    final entries = [
      {'name': 'session', 'value': 'list', 'domain': '.92mh.com', 'path': '/list'},
      {'name': 'session', 'value': 'root', 'domain': '.92mh.com', 'path': '/'},
    ];
    for (final list in [entries, entries.reversed.toList()]) {
      expect(webViewCookiesForUrl(list, 'https://www.92mh.com/list/update/'), {'session': 'list'});
    }
  });
}
