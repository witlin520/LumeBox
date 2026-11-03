import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../reading/reading.dart';
import '../session/section.dart';
import 'source_store.dart';

/// Explicit persistent storage; legacy fs/cache remain in-memory as before.
class SourceScriptStorage {
  SourceScriptStorage(this.section, String sourceId)
    : key = 'source.runtime.storage.${sha256.convert(utf8.encode(sourceId))}';
  final Section section;
  final String key;
  bool _disposed = false;

  void dispose() => _disposed = true;

  Future<Object?> invoke(Map<String, dynamic> payload) async {
    if (_disposed) throw StateError('源已释放');
    final library = await ReadingLibrary.open(section);
    if (_disposed) throw StateError('源已释放');
    final store = SandboxStore();
    final raw = library.setting(key);
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw) as Map;
      for (final entry in decoded.entries) {
        store.write(entry.key as String, entry.value as String);
      }
    }
    final name = payload['key'];
    if (name is! String || name.trim().isEmpty || name.length > 1024) {
      throw const FormatException('存储缺少 key');
    }
    switch (payload['operation']) {
      case 'get':
        final value = store.read(name);
        return value == null ? payload['defaultValue'] : jsonDecode(value);
      case 'set':
        store.write(name, jsonEncode(payload['value']));
      case 'remove':
        store.remove(name);
      default:
        throw const FormatException('不支持的存储操作');
    }
    library.setSetting(
      key,
      jsonEncode({for (final name in store.keys()) name: store.read(name)}),
    );
    return true;
  }
}
