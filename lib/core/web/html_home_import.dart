import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'web_home_sources.dart';

class HtmlHomeImport {
  static const maxBytes = WebHomeSource.maxHtmlBytes;

  static WebHomeSource decode(String fileName, List<int> bytes) {
    if (!['.html', '.htm'].contains(p.extension(fileName).toLowerCase())) {
      throw const FormatException('请选择 .html 或 .htm 文件');
    }
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('HTML 文件不能为空，且不能超过 2 MB');
    }
    String html;
    try {
      html = utf8.decode(bytes).replaceFirst(RegExp(r'^\uFEFF'), '');
    } on FormatException {
      throw const FormatException('HTML 需使用 UTF-8 编码保存');
    }
    if (!RegExp(
      r'<(?:html|head|body)\b|<!doctype\s+html',
      caseSensitive: false,
    ).hasMatch(html)) {
      throw const FormatException('文件中没有有效的 HTML 页面');
    }
    final title =
        RegExp(r'<title\b[^>]*>([\s\S]*?)</title\s*>', caseSensitive: false)
            .firstMatch(html)
            ?.group(1)
            ?.replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&quot;', '"')
            .replaceAll('&#39;', "'")
            .trim();
    var name = title == null || title.isEmpty
        ? p.basenameWithoutExtension(fileName)
        : title;
    if (name.length > 96) name = name.substring(0, 96);
    return WebHomeSource(
      id: 'html-${sha256.convert(utf8.encode(html))}',
      name: name,
      url: '',
      html: html,
    );
  }
}
