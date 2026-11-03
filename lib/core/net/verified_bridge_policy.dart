import 'dart:convert';

/// Explicit source declaration, enforced again in the native retained page.
class VerifiedBridgePolicy {
  VerifiedBridgePolicy(Map args) {
    final url = Uri.tryParse('${args['origin'] ?? ''}');
    if (url == null ||
        !['https', 'http'].contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        !['', '/'].contains(url.path)) {
      throw const FormatException('请求桥必须声明完整的源站 origin');
    }
    origin = url.origin;
    final list = args['paths'];
    if (list is! List ||
        list.isEmpty ||
        list.length > 32 ||
        list.any(
          (p) =>
              p is! String ||
              !p.startsWith('/') ||
              p.startsWith('//') ||
              p.contains(RegExp(r'[?#\\%]')) ||
              p
                  .split('/')
                  .any((segment) => segment == '.' || segment == '..') ||
              p.contains('*'),
        )) {
      throw const FormatException('请求桥需声明 1–32 个精确路径，不支持通配符');
    }
    paths = list.cast<String>().toSet();
  }
  late final String origin;
  late final Set<String> paths;
  Map<String, Object?> validate(Map args) {
    final url = Uri.tryParse('${args['url'] ?? ''}');
    if (url == null ||
        !['http', 'https'].contains(url.scheme) ||
        url.host.isEmpty ||
        url.origin != origin ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        url.path.contains(RegExp(r'[%\\]')) ||
        !paths.contains(url.path)) {
      throw const FormatException('请求桥仅允许声明的同源路径');
    }
    final method = '${args['method'] ?? 'GET'}'.toUpperCase();
    if (!['GET', 'POST'].contains(method)) {
      throw const FormatException('请求桥仅允许 GET／POST');
    }
    final raw = args['headers'] ?? <String, String>{};
    if (raw is! Map || raw.length > 32) throw const FormatException('请求桥请求头无效');
    final headers = raw.map((k, v) => MapEntry('$k', '$v'));
    if (headers.keys.any(
      (k) =>
          [
            'cookie',
            'authorization',
            'proxy-authorization',
            'host',
            'origin',
            'referer',
            'set-cookie',
            'content-length',
            'connection',
          ].contains(k.toLowerCase()) ||
          k.toLowerCase().startsWith('sec-'),
    )) {
      throw const FormatException('请求桥不接受凭据或浏览器身份请求头');
    }
    if (headers.entries.any(
      (e) =>
          !RegExp(r'^[!#$%&\x27*+.^_`|~0-9a-zA-Z-]+$').hasMatch(e.key) ||
          e.value.contains(RegExp(r'[\r\n]')) ||
          e.value.length > 8192,
    )) {
      throw const FormatException('请求桥请求头包含无效字符');
    }
    final body = args['body'];
    if (body != null && (body is! String || utf8.encode(body).length > 65536)) {
      throw const FormatException('请求桥正文必须是文本且不超过 64KB');
    }
    final timeout = args['timeoutMs'] ?? 6000;
    if (timeout is! num || !timeout.isFinite) {
      throw const FormatException('请求桥超时无效');
    }
    return {
      'url': url.toString(),
      'method': method,
      'headers': headers,
      'body': method == 'POST' ? body : null,
      'timeoutMs': timeout.round().clamp(100, 8000),
    };
  }
}
