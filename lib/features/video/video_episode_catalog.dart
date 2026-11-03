import 'dart:convert';

import '../../core/source/source.dart';

/// Route grouping never rewrites chapter IDs: the original source still resolves them.
abstract final class VideoEpisodeCatalog {
  static Future<List<SourceChapter>> load(
    DataSource source,
    String itemId,
  ) async {
    try {
      final chapters = await source.chapters(itemId);
      if (chapters.isNotEmpty) return chapters;
    } catch (_) {
      final metadata = await source.detail(itemId);
      if (metadata?.chapters.isNotEmpty == true) return metadata!.chapters;
      rethrow;
    }
    return (await source.detail(itemId))?.chapters ?? [];
  }

  static String lineOf(SourceChapter chapter) {
    if (chapter.line.trim().isNotEmpty) return chapter.line.trim();
    try {
      final data = jsonDecode(chapter.id);
      if (data is Map &&
          data['flag'] is String &&
          (data['flag'] as String).trim().isNotEmpty) {
        return (data['flag'] as String).trim();
      }
    } catch (_) {}
    final match = RegExp(r'^(.{1,60}?)\s+[·|｜]\s+(.+)$')
        .firstMatch(chapter.title);
    return match?.group(1)?.trim() ?? '默认线路';
  }

  static String labelOf(SourceChapter chapter) {
    final line = lineOf(chapter);
    final prefix = RegExp('^${RegExp.escape(line)}\\s+[·|｜]\\s+');
    return chapter.title.replaceFirst(prefix, '').trim();
  }

  /// Only explicit episode numbers are comparable; a missing episode never falls back by index.
  static String? episodeKey(SourceChapter chapter) {
    final label = labelOf(chapter);
    final season = RegExp(
      r's(\d{1,3})[ ._-]*e(\d{1,4})',
      caseSensitive: false,
    ).firstMatch(label);
    if (season != null) {
      return '${int.parse(season[1]!)}:${int.parse(season[2]!)}';
    }
    final number =
        RegExp(r'第\s*(\d{1,4})\s*[集话話期]').firstMatch(label) ??
        RegExp(
          r'(?:^|[ ._\]-])(?:ep?|episode)[ ._-]*(\d{1,4})(?!\d)',
          caseSensitive: false,
        ).firstMatch(label) ??
        RegExp(r'^(\d{1,4})(?:集|话|話)?$').firstMatch(label);
    return number == null ? null : '1:${int.parse(number[1]!)}';
  }

  static int matchingIndex(
    SourceChapter current,
    List<SourceChapter> candidates,
  ) {
    final exact = [
      for (var i = 0; i < candidates.length; i++)
        if (labelOf(candidates[i]) == labelOf(current)) i,
    ];
    if (exact.isNotEmpty) return exact.length == 1 ? exact.single : -1;
    final key = episodeKey(current);
    if (key == null) return -1;
    final matches = [
      for (var i = 0; i < candidates.length; i++)
        if (episodeKey(candidates[i]) == key) i,
    ];
    return matches.length == 1 ? matches.single : -1;
  }

  static String displayLabel(SourceChapter chapter, int index) {
    final label = labelOf(chapter);
    if (RegExp(
          r'\.(mkv|mp4|avi|mov|m4v|ts)(?:\b|$)',
          caseSensitive: false,
        ).hasMatch(label) ||
        label.length > 35 ||
        RegExp(r'^\d+$').hasMatch(label)) {
      final key = episodeKey(chapter);
      final number = key == null ? index + 1 : int.parse(key.split(':').last);
      return '第 ${number.toString().padLeft(2, '0')} 集';
    }
    return label.isEmpty ? '第 ${index + 1} 集' : label;
  }

  static Map<String, List<SourceChapter>> group(List<SourceChapter> chapters) {
    final lines = <String, List<SourceChapter>>{};
    for (final chapter in chapters) {
      (lines[lineOf(chapter)] ??= []).add(chapter);
    }
    return lines;
  }

  static List<SourceChapter> forChapter(
    List<SourceChapter> chapters,
    String id,
  ) {
    final selected = chapters.where((c) => c.id == id).firstOrNull;
    if (selected == null) return chapters;
    final line = lineOf(selected);
    return chapters.where((c) => lineOf(c) == line).toList();
  }
}
