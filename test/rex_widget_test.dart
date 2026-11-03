import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/js/rex_widget.dart';
import 'package:lume_box/core/js/source_script.dart';
import 'package:lume_box/core/net/rex_collection.dart';
import 'package:lume_box/core/net/source_import_input.dart';
import 'package:lume_box/core/net/source_subscription.dart';
import 'package:lume_box/core/source/source_package.dart';

String encryptedWidget() =>
    'REXENC\n${jsonEncode({'v': 2, 'mkv': 'rex-1', 'alg': 'A256GCM', 'iv': base64Encode(List.filled(12, 0)), 'kb': base64Encode(List.filled(60, 0))})}\n${base64Encode(List.filled(32, 0))}';

void main() {
  test('Python 明确的运行环境／Spider 声明优先于同名数据字典', () {
    const script =
        "WidgetMetadata = {'id': 'python_data', 'title': 'Python dict'}\nclass Spider:\n    pass\n";
    final prepared = SourcePackage.prepare(script, name: 'source.py');
    expect(SourcePackage.kindOf(prepared), SourcePackageKind.python);
    expect(prepared, startsWith('# LumeRuntime: python'));
  });
  const widget = '''
const unrelated = {id:'wrong', title:'wrong'};
const WidgetMetadata={id:'forward.test.source',title:'测试 Widget',version:'1.2',modules:[{id:'wrong',title:'wrong'}]};
const fetchItems=async p=>[];
''';
  test('Widget 识别、原生 id 映射和重复更新身份独立于来源 URL', () {
    final first = SourcePackage.prepare(widget, name: 'a.js');
    final second = SourcePackage.prepare(
      '$widget\n// changed',
      originUrl: 'https://fixture.invalid/raw',
    );
    final metadata = SourceMetadata.parseHeader(first)!;
    expect(metadata.id, RexWidget.identity('forward.test.source'));
    expect(metadata.name, '测试 Widget');
    expect(metadata.version, '1.2');
    expect(SourceMetadata.parseHeader(second)!.id, metadata.id);
    expect(SourcePackage.kindOf(first), SourcePackageKind.module);
    expect(SourcePackage.prepare(first), first);
    expect(
      RexWidget.matches(
        '// WidgetMetadata={id:"fake"};\nconst text="WidgetMetadata={}";',
      ),
      isFalse,
    );
  });

  test('REXENC 识别保留原文，执行前区分有效加密与损坏信封', () {
    final raw = encryptedWidget();
    final input = SourceImportInput.classify(raw, name: '瓜子(rex).js');
    expect(input.kind, SourceImportInputKind.script);
    expect(input.text, contains(raw));
    expect(
      () => RexWidget.wrap(input.text, {}),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'reason',
          contains('内容密钥'),
        ),
      ),
    );
    expect(
      () => RexWidget.requirePlaintext('REXENC\n{}\nnot-base64'),
      throwsA(isA<FormatException>()),
    );
  });

  test('Rex 集合可从文件／剪贴板识别；严格展开扩展名为空的模块，保留条目名', () async {
    final text = jsonEncode({
      'title': '红果',
      'widgets': [
        {'id': 'one.x', 'title': '明文', 'url': './modules/one/raw'},
        {
          'id': 'two.x',
          'title': '加密',
          'version': '3',
          'url': 'https://fixture.invalid/modules/two/raw',
        },
      ],
    });
    expect(
      SourceImportInput.classify(text, name: 'a.rex').kind,
      SourceImportInputKind.collection,
    );
    final source = SourceSubscription(
      strictManifest: true,
      fetch: (url) async {
        final body = url.endsWith('a.rex')
            ? text
            : url.endsWith('/one/raw')
            ? widget
            : encryptedWidget();
        return SourceFetchResult(bytes: utf8.encode(body), text: body);
      },
    );
    final refs = await source.resolveRefs(['https://fixture.invalid/a.rex']);
    expect(refs.map((e) => e.label), ['明文', '加密']);
    expect(refs.map((e) => e.url), [
      'https://fixture.invalid/modules/one/raw',
      'https://fixture.invalid/modules/two/raw',
    ]);
    expect(SourceMetadata.parseHeader(refs.last.script)!.name, '加密');
    expect(
      SourceMetadata.parseHeader(refs.last.script)!.id,
      RexWidget.identity('two.x'),
    );
    expect(source.complete, isTrue);
  });

  test('多集合共用总量上限，坏条目保留未完整状态，不能静默清除旧订阅', () async {
    final misses = <String>[];
    final resolver = SourceSubscription(
      maxScripts: 3,
      onSkip: (u, e) => misses.add(u),
      fetch: (url) async {
        if (url.endsWith('/bad')) throw StateError('404');
        final prefix = url.endsWith('/a') ? 'a' : 'b';
        final text = url.endsWith('/a') || url.endsWith('/b')
            ? jsonEncode({
                'widgets': [
                  for (final n in ['one', 'bad', 'two'])
                    {'title': n, 'url': 'https://fixture.invalid/$prefix/$n'},
                ],
              })
            : widget;
        return SourceFetchResult(bytes: utf8.encode(text), text: text);
      },
    );
    final refs = await resolver.resolveRefs([
      'https://fixture.invalid/a',
      'https://fixture.invalid/b',
    ]);
    expect(refs.length, 3);
    expect(resolver.complete, isFalse);
    expect(misses, ['https://fixture.invalid/a/bad']);
    expect(
      () => RexCollection.parse('{"widgets":[{"url":"file:///private/x"}]}'),
      throwsFormatException,
    );
  });
}
