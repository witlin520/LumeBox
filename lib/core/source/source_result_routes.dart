typedef SourceUrlRouter = String Function(String url, {String? kind});

/// Route media fields at the contract boundary. Item/chapter IDs and text stay
/// stable; signed URLs on undeclared hosts or path prefixes are left alone.
Object? routeSourceResult(
  Object? value,
  SourceUrlRouter route, {
  String? kind,
}) {
  if (value is String) return kind == null ? value : route(value, kind: kind);
  if (value is List) {
    return value.map((v) => routeSourceResult(v, route, kind: kind)).toList();
  }
  if (value is! Map) return value;
  final result = <String, Object?>{
    for (final e in value.entries) '${e.key}': e.value,
  };
  final mediaKind = '${value['kind'] ?? ''}'.toLowerCase();
  final urlKind =
      kind ??
      ({'video', 'audio', 'audiobook', 'audio-book'}.contains(mediaKind)
          ? 'video'
          : (mediaKind == 'webplayer' ||
                value['webPlayer'] == true ||
                value['webParse'] == true)
          ? 'site'
          : null);
  final original = value['url'];
  for (final e in value.entries) {
    final key = '${e.key}';
    if ({
          'cover',
          'coverUrl',
          'cover_url',
          'poster',
          'thumbnail',
          'thumbnailUrl',
          'image',
        }.contains(key) &&
        e.value is String) {
      result[key] = route(e.value as String, kind: 'image');
    } else if (key == 'images') {
      result[key] = routeSourceResult(e.value, route, kind: 'image');
    } else if (key == 'qualities' || key == 'levels') {
      result[key] = routeSourceResult(e.value, route, kind: 'video');
    } else if (key == 'pageUrl' && e.value is String) {
      result[key] = route(e.value as String, kind: 'site');
    } else if ({'url', 'src', 'playUrl'}.contains(key) &&
        urlKind != null &&
        e.value is String) {
      result[key] = route(e.value as String, kind: urlKind);
    } else if (key == 'imageHeaders' && e.value is Map) {
      result[key] = {
        for (final h in (e.value as Map).entries)
          route('${h.key}', kind: 'image'): routeHeaders(
            h.value,
            route,
            changed: route('${h.key}', kind: 'image') != '${h.key}',
          ),
      };
    } else if (key.endsWith('Headers') || key == 'headers') {
      result[key] = routeHeaders(
        e.value,
        route,
        changed: original != result['url'],
      );
    } else if (e.value is List || e.value is Map) {
      result[key] = routeSourceResult(e.value, route);
    }
  }
  final coverChanged = [
    'cover',
    'coverUrl',
    'cover_url',
    'poster',
    'thumbnail',
    'thumbnailUrl',
    'image',
  ].any((k) => value[k] != result[k]);
  final resourceChanged =
      coverChanged ||
      ['url', 'src', 'playUrl', 'pageUrl'].any((k) => value[k] != result[k]);
  // headers may precede url in source object insertion order.
  if (value['headers'] is Map) {
    result['headers'] = routeHeaders(
      value['headers'],
      route,
      changed: resourceChanged,
    );
  }
  for (final key in ['coverHeaders', 'cover_headers']) {
    if (value[key] is Map) {
      result[key] = routeHeaders(value[key], route, changed: coverChanged);
    }
  }
  return result;
}

Object? routeHeaders(
  Object? raw,
  SourceUrlRouter route, {
  required bool changed,
}) {
  if (raw is! Map) return raw;
  return {
    for (final e in raw.entries)
      if (!changed ||
          !{'cookie', 'authorization'}.contains('${e.key}'.toLowerCase()))
        '${e.key}': '${e.key}'.toLowerCase() == 'referer'
            ? route('${e.value}', kind: 'site')
            : e.value,
  };
}
