import 'dart:convert';

import '../source/source.dart';
import 'reading.dart';

/// Compare stable chapter facts; order changes alone are not new content.
class ChapterUpdates {
  static bool check(
    ReadingLibrary library,
    LibraryItem item,
    List<SourceChapter> chapters,
  ) {
    final key = 'favorite.chapterSnapshot.${item.identity}';
    Map<String, dynamic>? previous;
    try {
      previous = jsonDecode(library.setting(key) ?? '') as Map<String, dynamic>;
    } catch (_) {}
    final facts = <String, String>{
      for (final c in chapters)
          jsonEncode([c.line, c.id]): jsonEncode([
          c.title.trim(),
          c.publishedAt?.toUtc().toIso8601String(),
        ]),
    };
    final changed = previous == null
        ? item.chapterCount > 0 && chapters.length > item.chapterCount
        : facts.entries.any((e) => previous![e.key] != e.value);
    // An empty/transient response must not erase a useful baseline.
    if (facts.isNotEmpty) library.setSetting(key, jsonEncode(facts));
    return changed;
  }
}
