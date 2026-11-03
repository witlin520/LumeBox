import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// Reads a Node cat bundle without executing it or extracting supplied paths.
class CatLocalBundle {
  CatLocalBundle._(this.index, this.config);
  final List<int> index, config;
  String get hash => md5.convert(index).toString();
  String get configHash => md5.convert(config).toString();
  static const maxArchiveBytes = 24 * 1024 * 1024;

  static CatLocalBundle fromZip(List<int> bytes) {
    if (bytes.length > maxArchiveBytes) {
      throw const FormatException('猫源 ZIP 不能超过 24MB');
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final files = <String, ArchiveFile>{};
    var total = 0;
    for (final file in archive) {
      if (!file.isFile) continue;
      final path = file.name;
      if (file.isSymbolicLink ||
          path.contains('\\') ||
          path.contains(':') ||
          path.startsWith('/') ||
          path.split('/').any((p) => p.isEmpty || p == '..' || p == '.') ||
          files.containsKey(path)) {
        throw const FormatException('猫源 ZIP 包含无效路径、重复文件或符号链接');
      }
      total += file.size;
      if (total > maxArchiveBytes || files.length >= 256) {
        throw const FormatException('猫源 ZIP 解压后超过 24MB 或 256 个文件');
      }
      files[path] = file;
    }
    final entries = files.keys
        .where((p) => p == 'index.js' || p.endsWith('/index.js'))
        .toList();
    if (entries.length != 1) {
      throw const FormatException('请选择包含一套 index.js 和 index.config.js 的猫源 ZIP');
    }
    final prefix = entries.single.substring(
      0,
      entries.single.length - 'index.js'.length,
    );
    List<int> read(String name, int limit) {
      final file = files['$prefix$name'];
      if (file == null || file.size == 0 || file.size > limit) {
        throw FormatException('$name 缺失、为空或超过大小限制');
      }
      return file.content;
    }

    final index = read('index.js', 20 * 1024 * 1024);
    final config = read('index.config.js', 2 * 1024 * 1024);
    for (final entry in {
      'index.js': index,
      'index.config.js': config,
    }.entries) {
      if (!files.containsKey('$prefix${entry.key}.md5')) continue;
      final expected = utf8
          .decode(read('${entry.key}.md5', 4096))
          .trim()
          .toLowerCase();
      if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(expected) ||
          md5.convert(entry.value).toString() != expected) {
        throw FormatException('${entry.key} MD5 校验失败，请重新获取完整包');
      }
    }
    return CatLocalBundle._(index, config);
  }
}
