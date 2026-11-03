import 'dart:convert';

import '../session/section.dart';
import 'data_source.dart';
import 'source_content_rating.dart';
import 'source_picker_groups.dart';
import 'source_preferences.dart';

enum SourceContentCategory {
  movie('movie', '影视'),
  adult('adult', '成人'),
  unclassified('unclassified', '待分类'),
  all('all', '全部');

  const SourceContentCategory(this.id, this.label);
  final String id, label;
  static const groups = [movie, adult, unclassified];
  static SourceContentCategory? fromId(String id) =>
      values.where((value) => value.id == id).firstOrNull;
}

/// Content classification is independent of interpreter and source identity.
abstract final class SourceContentCategories {
  static bool appliesTo(SourceDescriptor source) =>
      source.runtimeKind == 'javascript' && !source.isAudio && !source.isKazumi;

  static String fromScript(String script) {
    final header = RegExp(
      r'^\s*(?://|#)\s*@?LumeSource:\s*(\{[^\n]+\})',
      multiLine: true,
    ).firstMatch(script);
    if (header == null) return '';
    try {
      final data = jsonDecode(header[1]!);
      final category = data is Map
          ? SourceContentCategory.fromId('${data['contentCategory'] ?? ''}')
          : null;
      return category == SourceContentCategory.all ? '' : category?.id ?? '';
    } catch (_) {
      return '';
    }
  }

  static SourceContentCategory automatic(SourceDescriptor source) {
    if (SourceContentRating.isAdult(source.id, source.name)) {
      return SourceContentCategory.adult;
    }
    final declared = SourceContentCategory.fromId(source.contentCategory);
    if (declared != null && declared != SourceContentCategory.all) {
      return declared;
    }
    if (source.group == '成人') return SourceContentCategory.adult;
    final host = Uri.tryParse(source.siteUrl)?.host.toLowerCase() ?? '';
    if (SourcePickerGroups.groupFor(Section.video, source) == 'movie' ||
        host == '360zy.com' ||
        host.endsWith('.360zy.com')) {
      return SourceContentCategory.movie;
    }
    return SourceContentCategory.unclassified;
  }

  static SourceContentCategory forSource(SourceDescriptor source) {
    final saved = SourceContentCategory.fromId(
      SourcePreferences.read(Section.video, source.id).contentCategory,
    );
    return saved != null && saved != SourceContentCategory.all
        ? saved
        : automatic(source);
  }
}
