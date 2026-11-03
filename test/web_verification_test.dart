import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/net/web_verification.dart';
import 'package:lume_box/core/net/site_session_pool.dart';

void main() {
  const target = 'https://books.example/list';
  final baseline = <String, Object?>{
    'kind': 'unknown',
    'business': false,
    'url': target,
  };
  Map<String, Object?> page([Map<String, Object?> values = const {}]) => {
    'url': target,
    'ready': true,
    'business': true,
    'kind': 'none',
    ...values,
  };
  test('未知验证需业务恢复，Cookie 单独变化不通过', () {
    expect(
      WebVerification.passed(
        baseline,
        page({'business': false}),
        target: target,
        cookieChanged: true,
      ),
      false,
    );
    expect(
      WebVerification.passed(
        baseline,
        page({'blocking': true}),
        target: target,
        cookieChanged: true,
      ),
      false,
    );
    expect(
      WebVerification.passed(
        baseline,
        page(),
        target: target,
        cookieChanged: false,
      ),
      true,
    );
    expect(
      WebVerification.passed(
        {...baseline, 'business': true},
        page(),
        target: target,
        cookieChanged: true,
      ),
      false,
    );
  });
  test('失败提示、重型风控、第三方 iframe 和未加载完都不能通过', () {
    for (final value in [
      page({'retry': true}),
      page({'heavy': true}),
      page({'url': 'https://captcha.example/ok'}),
      page({'url': 'about:blank'}),
      page({'url': '/loading'}),
      page({'ready': false}),
    ]) {
      expect(
        WebVerification.passed(
          baseline,
          value,
          target: target,
          cookieChanged: true,
        ),
        false,
      );
    }
  });
  test('已知厂商的凭证需业务 DOM，活动验证控件阻止 Cookie 误判', () {
    final known = {...baseline, 'kind': 'cloudflare'};
    expect(
      WebVerification.passed(
        known,
        page({'token': true, 'business': false}),
        target: target,
        cookieChanged: false,
      ),
      false,
    );
    expect(
      WebVerification.passed(
        known,
        page({'token': true}),
        target: target,
        cookieChanged: false,
      ),
      true,
    );
    expect(
      WebVerification.passed(
        known,
        page({'blocking': true}),
        target: target,
        cookieChanged: true,
      ),
      false,
    );
    expect(
      WebVerification.passed(
        known,
        page(),
        target: target,
        cookieChanged: false,
      ),
      false,
    );
    expect(
      WebVerification.passed(
        known,
        page({
          'localStorage': {'proof': 'new'},
        }),
        target: target,
        cookieChanged: false,
      ),
      true,
    );
  });
  test('Cookie 指纹覆盖全部名称和路径，忽略验证 iframe 与统计域', () {
    final a = [
      {
        'domain': '.books.example',
        'path': '/',
        'name': '__Host-custom',
        'value': 'old',
      },
    ];
    final b = [
      a.first,
      {'domain': 'captcha.example', 'path': '/', 'name': 'token', 'value': '1'},
    ];
    expect(
      WebVerification.cookieFingerprint(a, target),
      WebVerification.cookieFingerprint(b, target),
    );
    expect(
      WebVerification.cookieFingerprint([
        {...a.first, 'value': 'new'},
      ], target),
      isNot(WebVerification.cookieFingerprint(a, target)),
    );
  });
  test('全局池保留 Cookie 属性及业务源存储，不跨域或协议同步', () {
    final pool = SiteSessionPool();
    pool.importVerification(target, {
      'url': target,
      'cookies': [
        {
          'name': '__Host-proof',
          'value': 'pass',
          'domain': 'books.example',
          'path': '/',
          'secure': true,
          'httpOnly': true,
        },
        {
          'name': 'thirdParty',
          'value': 'no',
          'domain': 'captcha.example',
          'path': '/',
        },
      ],
      'localStorage': {'proof': 'yes'},
      'sessionStorage': {'session': 'yes'},
    });
    expect(pool.headersFor(target, {})['Cookie'], '__Host-proof=pass');
    expect(pool.headersFor('http://books.example/list', {})['Cookie'], isNull);
    expect(pool.storageFor(target)['sessionStorage'], {'session': 'yes'});
    expect(pool.storageFor('https://other.example')['localStorage'], isEmpty);
    pool.importVerification(target, {
      'url': 'https://captcha.example',
      'localStorage': {'proof': 'wrong'},
    });
    expect(pool.storageFor(target)['localStorage'], {'proof': 'yes'});
    pool.forgetHosts({'books.example'});
    expect(pool.storageFor(target)['localStorage'], isEmpty);
  });
  test('存储快照不截断后面的键或长凭证，键顺序不构成变化', () {
    final pool = SiteSessionPool();
    final values = {
      for (var i = 0; i < 140; i++) 'key-$i': 'value-$i',
      'proof': 'x' * 9000,
    };
    pool.importVerification(target, {'url': target, 'localStorage': values});
    expect(pool.storageFor(target)['localStorage'], values);
    expect(
      WebVerification.passed(
        {
          'kind': 'geetest',
          'business': false,
          'url': target,
          'localStorage': {'a': '1', 'b': '2'},
        },
        page({
          'localStorage': {'b': '2', 'a': '1'},
        }),
        target: target,
        cookieChanged: false,
      ),
      false,
    );
  });
  test('探针返回值可接受 WebKit 双重 JSON 编码且拒绝无效数据', () {
    expect(
      WebVerification.decode(r'"{\"kind\":\"unknown\"}"')?['kind'],
      'unknown',
    );
    expect(WebVerification.decode('broken'), isNull);
  });
}
