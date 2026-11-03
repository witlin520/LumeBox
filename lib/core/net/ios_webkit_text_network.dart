import 'dart:convert';

import '../js/source_web_runtime.dart';
import 'network_queue.dart';

/// WebKit keeps its normal certificate checks. This path only retries public
/// text GETs; binary requests, credentials and mutations stay on URLSession.
class IosWebKitTextNetwork {
  static bool accepts(NetworkRequest request) =>
      request.textResponse &&
      request.url.startsWith('https://') &&
      request.method == 'GET' &&
      request.followRedirects &&
      request.body == null &&
      request.bodyBytes == null &&
      request.proxy.isEmpty &&
      !request.allowBadCertificate &&
      !request.headers.keys.any(
        (key) => const {
          'cookie',
          'authorization',
          'proxy-authorization',
          'range',
        }.contains(key.toLowerCase()),
      );

  static Future<NetworkResponse> read(NetworkRequest request, String id) async {
    final runtime = SourceWebRuntime('tls:$id');
    try {
      Future<Object?> render() => runtime.invoke('render', {
        'url': request.url,
        'method': 'GET',
        'headers': request.headers,
        'includeHtml': false,
        'timeoutMs': 8000,
        'script': '''
let body = document.body ? document.body.innerText : '';
let contentType = document.contentType || 'text/html';
try { JSON.parse(body); contentType = 'application/json'; }
catch (_) {
  body = document.documentElement.outerHTML;
}
return {body: body, contentType: contentType, url: location.href};
''',
      });
      final operation = request.cancellation == null
          ? render()
          : request.cancellation!.run(render);
      final reply = await (request.cancellation?.guard(operation) ?? operation);
      request.cancellation?.check();
      if (reply is! Map || reply['result'] is! Map) {
        throw StateError('WebKit 没有返回文本响应');
      }
      final result = reply['result'] as Map;
      final finalUrl = Uri.tryParse('${result['url'] ?? ''}');
      if (finalUrl == null ||
          finalUrl.origin != Uri.parse(request.url).origin ||
          result['body'] is! String ||
          reply['status'] is! int) {
        throw StateError('WebKit 返回了非预期的文本页面');
      }
      final body = utf8.encode(result['body'] as String);
      if (body.length > (request.maxBytes ?? 8 * 1024 * 1024)) {
        throw StateError('WebKit 文本响应超过读取上限');
      }
      return NetworkResponse(
        statusCode: reply['status'] as int,
        body: body,
        headers: {
          'content-type':
              '${result['contentType'] ?? 'text/html'}; charset=utf-8',
        },
      );
    } finally {
      runtime.dispose();
    }
  }
}
