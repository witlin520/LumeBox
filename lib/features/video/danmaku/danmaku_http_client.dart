import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../core/net/ios_image_network.dart';
import '../../../core/net/network_queue.dart';

/// Local adapter traffic never enters an HTTP proxy. Remote iOS traffic uses
/// URLSession, matching the system proxy and VPN route used by the main app.
class DanmakuHttpClient extends http.BaseClient {
  DanmakuHttpClient({NetworkSender? nativeSender, http.Client? remoteClient})
    : _nativeSender =
          nativeSender ?? (Platform.isIOS ? IosImageNetwork.send : null),
      _remote = remoteClient ?? http.Client();

  final NetworkSender? _nativeSender;
  final http.Client _remote;
  http.Client? _loopback;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('弹幕请求已取消', request.url);
    if (const ['127.0.0.1', 'localhost', '::1'].contains(request.url.host)) {
      final client = _loopback ??= IOClient(
        HttpClient()..findProxy = (_) => 'DIRECT',
      );
      return client.send(request);
    }
    final sender = _nativeSender;
    if (sender == null) return _remote.send(request);
    final body = await request.finalize().toBytes();
    final response = await sender(
      NetworkRequest(
        url: request.url.toString(),
        method: request.method,
        headers: request.headers,
        bodyBytes: body.isEmpty ? null : body,
        source: '弹幕服务',
        followRedirects: request.followRedirects,
        timeout: const Duration(seconds: 40),
      ),
    );
    return http.StreamedResponse(
      Stream.value(response.body),
      response.statusCode,
      headers: response.headers.map(
        (key, value) => MapEntry(key.toLowerCase(), value),
      ),
      request: request,
    );
  }

  @override
  void close() {
    _closed = true;
    _loopback?.close();
    _remote.close();
  }
}
