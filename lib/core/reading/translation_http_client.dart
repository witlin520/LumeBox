import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import '../net/lume_http.dart';
import '../net/lume_net.dart';
import '../net/secure_connection_failure.dart';

/// Prefer source networking. An explicit iOS TLS handshake failure may retry
/// JSON once using Dart TLS with standard certificate validation.
class TranslationHttpClient extends http.BaseClient {
  TranslationHttpClient({
    LumeHttp? network,
    this.timeout = const Duration(seconds: 60),
    this.maxBytes = 2 * 1024 * 1024,
    http.Client? handshakeFallback,
  }) : network =
           network ?? LumeHttp(source: '全局翻译', settings: LumeNet.settings),
       _fallback = handshakeFallback;
  http.Client? _fallback;
  final LumeHttp network;
  final Duration timeout;
  final int maxBytes;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    try {
      final response = await network.sendBytes(
        url: request.url.toString(),
        method: request.method,
        headers: request.headers,
        bodyBytes: bytes,
        followRedirects: false,
        timeout: timeout,
        maxBytes: maxBytes,
      );
      return http.StreamedResponse(
        Stream.value(response.body),
        response.statusCode,
        headers: response.headers,
        contentLength: response.body.length,
        request: request,
      );
    } catch (error) {
      // -1200 means TLS failed before HTTP could submit the body. Retry once
      // through Dart's TLS stack, keeping normal certificate verification.
      // Never retry a timeout, HTTP failure or certificate rejection here.
      if ((!Platform.isIOS && _fallback == null) ||
          secureConnectionFailureOf(error) !=
              SecureConnectionFailure.handshake ||
          request.url.scheme != 'https' ||
          request.method != 'POST' ||
          !(request.headers['content-type'] ?? '').startsWith(
            'application/json',
          )) {
        rethrow;
      }
      _fallback ??= IOClient(HttpClient()..connectionTimeout = timeout);
      final retry = http.Request(request.method, request.url)
        ..followRedirects = false
        ..headers.addAll(request.headers)
        ..bodyBytes = bytes;
      final response = await _fallback!.send(retry).timeout(timeout);
      final data = BytesBuilder();
      await for (final chunk in response.stream.timeout(timeout)) {
        if (data.length + chunk.length > maxBytes) {
          throw const FormatException('翻译响应超过读取上限');
        }
        data.add(chunk);
      }
      return http.StreamedResponse(
        Stream.value(data.takeBytes()),
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    }
  }

  @override
  void close() {
    network.dispose();
    _fallback?.close();
  }
}
