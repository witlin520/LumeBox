import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'network_queue.dart';
import 'network_cancellation.dart';
import 'waf.dart';

/// Reuses WebKit's real browsing session after the user completed verification.
class IosVerifiedWebView {
  static const channel = MethodChannel('lumebox/webview');
  static int _sequence = 0;
  static Future<Map<String, dynamic>?> _read(
    String method,
    NetworkRequest request,
    Map<String, Object?> arguments,
  ) async {
    final token = request.cancellation ?? NetworkCancellation.current;
    token?.check();
    final id = 'verified-${_sequence++}';
    void cancel() => unawaited(
      channel
          .invokeMethod<void>('cancelVerifiedRead', {'requestId': id})
          .catchError((Object _) {}),
    );
    final stop = token?.onCancel(cancel);
    try {
      final operation = channel.invokeMapMethod<String, dynamic>(method, {
        ...arguments,
        'requestId': id,
      });
      return await (token?.guard(operation) ?? operation).timeout(
        const Duration(seconds: 20),
      );
    } on TimeoutException {
      cancel();
      rethrow;
    } finally {
      stop?.call();
    }
  }

  static Map<String, String> scopedResourceHeaders(
    String url,
    Map<String, String> original,
    List<Object?> cookies,
  ) {
    final selected = webViewCookiesForUrl(cookies, url)
      ..removeWhere((name, _) => !{'cf_clearance', '__cf_bm'}.contains(name));
    if (selected.isEmpty) return original;
    final pairs = <String, String>{};
    final old =
        original.entries
            .where((e) => e.key.toLowerCase() == 'cookie')
            .firstOrNull
            ?.value ??
        '';
    for (final part in old.split(';')) {
      final at = part.indexOf('=');
      if (at > 0) {
        pairs[part.substring(0, at).trim()] = part.substring(at + 1).trim();
      }
    }
    pairs.addAll(selected);
    return {
      for (final e in original.entries)
        if (e.key.toLowerCase() != 'cookie') e.key: e.value,
      'Cookie': pairs.entries.map((e) => '${e.key}=${e.value}').join('; '),
    };
  }

  static Future<Map<String, String>> resourceHeaders(
    String url,
    Map<String, String> original,
  ) async {
    try {
      final cookies = await channel
          .invokeMethod<List<Object?>>('allCookies', {'url': url})
          .timeout(const Duration(seconds: 2));
      return scopedResourceHeaders(url, original, cookies ?? []);
    } catch (_) {
      return original;
    }
  }

  static Future<NetworkResponse> readResource(NetworkRequest request) async {
    final raw = await _read('readVerifiedResource', request, {
      'url': request.url,
      'userAgent': request.headers['User-Agent'],
      'method': request.method,
      'headers': {
        for (final e in request.headers.entries)
          if (!{
            'cookie',
            'authorization',
            'user-agent',
            'referer',
            'host',
            'content-length',
          }.contains(e.key.toLowerCase()))
            e.key: e.value,
      },
      if (request.body != null) 'body': request.body,
    });
    if (raw == null) throw StateError('网页图片会话没有返回响应');
    return NetworkResponse(
      statusCode: raw['status'] as int,
      body: (raw['body'] as Uint8List).toList(),
      headers: {'content-type': '${raw['contentType'] ?? ''}'},
    );
  }

  static Future<NetworkResponse> read(NetworkRequest request) async {
    final raw = await _read('readVerifiedPage', request, {
      'url': request.url,
      'userAgent': request.headers['User-Agent'],
    });
    if (raw == null) throw StateError('网页会话没有返回正文');
    final body = utf8.encode(raw['body'] as String);
    if (body.length > (request.maxBytes ?? 10 * 1024 * 1024)) {
      throw StateError('网页正文超过读取上限');
    }
    return NetworkResponse(
      statusCode: raw['status'] as int,
      body: body,
      headers: {
        'content-type': '${raw['contentType'] ?? 'text/html'}; charset=utf-8',
      },
    );
  }
}
