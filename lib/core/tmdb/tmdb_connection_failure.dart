import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../util/sensitive_data.dart';

/// Never display raw request URLs: API credentials can occur in their query.
abstract final class TmdbConnectionFailure {
  static String describe(
    Object error, {
    required bool api,
    required bool customEndpoint,
    required bool globalProxy,
  }) {
    final target = api ? 'API' : '图片';
    final route = customEndpoint ? '已配置的$target代理地址' : 'TMDB 官方$target地址';
    final network = globalProxy ? '经全局 HTTP 代理' : '直连';
    final String reason;
    if (error is StateError) {
      reason = SensitiveData.redact(error.message.toString());
    } else if (error is TimeoutException) {
      reason = '连接或读取超时。请检查网络，或配置可用的$target代理地址。';
    } else if (error is HandshakeException || error is TlsException) {
      reason = 'TLS 安全连接失败。请检查设备时间、代理证书及 HTTPS 地址。';
    } else if (error is SocketException || error is http.ClientException) {
      final text = error.toString().toLowerCase();
      reason =
          text.contains('failed host lookup') ||
              text.contains('name or service') ||
              text.contains('nodename')
          ? 'DNS 解析失败，当前网络无法解析服务器域名。请更换网络或检查代理地址。'
          : '网络连接失败或被中断。请检查当前网络及全局 HTTP 代理；官方地址不可达时可配置$target代理地址。';
    } else if (error is FormatException) {
      reason = '地址格式或返回内容无效。代理地址应是 HTTP(S) 服务根地址，返回内容需符合 TMDB 接口格式。';
    } else {
      reason = api
          ? '服务未返回有效的 TMDB 配置信息，请检查地址和服务状态。'
          : '返回内容无法解码为图片，请检查图片代理地址和服务状态。';
    }
    return '测试失败：$reason\n\n当前测试：$route（$network）。';
  }
}
