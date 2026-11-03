import 'dart:convert';

/// Stable storage identity. Website IDs remain unchanged at the source boundary.
abstract final class ReadingIdentity {
  static String key(String sourceId, String itemId) =>
      'lume:item:${jsonEncode([sourceId, itemId])}';
  static List<String>? decode(String value) {
    try {
      if (!value.startsWith('lume:item:')) return null;
      final raw = jsonDecode(value.substring('lume:item:'.length));
      if (raw is List &&
          raw.length >= 2 &&
          raw.length <= 3 &&
          raw.every((v) => v is String)) {
        return raw.cast<String>();
      }
    } catch (_) {}
    return null;
  }
}
