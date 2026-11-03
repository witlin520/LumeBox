import 'source_models.dart';

RegExp homeBrowsePattern(String mode) => mode == '热门'
    ? RegExp(r'热门|最热|热度|人气|热播|人氣|popular|hot', caseSensitive: false)
    : RegExp(r'最新|更新|上架|时间|時間|日期|latest|new|time', caseSensitive: false);

/// Only route shortcuts to categories or ordering actually supplied by a source.
({String? category, String? group, String? option})? homeBrowseTarget(
  String mode,
  List<SourceCategory> categories,
  List<SourceFilterGroup> groups,
) {
  final pattern = homeBrowsePattern(mode);
  for (final group in groups) {
    if (!RegExp(
      r'排序|顺序|排序|order|sort',
      caseSensitive: false,
    ).hasMatch('${group.id} ${group.title}')) {
      continue;
    }
    for (final option in group.options) {
      if (pattern.hasMatch(option.title)) {
        return (category: null, group: group.id, option: option.id);
      }
    }
  }
  for (final category in categories) {
    if (pattern.hasMatch(category.title)) {
      return (category: category.id, group: null, option: null);
    }
  }
  return null;
}
