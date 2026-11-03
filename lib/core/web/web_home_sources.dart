import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../reading/reading.dart';
import '../session/section.dart';

/// A website or a self-contained HTML home, separate from JS/Cat source runtimes.
@immutable
class WebHomeSource {
  static const maxHtmlBytes = 2 * 1024 * 1024;
  const WebHomeSource({
    required this.id,
    required this.name,
    required this.url,
    this.html,
  });

  final String id;
  final String name;
  final String url;
  final String? html;
  bool get isLocal => html != null;

  Uri? get uri => Uri.tryParse(url);

  WebHomeSource copyWith({String? name, String? url}) => WebHomeSource(
    id: id,
    name: name ?? this.name,
    url: url ?? this.url,
    html: html,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    if (isLocal) 'html': html,
  };

  static WebHomeSource? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}'.trim();
    final name = '${raw['name'] ?? ''}'.trim();
    final url = '${raw['url'] ?? ''}'.trim();
    final html = raw['html'];
    if (id.isEmpty || name.isEmpty) return null;
    if (html is String &&
        html.trim().isNotEmpty &&
        html.length <= maxHtmlBytes &&
        utf8.encode(html).length <= maxHtmlBytes) {
      return WebHomeSource(id: id, name: name, url: '', html: html);
    }
    if (!isValidWebHomeUrl(url)) return null;
    return WebHomeSource(id: id, name: name, url: url);
  }

  @override
  bool operator ==(Object other) =>
      other is WebHomeSource &&
      other.id == id &&
      other.name == name &&
      other.url == url &&
      other.html == html;

  @override
  int get hashCode => Object.hash(id, name, url, html);
}

/// Persists the web home list in the video section library.
///
/// Reuses the existing per-section settings store so backup/export keeps the
/// entries next to the other video preferences, without a schema migration.
class WebHomeStore extends ChangeNotifier {
  WebHomeStore._(this._library) : _items = _decode(_library.setting(_key));

  static const _key = 'video.web.homes.v1';
  static final _stores = Expando<WebHomeStore>();
  final ReadingLibrary _library;
  List<WebHomeSource> _items;

  static WebHomeStore forLibrary(ReadingLibrary library) =>
      _stores[library] ??= WebHomeStore._(library);

  static Future<WebHomeStore> open() async =>
      forLibrary(await ReadingLibrary.open(Section.video));

  static WebHomeStore? get instance {
    final library = ReadingLibrary.find(Section.video);
    return library == null ? null : forLibrary(library);
  }

  List<WebHomeSource> get items => List.unmodifiable(_items);

  WebHomeSource? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  void upsert(WebHomeSource source) {
    final next = [..._items];
    final index = next.indexWhere((item) => item.id == source.id);
    if (index >= 0) {
      next[index] = source;
    } else {
      next.add(source);
    }
    _save(next);
  }

  void remove(String id) {
    _library.setSetting('video.web.home.state.$id', '{}');
    _save(_items.where((item) => item.id != id).toList());
  }

  Map<String, dynamic> readLocalState(String id) {
    final raw = _library.setting('video.web.home.state.$id');
    if (raw == null) return {};
    try {
      final state = jsonDecode(raw);
      return state is Map<String, dynamic> ? state : {};
    } catch (_) {
      return {};
    }
  }

  void writeLocalState(String id, Map<String, dynamic> state) {
    final encoded = jsonEncode(state);
    if (utf8.encode(encoded).length > 2 * 1024 * 1024) {
      throw const FormatException('这个网页的本地缓存已超过 2 MB');
    }
    _library.setSetting('video.web.home.state.$id', encoded);
  }

  void move(int from, int to) {
    if (from == to ||
        from < 0 ||
        to < 0 ||
        from >= _items.length ||
        to >= _items.length) {
      return;
    }
    final next = [..._items];
    final item = next.removeAt(from);
    next.insert(to, item);
    _save(next);
  }

  /// Reorder only visible search results; other home pages keep their slots.
  void moveVisible(List<String> ids, String from, String to) {
    final visible = _items.where((row) => ids.contains(row.id)).toList();
    final source = visible.indexWhere((row) => row.id == from);
    final target = visible.indexWhere((row) => row.id == to);
    if (source < 0 || target < 0 || source == target) return;
    visible.insert(target, visible.removeAt(source));
    var index = 0;
    _save([
      for (final row in _items) ids.contains(row.id) ? visible[index++] : row,
    ]);
  }

  /// Stable id for a newly added home page; callers don't need timestamps.
  String nextId() =>
      'web-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  void _save(List<WebHomeSource> next) {
    _items = List.unmodifiable(next);
    _library.setSetting(_key, jsonEncode(next.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  static List<WebHomeSource> _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final value = jsonDecode(raw);
      if (value is! List) return const [];
      return List.unmodifiable(
        value.map(WebHomeSource.fromJson).whereType<WebHomeSource>(),
      );
    } catch (_) {
      return const [];
    }
  }
}

/// Accepts only absolute http(s) home pages; used by the add/edit dialog.
bool isValidWebHomeUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}
