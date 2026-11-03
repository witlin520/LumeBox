import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// A self-contained source. Keeping bytes in the script record makes updates,
/// backups and removal atomic; imports never depend on the original file URL.
class SourceBundle {
  SourceBundle(
    this.entry,
    this.runtime,
    this.protocol,
    this.files,
    this.metadata,
  );
  final String entry, runtime, protocol;
  final Map<String, List<int>> files;
  final Map<String, Object?> metadata;
  static const maxBytes = 8 * 1024 * 1024;
  static const maxFiles = 256;

  static bool isZip(List<int> bytes) =>
      bytes.length > 3 &&
      bytes[0] == 80 &&
      bytes[1] == 75 &&
      bytes[2] == 3 &&
      bytes[3] == 4;

  static String checkedPath(String name) {
    if (name.isEmpty ||
        name.contains('\\') ||
        name.contains(':') ||
        name.startsWith('/') ||
        name
            .split('/')
            .any((part) => part == '..' || part.isEmpty || part == '.')) {
      throw const FormatException('源包文件路径无效或越界');
    }
    return name;
  }

  static Map<String, List<int>> _unzip(List<int> bytes) {
    if (bytes.length > maxBytes) throw const FormatException('源包不能超过 8MB');
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final files = <String, List<int>>{};
    var size = 0;
    for (final file in archive) {
      if (!file.isFile) continue;
      final name = checkedPath(file.name);
      if (file.isSymbolicLink || files.containsKey(name)) {
        throw const FormatException('源包含重复路径或符号链接');
      }
      size += file.size;
      if (size > maxBytes || files.length >= maxFiles) {
        throw const FormatException('源包解压后超过 8MB 或 256 个文件');
      }
      files[name] = file.content;
    }
    return files;
  }

  static SourceBundle fromZip(List<int> bytes) {
    var files = _unzip(bytes);
    if (files.containsKey('rex-manifest.json')) {
      final manifest = jsonDecode(utf8.decode(files['rex-manifest.json']!));
      if (manifest is Map &&
          manifest['format'] == 'video.fika.rex.home-package') {
        throw const FormatException(
          '这是 Rex 首页布局包，不是独立模块源。请导入作者的模块集合地址，或单独导入 rex-scripts 里的脚本；首页布局暂不支持，REXENC 加密脚本还需要可用的密钥加载协议或作者提供的明文版本。',
        );
      }
    }
    var manifests = files.keys
        .where((name) => name == 'lume.json' || name.endsWith('/lume.json'))
        .toList();
    if (!files.containsKey('lume.json') && manifests.length == 1) {
      final prefix = manifests.single.substring(
        0,
        manifests.single.length - 'lume.json'.length,
      );
      if (files.keys.every((name) => name.startsWith(prefix))) {
        files = {
          for (final row in files.entries)
            row.key.substring(prefix.length): row.value,
        };
      }
    }
    Map<String, Object?> manifest = {};
    if (files['lume.json'] case final bytes?) {
      manifest = Map<String, Object?>.from(
        jsonDecode(utf8.decode(bytes)) as Map,
      );
    }
    var entry = manifest['entry'] as String?;
    if (entry == null && files['package.json'] != null) {
      final package = jsonDecode(utf8.decode(files['package.json']!)) as Map;
      entry = (package['module'] ?? package['main']) as String?;
      if (entry?.startsWith('./') ?? false) entry = entry!.substring(2);
    }
    if (entry == null) {
      final candidates = files.keys
          .where(
            (name) => [
              'main.py',
              'spider.py',
              'main.mjs',
              'index.mjs',
              'index.js',
            ].contains(name),
          )
          .toList();
      if (candidates.length == 1) entry = candidates.single;
    }
    if (entry == null || !files.containsKey(checkedPath(entry))) {
      throw const FormatException('源包需要 lume.json 指定 entry 入口');
    }
    final runtime =
        '${manifest['runtime'] ?? (entry.endsWith('.py') ? 'python' : 'module')}';
    if (!['python', 'module'].contains(runtime)) {
      throw const FormatException('源包 runtime 应为 python 或 module');
    }
    final protocol =
        '${manifest['protocol'] ?? (runtime == 'python' ? 'spider' : 'lume')}';
    if (!['lume', 'spider'].contains(protocol)) {
      throw const FormatException('源包 protocol 应为 lume 或 spider');
    }
    // Wheels travel with the source, but only architecture-independent wheels
    // can be installed after signing. iOS native wheels belong in the build.
    for (final name
        in files.keys.where((name) => name.endsWith('.whl')).toList()) {
      if (!name.endsWith('-none-any.whl')) {
        throw const FormatException('手机只可导入纯 Python wheel；原生扩展须随 iOS 构建签名');
      }
      final wheel = _unzip(files.remove(name)!);
      for (final row in wheel.entries) {
        if (row.key.endsWith('.so') ||
            row.key.endsWith('.pyd') ||
            row.key.endsWith('.dylib')) {
          throw const FormatException('源包不能加载未签名原生扩展');
        }
        if (files.containsKey(row.key)) throw const FormatException('依赖文件路径重复');
        files[row.key] = row.value;
      }
    }
    var total = 0;
    for (final row in files.entries) {
      total += row.value.length;
      if (RegExp(
        r'\.(so|pyd|dylib|fwork|dex|jar|apk)$',
        caseSensitive: false,
      ).hasMatch(row.key)) {
        throw const FormatException('原生扩展须在构建时签名；Java/DEX 需要 Android 后端');
      }
    }
    if (total > maxBytes || files.length > maxFiles) {
      throw const FormatException('源包及依赖超过大小上限');
    }
    return SourceBundle(
      entry,
      runtime,
      protocol,
      files,
      Map<String, Object?>.from(manifest['metadata'] as Map? ?? {}),
    );
  }

  String encode() => base64Encode(
    utf8.encode(
      jsonEncode({
        'entry': entry,
        'runtime': runtime,
        'protocol': protocol,
        'files': files.map(
          (name, bytes) => MapEntry(name, base64Encode(bytes)),
        ),
      }),
    ),
  );

  static SourceBundle? parse(String script) {
    final match = RegExp(
      r'^(?:#|//) LumeBundle: ([A-Za-z0-9+/=]+)$',
      multiLine: true,
    ).firstMatch(script);
    if (match == null) return null;
    final data = jsonDecode(utf8.decode(base64Decode(match[1]!))) as Map;
    final files = (data['files'] as Map).map(
      (key, value) => MapEntry(checkedPath('$key'), base64Decode('$value')),
    );
    final entry = checkedPath('${data['entry']}');
    if (!files.containsKey(entry) ||
        files.length > maxFiles ||
        files.values.fold<int>(0, (n, bytes) => n + bytes.length) > maxBytes) {
      throw const FormatException('源包内容无效或过大');
    }
    return SourceBundle(
      entry,
      '${data['runtime']}',
      '${data['protocol']}',
      files,
      {},
    );
  }

  /// Resolve bundled JS dependencies using POSIX names on every platform.
  String resolve(String parent, String specifier) {
    if (specifier.contains(':') || specifier.startsWith('/')) {
      throw FormatException('模块依赖须放入源包：$specifier');
    }
    final relative = Uri.parse(specifier).path;
    final path = specifier.startsWith('.')
        ? p.posix.normalize(p.posix.join(p.posix.dirname(parent), relative))
        : 'node_modules/$specifier';
    checkedPath(path);
    for (final candidate in [
      path,
      '$path.js',
      '$path.mjs',
      '$path.cjs',
      '$path.json',
      '$path/index.js',
      '$path/index.mjs',
    ]) {
      if (files.containsKey(candidate)) return candidate;
    }
    if (files['$path/package.json'] case final bytes?) {
      final package = jsonDecode(utf8.decode(bytes)) as Map;
      return resolve(
        '$path/package.json',
        './${package['module'] ?? package['main'] ?? 'index.js'}',
      );
    }
    throw FormatException('源包缺少模块依赖：$specifier');
  }
}
