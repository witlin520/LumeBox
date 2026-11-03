import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/net/site_session_pool.dart';

void main() {
  test('浏览器完整快照替换当前域旧Cookie，保留其他站点与HttpOnly', () {
    final pool = SiteSessionPool();
    pool.importCookies([
      {
        'name': 'old',
        'value': 'expired-browser-session',
        'domain': '.site.test',
        'path': '/',
      },
      {'name': 'other', 'value': 'keep', 'domain': 'other.test', 'path': '/'},
    ]);
    pool.importVerification('https://www.site.test', {
      'url': 'https://www.site.test/home',
      'cookies': [
        {
          'name': 'session',
          'value': 'new',
          'domain': '.site.test',
          'path': '/',
          'httpOnly': true,
          'secure': true,
        },
      ],
      'localStorage': {'token': 'origin-scoped'},
    });
    expect(
      pool.headersFor('https://www.site.test/api', {})['Cookie'],
      'session=new',
    );
    expect(pool.headersFor('https://other.test/', {})['Cookie'], 'other=keep');
    expect(pool.storageFor('https://www.site.test')['localStorage'], {
      'token': 'origin-scoped',
    });
    pool.importVerification('https://www.site.test', {
      'url': 'https://challenge.other.test',
      'cookies': [],
    });
    expect(
      pool.headersFor('https://www.site.test/api', {})['Cookie'],
      'session=new',
    );
    pool.importVerification('https://www.site.test', {
      'url': 'https://www.site.test/home',
      'cookies': [],
    });
    expect(pool.headersFor('https://www.site.test/api', {})['Cookie'], isNull);
  });

  test('无Path Cookie遵循请求目录，不漏掉目录自身或泄漏到相似前缀', () {
    final pool = SiteSessionPool();
    pool.absorb('https://site.test/api/login', {
      'set-cookie': 'session=ok; Secure; HttpOnly',
    });
    expect(
      pool.headersFor('https://site.test/api', {})['Cookie'],
      'session=ok',
    );
    expect(
      pool.headersFor('https://site.test/api/list', {})['Cookie'],
      'session=ok',
    );
    expect(pool.headersFor('https://site.test/apix', {})['Cookie'], isNull);
    expect(pool.headersFor('http://site.test/api', {})['Cookie'], isNull);
  });
}
