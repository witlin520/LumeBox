import 'dart:typed_data';

/// Short-lived original cover bytes, shared across decode sizes and page visits.
/// Reader pages never use this cache. Nothing is written to disk.
class CoverByteCache {
  CoverByteCache({
    this.budgetBytes = 8 * 1024 * 1024,
    this.maxEntryBytes = 2 * 1024 * 1024,
    this.ttl = const Duration(minutes: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int budgetBytes;
  final int maxEntryBytes;
  final Duration ttl;
  final DateTime Function() _now;
  final _entries = <String, ({Uint8List data, DateTime until})>{};
  int _bytes = 0;
  int get bytes => _bytes;

  Uint8List? get(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (!entry.until.isAfter(_now())) {
      _bytes -= entry.data.length;
      return null;
    }
    _entries[key] = entry;
    return entry.data;
  }

  void put(String key, Uint8List data) {
    final now = _now();
    for (final expired
        in _entries.entries
            .where((entry) => !entry.value.until.isAfter(now))
            .map((entry) => entry.key)
            .toList()) {
      _bytes -= _entries.remove(expired)!.data.length;
    }
    final previous = _entries.remove(key);
    if (previous != null) _bytes -= previous.data.length;
    if (data.isEmpty ||
        data.length > maxEntryBytes ||
        data.length > budgetBytes) {
      return;
    }
    _entries[key] = (data: data, until: now.add(ttl));
    _bytes += data.length;
    while (_bytes > budgetBytes) {
      _bytes -= _entries.remove(_entries.keys.first)!.data.length;
    }
  }

  void clear() {
    _entries.clear();
    _bytes = 0;
  }

  void remove(String key) {
    final entry = _entries.remove(key);
    if (entry != null) _bytes -= entry.data.length;
  }
}
