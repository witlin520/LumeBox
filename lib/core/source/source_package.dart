import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../js/source_script.dart';
import '../js/module_script.dart';
import 'source_bundle.dart';
import 'remote_spider.dart';
import 'kazumi_rule.dart';
import '../js/rex_widget.dart';

enum SourcePackageKind { javascript, python, module }

/// Runtime markers live with the script, so backup, refresh and restore retain
/// the selected interpreter without a database migration.
class SourcePackage {
  /// Preserve legacy PEP 263 encodings for CPython to decode (GBK etc.).
  static String fromBytes(
    List<int> bytes, {
    String name = '',
    String originUrl = '',
  }) {
    if (SourceBundle.isZip(bytes)) {
      return fromBundle(
        SourceBundle.fromZip(bytes),
        name: name,
        originUrl: originUrl,
      );
    }
    return _fromTextBytes(bytes, name: name, originUrl: originUrl);
  }

  static String fromBundle(
    SourceBundle bundle, {
    String name = '',
    String originUrl = '',
  }) {
    final prefix = bundle.runtime == 'python' ? '#' : '//';
    final header = '$prefix LumeRuntime: ${bundle.runtime}\n';
    final original = SourceMetadata.parseHeader(
      utf8.decode(bundle.files[bundle.entry]!, allowMalformed: true),
    );
    final info = bundle.metadata.isNotEmpty
        ? bundle.metadata
        : original == null
        ? <String, Object?>{}
        : <String, Object?>{
            'id': original.id,
            'name': original.name,
            'version': original.version,
            'category': original.category,
            'mirrors': original.mirrors,
          };
    final metadata = info.isEmpty
        ? ''
        : '$prefix LumeSource: ${jsonEncode(info)}\n';
    return prepare(
      '$header$metadata$prefix LumeBundle: ${bundle.encode()}',
      name: name,
      originUrl: originUrl,
    );
  }

  static String _fromTextBytes(
    List<int> bytes, {
    String name = '',
    String originUrl = '',
  }) {
    final preview = utf8.decode(bytes, allowMalformed: true);
    final python =
        name.toLowerCase().endsWith('.py') ||
        (Uri.tryParse(originUrl)?.path.toLowerCase().endsWith('.py') ??
            false) ||
        kindOf(preview) == SourcePackageKind.python;
    if (!python) {
      final module = RegExp(
        r'\.(mjs|cjs)$',
        caseSensitive: false,
      ).hasMatch(name);
      return prepare(
        module ? '// LumeRuntime: module\n$preview' : preview,
        name: name,
        originUrl: originUrl,
      );
    }
    try {
      final script = stripScriptBom(utf8.decode(bytes));
      return prepare(
        '# LumeRuntime: python\n$script',
        name: name,
        originUrl: originUrl,
      );
    } on FormatException {
      return prepare(
        '# LumeRuntime: python\n# LumePythonBytes: ${base64Encode(bytes)}',
        name: name,
        originUrl: originUrl,
      );
    }
  }

  static SourcePackageKind kindOf(String script) {
    // Exporters explicitly declare their interpreter. Do not let embedded
    // examples/templates or compatibility code override a leading marker.
    final marker = RegExp(
      r'^\s*(?://|#)\s*LumeRuntime:\s*(javascript|python|module)\s*$',
      multiLine: true,
    ).firstMatch(stripScriptBom(script));
    if (marker != null) {
      return SourcePackageKind.values.byName(marker[1]!);
    }
    if (RemoteSpider.matches(script)) return SourcePackageKind.module;
    if (RegExp(
          r'^\s*#\s*LumeRuntime:\s*python',
          multiLine: true,
        ).hasMatch(script) ||
        RegExp(
          r'^class\s+Spider\s*(?:\(|:)',
          multiLine: true,
        ).hasMatch(script) ||
        RegExp(
          r'^def\s+(?:homeContent|getHomeContent)\s*\(',
          multiLine: true,
        ).hasMatch(script)) {
      return SourcePackageKind.python;
    }
    if (RexWidget.matches(script)) return SourcePackageKind.module;
    if (RegExp(
          r'^\s*//\s*LumeRuntime:\s*module',
          multiLine: true,
        ).hasMatch(script) ||
        RegExp(
          r'^\s*export\s+(default|const|let|var|function|async|class|\{)',
          multiLine: true,
        ).hasMatch(script) ||
        RegExp(
          r'''^\s*import\s*(?:\(|["'{*]|[\w$]+\s*(?:,|from))''',
          multiLine: true,
        ).hasMatch(script) ||
        ModuleScript.hasCommonJsExport(script)) {
      return SourcePackageKind.module;
    }
    return SourcePackageKind.javascript;
  }

  static bool looksLikeScript(String text) =>
      KazumiRule.matches(text) || kindOf(text) != SourcePackageKind.javascript;

  /// Give scripts without Lume metadata a stable identity before overwrite
  /// confirmation. URL/file identity survives edits; pasted scripts use content.
  static String prepare(String raw, {String name = '', String originUrl = ''}) {
    final clean = stripScriptBom(raw);
    if (KazumiRule.matches(clean)) {
      return KazumiRule.convert(clean, originUrl: originUrl);
    }
    final script = RemoteSpider.matches(clean)
        ? RemoteSpider.convert(clean)
        : clean;
    final kind = kindOf(script);
    if (kind == SourcePackageKind.module && RexWidget.matches(script)) {
      return RexWidget.prepare(script, name: name, originUrl: originUrl);
    }
    if (kind == SourcePackageKind.javascript) return raw;
    final prefix = kind == SourcePackageKind.python ? '#' : '//';
    final marker = '$prefix LumeRuntime: ${kind.name}';
    final metadata = SourceMetadata.parseHeader(script);
    if (metadata != null) {
      return script.contains(marker) ? script : '$marker\n$script';
    }
    var label = name.trim();
    if (label.isEmpty && originUrl.isNotEmpty) {
      label = Uri.tryParse(originUrl)?.pathSegments.lastOrNull ?? '';
    }
    label = label.replaceFirst(RegExp(r'\.(py|mjs|cjs|js|zip|json)$'), '');
    if (label.isEmpty) {
      label = kind == SourcePackageKind.python ? 'Python 源' : '模块源';
    }
    final identity = originUrl.isNotEmpty
        ? originUrl
        : name.isNotEmpty
        ? name
        : script;
    final id =
        '${kind.name}_${sha256.convert(utf8.encode(identity)).toString().substring(0, 24)}';
    // Bare Python scripts belong to the importing library. An explicit header
    // still controls category validation, so video/comic mismatches are rejected.
    final category = kind == SourcePackageKind.python ? '' : 'video';
    return '$marker\n$prefix LumeSource: ${jsonEncode({'id': id, 'name': label, 'version': '1', 'category': category})}\n$script';
  }
}
