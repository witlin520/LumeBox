import 'package:flutter/services.dart';

enum SecureConnectionFailure { certificate, handshake }

/// Recognize explicit TLS failures; a generic connection reset can still retry.
SecureConnectionFailure? secureConnectionFailureOf(Object? error) {
  if (error is PlatformException) {
    final details = error.details;
    if (details is Map && details['domain'] == 'NSURLErrorDomain') {
      final code = details['code'];
      if (code == -1200) return SecureConnectionFailure.handshake;
      if ([-1201, -1202, -1203, -1204].contains(code)) {
        return SecureConnectionFailure.certificate;
      }
    }
    if (error.code == 'tls_handshake') {
      return SecureConnectionFailure.handshake;
    }
    if (error.code == 'certificate') {
      return SecureConnectionFailure.certificate;
    }
  }
  final text = '$error'.toUpperCase();
  if (text.contains('CERTIFICATE_VERIFY_FAILED')) {
    return SecureConnectionFailure.certificate;
  }
  if (text.contains('TLS_HANDSHAKE_FAILED') ||
      text.contains('A TLS ERROR CAUSED THE SECURE CONNECTION TO FAIL') ||
      text.contains('TLS错误导致安全连接失败') ||
      text.contains('HTTPS安全连接失败')) {
    return SecureConnectionFailure.handshake;
  }
  // Older native builds label -1200 as "network". Preserve recognition after
  // an exception has crossed a script boundary and become a string.
  if (text.contains('NSURLERRORDOMAIN')) {
    final match = RegExp(r'\bCODE\s*[:=]\s*(-120[0-4])\b').firstMatch(text);
    if (match != null) {
      return match[1] == '-1200'
          ? SecureConnectionFailure.handshake
          : SecureConnectionFailure.certificate;
    }
  }
  return null;
}

String secureConnectionHint(SecureConnectionFailure failure) =>
    failure == SecureConnectionFailure.certificate
    ? 'HTTPS 证书校验失败，网页验证码无法修复证书问题。请核对手机日期时间，并检查站点证书与网络环境。'
    : 'HTTPS 安全连接建立失败，网页验证无法修复 TLS 握手。请对比手机浏览器的结果，并核对手机与电脑的网络和代理线路。';

/// Pass only fixed descriptions and a known system error number to Python.
/// Native exception messages/details can contain URLs, tokens or headers.
String pythonHostPlatformFailure(PlatformException error) {
  final details = error.details;
  final systemCode =
      details is Map &&
          details['domain'] == 'NSURLErrorDomain' &&
          details['code'] is int
      ? details['code'] as int
      : null;
  final suffix = systemCode == null ? '' : '（iOS $systemCode）';
  switch (secureConnectionFailureOf(error)) {
    case SecureConnectionFailure.certificate:
      return 'CERTIFICATE_VERIFY_FAILED：HTTPS 证书校验失败$suffix';
    case SecureConnectionFailure.handshake:
      return 'TLS_HANDSHAKE_FAILED：HTTPS安全连接失败$suffix';
    case null:
      break;
  }
  if (error.code == 'api_timeout') return '系统网络请求超时$suffix';
  if (error.code == 'transport_security') {
    return 'iOS 网络安全策略拒绝了请求$suffix';
  }
  if (error.code == 'cancelled') return '请求已取消';
  if (error.code == 'network') return '系统网络请求失败$suffix';
  final code = RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(error.code)
      ? error.code
      : 'platform_error';
  return '宿主操作失败：$code';
}
