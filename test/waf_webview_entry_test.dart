import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/net/waf.dart';

/// 「这张错误卡要不要给【网页视图】出口」的口径（真机反馈：卡片上写着「可点
/// 【网页视图】过校验」，按钮却不在——巴卡漫画首页超时那一次）。
void main() {
  test('明确的 TLS 和证书错误不再提示去做网页验证码', () {
    for (final message in [
      'TLS_HANDSHAKE_FAILED：HTTPS安全连接失败（iOS -1200）',
      'RuntimeError: CERTIFICATE_VERIFY_FAILED',
      'PlatformException(network, 系统网络请求失败, {code: -1200, domain: NSURLErrorDomain}, null)',
      '网页视图：TLS错误导致安全连接失败。',
    ]) {
      expect(webViewMayHelp(message), isFalse, reason: message);
    }
    expect(
      webViewMayHelp('NEED_WEBVIEW_VERIFY：显式要求验证；TLS_HANDSHAKE_FAILED'),
      isTrue,
    );
  });

  test('明确被 WAF 拦下：给出口', () {
    for (final message in <String>[
      'NEED_WEBVIEW_VERIFY：巴卡漫画 需要网页验证（HTTP 403）',
      'NEED_WEBVIEW_VERIFY：站点需要网页验证（Just a moment...）',
      'Cloudflare 校验未通过（cf-chl 挑战页）',
      'HTTP 503 服务不可用',
    ]) {
      expect(webViewMayHelp(message), isTrue, reason: message);
    }
  });

  test('超时 / 网络失败 / 403 / 429 / 5xx：也要给（可能被拦，也可能只是慢）', () {
    for (final message in <String>[
      '执行超时: 调用超时: LumeSource.home',
      '网络请求失败：请求超时（20s）',
      'SocketException: Connection reset by peer',
      'HandshakeException: Connection terminated during handshake',
      'Failed host lookup: bakamh.com',
      'Connection refused',
      '请求失败（HTTP 403）',
      '请求失败（HTTP 429）',
      '请求失败（HTTP 502）',
    ]) {
      expect(webViewMayHelp(message), isTrue, reason: message);
    }
  });

  test('需要外部桥接、以及脚本自身错误：不给出口（网页视图救不了）', () {
    for (final message in <String>[
      'WAF_RECAPTCHA_V3：该站点需要外部桥接服务',
      '少数派文库：无效分类',
      '脚本错误: 列表没解析出条目',
      '',
    ]) {
      expect(webViewMayHelp(message), isFalse, reason: message);
    }
  });
}
