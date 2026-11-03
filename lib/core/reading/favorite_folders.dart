import 'dart:convert';

import 'reading_library.dart';

class FavoriteFolders {
  FavoriteFolders(this.library);
  final ReadingLibrary library;
  static const key = 'favorites.folders';
  Map<String, List<String>> load() {
    try {
      final raw = library.setting(key);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map).map(
        (name, ids) => MapEntry(
          '$name',
          (ids as List)
              .cast<String>()
              .map((id) => library.item(id)?.identity ?? id)
              .toList(),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  void save(Map<String, List<String>> folders) =>
      library.setSetting(key, jsonEncode(folders));
  bool create(String name) {
    final folders = load();
    name = name.trim();
    if (name.isEmpty || folders.containsKey(name)) return false;
    folders[name] = [];
    save(folders);
    return true;
  }

  void remove(String name) {
    final folders = load()..remove(name);
    save(folders);
  }

  void move(String itemId, String? name) {
    itemId = library.item(itemId)?.identity ?? itemId;
    final folders = load();
    for (final ids in folders.values) {
      ids.remove(itemId);
    }
    folders[name]?.add(itemId);
    save(folders);
  }
}
