import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/net/waf.dart';

void main() {
  test('200 挑战页可识别，普通 403 防盗链与正文提到 CF 均不弹验证', () {
    expect(
      WafDetector.isChallenge(
        statusCode: 200,
        headers: {'Cf-Mitigated': 'challenge'},
      ),
      true,
    );
    expect(
      WafDetector.isChallenge(
        statusCode: 200,
        body: '<html><title>Just a moment...</title></html>',
      ),
      true,
    );
    expect(
      WafDetector.isChallenge(
        statusCode: 200,
        body: '<script src="/cdn-cgi/challenge-platform/x"></script><script>var __cf_chl_x = 1;</script>',
      ),
      true,
    );
    expect(
      WafDetector.isChallenge(statusCode: 403, body: 'Referer required'),
      false,
    );
    expect(
      WafDetector.isChallenge(
        statusCode: 200,
        body: '<article>Cloudflare explains checking your browser and just a moment.</article>',
      ),
      false,
    );
  });
}
