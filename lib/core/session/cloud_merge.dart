import 'dart:convert';

/// Record-level last-write merge. Explicit null tombstones prevent deleted items returning.
class CloudMerge {
  static Map<String, Map<String, dynamic>> decode(String text) {
    final raw = jsonDecode(text);
    if (raw is! Map ||
        raw['format'] != 'lumebox-icloud' ||
        ![1, 2].contains(raw['version']) ||
        raw['records'] is! Map ||
        (raw['records'] as Map).length > 100000) {
      throw const FormatException('iCloud 同步数据版本不兼容');
    }
    final result = <String, Map<String, dynamic>>{};
    for (final entry in (raw['records'] as Map).entries) {
      final value = entry.value;
      if (entry.key is! String ||
          value is! Map ||
          value['stamp'] is! int ||
          value['stamp'] < 0 ||
          value['device'] is! String ||
          !value.containsKey('value')) {
        throw const FormatException('iCloud 同步记录无效');
      }
      result[entry.key as String] = Map<String, dynamic>.from(value);
    }
    return result;
  }

  static Map<String, Map<String, dynamic>> merge(
    Iterable<Map<String, Map<String, dynamic>>> documents,
  ) {
    final result = <String, Map<String, dynamic>>{};
    for (final document in documents) {
      for (final entry in document.entries) {
        final old = result[entry.key];
        final next = entry.value;
        if (old == null ||
            (next['stamp'] as int) > (old['stamp'] as int) ||
            next['stamp'] == old['stamp'] &&
                (next['device'] as String).compareTo(old['device'] as String) >
                    0) {
          result[entry.key] = Map.from(next);
        }
      }
    }
    return result;
  }

  static String encode(Map<String, Map<String, dynamic>> records) => jsonEncode(
    {'format': 'lumebox-icloud', 'version': 2, 'records': records},
  );
}
