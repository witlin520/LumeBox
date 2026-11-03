/// Source diagnostics belong in resource details, not the title's metadata row.
/// Keep availability and preview restrictions visible without exposing API noise.
String conciseVideoSubtitle(String raw, {required int availableEpisodes}) {
  final text = raw.trim();
  if (!RegExp(r'网盘|云盘').hasMatch(text) ||
      !RegExp(
        r'HTTP\s*\d{3}|video_preview|Cookie|\bOK\b',
        caseSensitive: false,
      ).hasMatch(text)) {
    return text;
  }
  final count = RegExp(r'(\d+)\s*个(?:网盘|云盘)').firstMatch(text)?.group(1);
  final preview = RegExp(r'(\d+)\s*(秒|分钟)\s*预览').firstMatch(text);
  return [
    count == null ? '网盘资源' : '$count 个网盘',
    if (availableEpisodes > 0) '可用 $availableEpisodes 集',
    if (preview != null)
      '含 ${preview.group(1)} ${preview.group(2)}预览线路'
    else if (text.contains('video_preview') || text.contains('仅预览'))
      '含预览线路',
    if (RegExp(
      r'HTTP\s*[45]\d{2}|失败|失效|不可用',
      caseSensitive: false,
    ).hasMatch(text))
      '部分线路不可用',
    if (RegExp(r'(?:需要|需|请先|必须)\s*登录').hasMatch(text)) '部分线路需登录',
  ].join(' · ');
}
