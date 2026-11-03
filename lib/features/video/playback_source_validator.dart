import '../../core/net/lume_http.dart';

typedef SourceValidationRequest = Future<LumeHttpResponse> Function(
  Uri uri,
  Map<String, String> headers,
);

/// One bounded request for the current address. Never selects another address,
/// follows HLS variants or invokes playback operations.
class PlaybackSourceValidator {
  PlaybackSourceValidator({this.request});
  final SourceValidationRequest? request;
  LumeHttp? _active;
  int _revision = 0;
  static const maxBytes = 1024;

  Future<String?> check(Uri uri, Map<String, String> headers) async {
    cancel();
    final revision = _revision;
    LumeHttp? client;
    try {
      final response = request != null
          ? await request!(uri, headers)
          : await (client = _active = LumeHttp(source: '播放后静默校验')).send(
              url: uri.toString(),
              method: 'GET',
              headers: {
                for (final entry in headers.entries)
                  if (entry.key.toLowerCase() != 'range')
                    entry.key: entry.value,
                'Range': 'bytes=0-1023',
              },
              maxBytes: maxBytes,
              timeout: const Duration(seconds: 6),
            );
      if (revision != _revision) return null;
      if (response.statusCode != 200 && response.statusCode != 206) {
        return '后台校验返回 HTTP ${response.statusCode}，当前播放源可能不可用；请按需手动更换线路';
      }
      final type = response.headers.entries
          .where((entry) => entry.key.toLowerCase() == 'content-type')
          .map((entry) => entry.value.toLowerCase())
          .firstOrNull;
      if (type?.contains('text/html') == true) {
        return '后台校验返回网页而非媒体，播放源可能需要重新验证；请按需手动处理';
      }
      return null;
    } catch (_) {
      return revision == _revision ? '后台暂时无法校验播放源，请以实际播放状态为准；不会自动更换线路' : null;
    } finally {
      client?.dispose();
      if (identical(_active, client)) _active = null;
    }
  }

  void cancel() {
    _revision++;
    _active?.dispose();
    _active = null;
  }
}
