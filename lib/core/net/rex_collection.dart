import 'dart:convert';

/// Rex/Forward collection manifests. Module URLs can be extensionless.
class RexCollection {
  static const maxEntries = 2000;
  RexCollection(this.entries);
  final List<RexCollectionEntry> entries;

  static bool matches(String text) {
    if (!text.trimLeft().startsWith('{')) return false;
    try {
      final value = jsonDecode(text);
      return value is Map && value['widgets'] is List;
    } on FormatException {
      return false;
    }
  }

  static RexCollection parse(String text, {String origin = ''}) {
    final value = jsonDecode(text);
    if (value is! Map || value['widgets'] is! List) {
      throw const FormatException('Rex 集合需要 widgets 数组');
    }
    final entries = <RexCollectionEntry>[];
    final widgets = value['widgets'] as List;
    if (widgets.length > maxEntries) {
      throw const FormatException('Rex 集合超过 2000 个条目');
    }
    for (var i = 0; i < widgets.length; i++) {
      final entry = widgets[i];
      if (entry is! Map || entry['url'] is! String) {
        throw FormatException('Rex 集合第 ${i + 1} 项缺少模块地址');
      }
      var uri = Uri.tryParse(entry['url'] as String);
      if (uri != null && !uri.hasScheme && origin.isNotEmpty) {
        uri = Uri.parse(origin).resolveUri(uri);
      }
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment) {
        throw FormatException('Rex 集合第 ${i + 1} 项模块地址无效');
      }
      entries.add(
        RexCollectionEntry(
          url: uri.toString(),
          id: '${entry['id'] ?? ''}',
          title: '${entry['title'] ?? entry['id'] ?? '模块 ${i + 1}'}',
          version: '${entry['version'] ?? '1'}',
        ),
      );
    }
    return RexCollection(entries);
  }
}

class RexCollectionEntry {
  const RexCollectionEntry({
    required this.url,
    required this.id,
    required this.title,
    required this.version,
  });
  final String url, id, title, version;
}
