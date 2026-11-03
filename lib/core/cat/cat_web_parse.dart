import '../source/data_source.dart';

/// A Cat site returned `parse=1`: the play URL is a web page, not a media file.
///
/// The UI catches this and opens [CatWebParsePage] to let the page run and sniff
/// the real media URL. It extends [SourceException] so background paths
/// (next-episode preload/auto advance) degrade quietly instead of crashing.
class CatWebParseRequired extends SourceException {
  CatWebParseRequired(
    this.page,
    this.headers, {
    this.webPlayer = false,
    this.episodeSelector,
  }) : super(SourceErrorKind.callFailed, '该线路需要网页解析');

  final Uri page;
  final Map<String, String> headers;
  final bool webPlayer;

  /// A declarative button selector; never executable source-supplied JavaScript.
  final String? episodeSelector;

  @override
  String toString() => '该线路是网页解析地址，需要在网页里取回播放地址';
}

/// Pure helpers for the web-page media sniffer; kept UI-free for tests.
class CatMediaSniffer {
  const CatMediaSniffer._();

  static final _mediaSuffix = RegExp(
    r'\.(m3u8|mp4|flv|mkv|m4v|webm|ts|mpd)(?:$|[?#])',
    caseSensitive: false,
  );

  /// Blob URLs belong to the page's own player and cannot be handed to a player.
  static bool isMediaUrl(String value) {
    final text = value.trim();
    if (text.isEmpty) return false;
    final uri = Uri.tryParse(text);
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (_mediaSuffix.hasMatch(uri.path)) return true;
    return uri.toString().toLowerCase().contains('m3u8');
  }

  /// Keeps order and removes duplicates; relative URLs are ignored.
  static List<String> filter(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final text = value.trim();
      if (!isMediaUrl(text) || !seen.add(text)) continue;
      result.add(text);
    }
    return result;
  }
}
