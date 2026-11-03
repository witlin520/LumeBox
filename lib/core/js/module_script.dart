import 'dart:convert';

import '../source/source_bundle.dart';
import 'spider_module_adapter.dart';

/// ESM/CommonJS module graphs. Source spans are tokenized before rewriting
/// exports: text in comments, strings and template literals is never replaced.
class ModuleScript {
  /// Ignore CommonJS probes inside embedded UMD libraries and quoted text.
  static bool hasCommonJsExport(String script) {
    if (!RegExp(r'\bmodule\s*\.\s*exports\b').hasMatch(script)) return false;
    final List<({String value, int start, int end})> tokens;
    try {
      tokens = _tokens(script);
    } on FormatException {
      return false;
    }
    var depth = 0;
    var exported = false, globalSource = false;
    for (var i = 0; i + 3 < tokens.length; i++) {
      final value = tokens[i].value;
      if (depth == 0 && value == 'LumeSource' && tokens[i + 1].value == '=') {
        globalSource = true;
      }
      if (value == 'module' &&
          tokens[i + 1].value == '.' &&
          tokens[i + 2].value == 'exports' &&
          ['=', '.'].contains(tokens[i + 3].value)) {
        exported = true;
      }
      if (['{', '[', '('].contains(value)) depth++;
      if (['}', ']', ')'].contains(value)) depth--;
    }
    return exported && !globalSource;
  }

  static const builtins = {
    'crypto',
    'node:crypto',
    'buffer',
    'node:buffer',
    'pako',
  };

  /// Read only literal identity fields from a top-level metadata assignment.
  /// Comments, strings and nested objects are skipped by the module tokenizer.
  static Map<String, String>? objectStringFields(String script, String name) {
    final tokens = _tokens(script);
    String? literal(int i) {
      if (tokens[i].value != '<literal>') return null;
      final raw = script.substring(tokens[i].start, tokens[i].end);
      if (raw.startsWith('"')) {
        try {
          final value = jsonDecode(raw);
          return value is String ? value : null;
        } catch (_) {
          return null;
        }
      }
      if (raw.startsWith("'") && !raw.contains(r'\')) {
        return raw.substring(1, raw.length - 1);
      }
      return null;
    }

    var depth = 0;
    for (var i = 0; i + 2 < tokens.length; i++) {
      final value = tokens[i].value;
      if (depth == 0 &&
          value == name &&
          tokens[i + 1].value == '=' &&
          tokens[i + 2].value == '{') {
        final fields = <String, String>{};
        var level = 1;
        for (var j = i + 3; j + 2 < tokens.length && level > 0; j++) {
          final key = tokens[j].value;
          if (level == 1 && tokens[j + 1].value == ':') {
            final property = literal(j) ?? key;
            final text = literal(j + 2);
            if (text != null && ['id', 'title', 'version'].contains(property)) {
              fields[property] = text;
            }
          }
          if (['{', '[', '('].contains(key)) level++;
          if (['}', ']', ')'].contains(key)) level--;
        }
        return fields;
      }
      if (['{', '[', '('].contains(value)) depth++;
      if (['}', ']', ')'].contains(value)) depth--;
    }
    return null;
  }

  static Set<String> dependencies(String script) {
    final result = <String>{};
    _body(script, (path) {
      result.add(path);
      return path;
    });
    return result;
  }

  static String wrap(String script) {
    final bundle = SourceBundle.parse(script);
    final bodies = <String, String>{};
    final entry = bundle?.entry ?? 'main.js';
    void visit(String path) {
      if (bodies.containsKey(path)) return;
      bodies[path] = '';
      final text = bundle == null ? script : utf8.decode(bundle.files[path]!);
      if (path.endsWith('.json')) {
        bodies[path] = 'module.exports = ${jsonEncode(jsonDecode(text))};';
        return;
      }
      final dependencies = <String, String>{};
      String resolve(String name) {
        if (builtins.contains(name)) return name;
        if (bundle == null) throw const FormatException('跨文件模块请连同依赖打包为 ZIP 源包');
        final target = bundle.resolve(path, name);
        dependencies[name] = target;
        return target;
      }

      bodies[path] = _body(text, resolve);
      for (final target in dependencies.values) {
        visit(target);
      }
    }

    visit(entry);
    return '''
(function () {
  var factories = {${bodies.entries.map((row) => '${jsonEncode(row.key)}: function(module, exports, require) {\n${row.value}\n}').join(',\n')}};
  var cache = Object.create(null);
  function require(path) {
    if (path === 'pako') return globalThis.pako;
    if (path === 'buffer' || path === 'node:buffer') return {Buffer: globalThis.Buffer};
    if (path === 'crypto' || path === 'node:crypto') return globalThis.__lumeModules.crypto;
    if (cache[path]) return cache[path].exports;
    if (!factories[path]) throw new Error('源包缺少模块：' + path);
    var module = {exports:{}}; cache[path] = module;
    factories[path](module, module.exports, require);
    return module.exports;
  }
  var exported = require(${jsonEncode(entry)});
  var source = exported.default || exported;
  if (!source || typeof source !== 'object') throw new Error('模块须导出源对象');
  if (!Object.keys(source).length) throw new Error('模块没有导出源接口');
  if (${bundle?.protocol == 'spider'} || (!source.categories && (source.home || source.homeContent))) {
    source = ($spiderModuleAdapter)(source);
  }
  LumeSource = source;
})();
''';
  }

  static String _body(String script, String Function(String) resolve) {
    final tokens = _tokens(script);
    final edits = <({int start, int end, String text})>[];
    final names = <String>[];
    final prelude = <String>[];
    final epilogue = <String>[];
    String literal(int index) {
      final token = tokens.elementAtOrNull(index);
      if (token?.value != '<literal>') {
        throw const FormatException('模块依赖须为字符串字面量');
      }
      final value = script.substring(token!.start, token.end);
      if (!(value.startsWith('"') || value.startsWith("'")) ||
          value.contains(r'\')) {
        throw const FormatException('模块路径不支持转义或模板表达式');
      }
      return value.substring(1, value.length - 1);
    }

    var depth = 0;
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.value == 'require' &&
          tokens.elementAtOrNull(i + 1)?.value == '(' &&
          tokens.elementAtOrNull(i + 2)?.value == '<literal>') {
        final path = resolve(literal(i + 2));
        edits.add((
          start: tokens[i + 2].start,
          end: tokens[i + 2].end,
          text: jsonEncode(path),
        ));
      }
      if (token.value == 'import' &&
          tokens.elementAtOrNull(i + 1)?.value == '(') {
        final path = resolve(literal(i + 2));
        edits.add((
          start: token.start,
          end: tokens[i + 3].end,
          text: 'Promise.resolve(require(${jsonEncode(path)}))',
        ));
        i += 3;
        continue;
      }
      if (depth == 0 && token.value == 'import') {
        var end = i + 1;
        final sideEffect = tokens[end].value == '<literal>';
        if (!sideEffect) {
          while (end < tokens.length && tokens[end].value != 'from') {
            end++;
          }
          end++;
        }
        final path = resolve(literal(end));
        final temp = '__lume_import_${prelude.length}';
        prelude.add('var $temp = require(${jsonEncode(path)});');
        var j = i + 1;
        if (!sideEffect && _identifier(tokens[j].value)) {
          prelude.add(
            'var ${tokens[j++].value} = Object.prototype.hasOwnProperty.call($temp, "default") ? $temp.default : $temp;',
          );
          if (tokens[j].value == ',') j++;
        }
        if (!sideEffect && tokens[j].value == '*') {
          if (tokens[j + 1].value != 'as' ||
              !_identifier(tokens[j + 2].value)) {
            throw const FormatException('模块命名空间导入无效');
          }
          prelude.add('var ${tokens[j + 2].value} = $temp;');
        } else if (!sideEffect && tokens[j].value == '{') {
          j++;
          while (tokens[j].value != '}') {
            final imported = tokens[j++].value;
            if (imported == ',') continue;
            var local = imported;
            if (tokens[j].value == 'as') {
              j++;
              local = tokens[j++].value;
            }
            if (!_identifier(imported) || !_identifier(local)) {
              throw const FormatException('模块具名导入无效');
            }
            prelude.add('var $local = $temp[${jsonEncode(imported)}];');
          }
        }
        edits.add((start: token.start, end: tokens[end].end, text: ''));
        i = end;
        continue;
      }
      if (depth == 0 && token.value == 'export') {
        final next = tokens.elementAtOrNull(i + 1);
        if (next?.value == 'default') {
          edits.add((
            start: token.start,
            end: next!.end,
            text: 'module.exports.default =',
          ));
        } else if (next?.value == '*') {
          final path = resolve(literal(i + 3));
          edits.add((
            start: token.start,
            end: tokens[i + 3].end,
            text: 'Object.assign(exports, require(${jsonEncode(path)}));',
          ));
          i += 3;
          continue;
        } else if (next?.value == '{') {
          var j = i + 2;
          final bindings = <String>[];
          while (j < tokens.length && tokens[j].value != '}') {
            final local = tokens[j++].value;
            if (local == ',') continue;
            var exported = local;
            if (tokens.elementAtOrNull(j)?.value == 'as') {
              j++;
              exported = tokens[j++].value;
            }
            if (!_identifier(local) || !_identifier(exported)) {
              throw const FormatException('模块 export 列表格式不支持');
            }
            bindings.add('exports[${jsonEncode(exported)}] = $local;');
          }
          if (j == tokens.length) {
            throw const FormatException('模块 export 列表未闭合');
          }
          if (tokens.elementAtOrNull(j + 1)?.value == 'from') {
            final target = resolve(literal(j + 2));
            final temp = '__lume_reexport_${prelude.length}';
            prelude.add('var $temp = require(${jsonEncode(target)});');
            for (var k = 0; k < bindings.length; k++) {
              final binding = bindings[k];
              final equals = binding.indexOf(' = ');
              final local = binding.substring(equals + 3, binding.length - 1);
              final value = local == 'default'
                  ? '(Object.prototype.hasOwnProperty.call($temp, "default") ? $temp.default : $temp)'
                  : '$temp[${jsonEncode(local)}]';
              bindings[k] = '${binding.substring(0, equals)} = $value;';
            }
            j += 2;
          }
          epilogue.addAll(bindings);
          edits.add((start: token.start, end: tokens[j].end, text: ''));
          i = j;
          continue;
        } else {
          var declaration = i + 1;
          if (tokens.elementAtOrNull(declaration)?.value == 'async') {
            declaration++;
          }
          final keyword = tokens.elementAtOrNull(declaration)?.value;
          final name = tokens.elementAtOrNull(declaration + 1)?.value;
          if (!['function', 'class', 'const', 'let', 'var'].contains(keyword) ||
              name == null ||
              !_identifier(name)) {
            throw const FormatException(
              '模块 export 写法不支持；请使用 export default 对象',
            );
          }
          // Multiple variable bindings and destructuring are deliberately rejected.
          if (['const', 'let', 'var'].contains(keyword)) {
            var nesting = 0;
            for (var j = declaration + 2; j < tokens.length; j++) {
              final value = tokens[j].value;
              if (nesting == 0 && value == ';') break;
              if (nesting == 0 && value == ',') {
                throw const FormatException('请将模块 export 的多个变量拆成独立声明');
              }
              if (['(', '[', '{'].contains(value)) nesting++;
              if ([')', ']', '}'].contains(value)) nesting--;
            }
          }
          names.add(name);
          edits.add((start: token.start, end: token.end, text: ''));
        }
      }
      if (token.value == '{') depth++;
      if (token.value == '}') depth--;
    }
    var body = script;
    for (final edit in edits.reversed) {
      body = body.replaceRange(edit.start, edit.end, edit.text);
    }
    return '''
${prelude.join('\n')}
$body
${names.map((name) => 'exports[${jsonEncode(name)}] = $name;').join('\n')}
${epilogue.join('\n')}
''';
  }

  static bool _identifier(String value) =>
      RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(value);

  static List<({String value, int start, int end})> _tokens(String text) {
    final result = <({String value, int start, int end})>[];
    var i = 0;
    String? previous;
    while (i < text.length) {
      final c = text[i];
      if (RegExp(r'\s').hasMatch(c)) {
        i++;
        continue;
      }
      if (text.startsWith('//', i)) {
        final end = text.indexOf('\n', i + 2);
        i = end < 0 ? text.length : end + 1;
        continue;
      }
      if (text.startsWith('/*', i)) {
        final end = text.indexOf('*/', i + 2);
        if (end < 0) throw const FormatException('模块注释未闭合');
        i = end + 2;
        continue;
      }
      final start = i;
      if (c == '"' || c == "'" || c == '`') {
        i++;
        while (i < text.length) {
          if (text[i] == r'\') {
            i += 2;
            continue;
          }
          if (text[i++] == c) break;
        }
        result.add((value: '<literal>', start: start, end: i));
        previous = '<literal>';
        continue;
      }
      if (c == '/' &&
          (previous == null ||
              [
                '=',
                '(',
                '[',
                ',',
                ':',
                'return',
                '=>',
                '!',
                '?',
              ].contains(previous))) {
        i++;
        var characterClass = false;
        while (i < text.length) {
          if (text[i] == r'\') {
            i += 2;
            continue;
          }
          if (text[i] == '[') characterClass = true;
          if (text[i] == ']') characterClass = false;
          if (text[i++] == '/' && !characterClass) break;
        }
        while (i < text.length && RegExp(r'[A-Za-z]').hasMatch(text[i])) {
          i++;
        }
        previous = '<literal>';
        result.add((value: previous, start: start, end: i));
        continue;
      }
      if (RegExp(r'[A-Za-z_$]').hasMatch(c)) {
        i++;
        while (i < text.length && RegExp(r'[\w$]').hasMatch(text[i])) {
          i++;
        }
      } else {
        i++;
      }
      previous = text.substring(start, i);
      result.add((value: previous, start: start, end: i));
    }
    return result;
  }
}
