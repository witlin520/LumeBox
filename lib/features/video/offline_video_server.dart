import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// A session-only loopback endpoint makes downloaded HLS playable by AVFoundation as well as FFmpeg.
class OfflineVideoServer {
  OfflineVideoServer._(this._server, this._root, this._token);
  final HttpServer _server;
  final String _root, _token;
  static Future<OfflineVideoServer> open(Directory directory) async {
    final root = await directory.resolveSymbolicLinks();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    final token = List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final result = OfflineVideoServer._(server, root, token);
    server.listen(result._serve);
    return result;
  }

  Uri get uri => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: _server.port,
    path: '/$_token/index.m3u8',
  );

  /// 用同一个回环服务器播放目录内任意文件（如合并后的 `merged.mp4`）。
  /// 走 HTTP 而非 `file://`，可规避 iOS 沙盒路径含空格（`Application Support`）、
  /// 以及不同播放器内核对 `file://` 支持不一的问题。
  Uri fileUri(String name) => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: _server.port,
    path: '/$_token/$name',
  );
  Future<void> close() => _server.close(force: true);
  Future<void> _serve(HttpRequest request) async {
    try {
      final parts = request.uri.pathSegments;
      if (!['GET', 'HEAD'].contains(request.method) ||
          parts.isEmpty ||
          parts.first != _token) {
        request.response.statusCode = 403;
        return;
      }
      final path = p.normalize(p.joinAll([_root, ...parts.skip(1)]));
      if (!p.isWithin(_root, path) ||
          ![
            '.m3u8',
            '.ts',
            '.m4s',
            '.mp4',
            '.key',
            '.aac',
            '.mp3',
          ].contains(p.extension(path))) {
        request.response.statusCode = 403;
        return;
      }
      final file = File(path);
      if (!await file.exists()) {
        request.response.statusCode = 404;
        return;
      }
      if (!p.isWithin(_root, await file.resolveSymbolicLinks())) {
        request.response.statusCode = 403;
        return;
      }
      final length = await file.length();
      var start = 0, end = length - 1;
      final range = request.headers.value('range');
      if (range != null) {
        // 只处理单段 Range；多段（bytes=A-B,C-D）按标准返回 416。
        // 同时支持：bytes=A-B / bytes=A- / bytes=-N（后缀，取末 N 字节）。
        // AVFoundation 读取尾部 moov 时可能用到后缀 Range，漏掉会 416 导致放不动。
        final suffix = RegExp(r'^bytes=-(\d+)$').firstMatch(range);
        final single = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
        if (suffix != null) {
          final count = int.parse(suffix.group(1)!);
          if (count <= 0 || length == 0) {
            request.response.statusCode = 416;
            request.response.headers.set('Content-Range', 'bytes */$length');
            return;
          }
          // 取末 count 字节；超过全长大小时按整文件处理。
          final take = count < length ? count : length;
          start = length - take;
          end = length - 1;
        } else if (single != null) {
          start = int.parse(single.group(1)!);
          end = single.group(2)!.isEmpty ? end : int.parse(single.group(2)!);
        } else {
          request.response.statusCode = 416;
          request.response.headers.set('Content-Range', 'bytes */$length');
          return;
        }
        if (start >= length || end < start) {
          request.response.statusCode = 416;
          request.response.headers.set('Content-Range', 'bytes */$length');
          return;
        }
        if (end > length - 1) end = length - 1;
        request.response.statusCode = 206;
        request.response.headers.set(
          'Content-Range',
          'bytes $start-$end/$length',
        );
      }
      request.response.headers.set('Accept-Ranges', 'bytes');
      request.response.headers.contentType = ContentType.parse(switch (p
          .extension(path)) {
        '.m3u8' => 'application/vnd.apple.mpegurl',
        '.aac' => 'audio/aac',
        '.mp3' => 'audio/mpeg',
        '.ts' => 'video/mp2t',
        '.mp4' || '.m4s' => 'video/mp4',
        _ => 'application/octet-stream',
      });
      request.response.contentLength = length == 0 ? 0 : end - start + 1;
      if (request.method == 'GET' && length > 0) {
        await request.response.addStream(file.openRead(start, end + 1));
      }
    } catch (_) {
      /* Client cancellation must not terminate the offline server. */
    } finally {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }
}
