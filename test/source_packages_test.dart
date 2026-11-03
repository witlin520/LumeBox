import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/js/module_script.dart';
import 'package:lume_box/core/js/python_source_engine.dart';
import 'package:lume_box/core/js/source_script.dart';
import 'package:lume_box/core/net/source_import_input.dart';
import 'package:lume_box/core/net/source_subscription.dart';
import 'package:lume_box/core/source/source_package.dart';
import 'package:lume_box/core/session/section.dart';

void main() {
  test('明确的 JS 标记不被正文中的 Python 示例误分，模块标记优先于内嵌 JS 标记', () {
    const script =
        '// LumeSource: {"id":"maker","name":"示例","version":"1"}\n'
        '// LumeRuntime: javascript\n'
        'var example = `\nclass Spider:\n    pass\n`;\n'
        'var LumeSource = {list: async function(){return {items:[]};}};';
    final imported = SourcePackage.fromBytes(
      utf8.encode(script),
      name: '示例.js',
    );
    expect(SourcePackage.kindOf(imported), SourcePackageKind.javascript);
    expect(imported, script);
    expect(
      SourcePackage.kindOf('// LumeRuntime: module\n$script'),
      SourcePackageKind.module,
    );
    expect(
      SourcePackage.kindOf('# LumeRuntime: python\n$script'),
      SourcePackageKind.python,
    );
  });
  const python =
      'from base.spider import Spider\nclass Spider(Spider):\n    pass\n';
  test('Python 本地导入有稳定元信息，覆盖和恢复保留同一个 id', () {
    final first = SourceImportInput.classify(python, name: '影探4K.py');
    final second = SourceImportInput.classify(
      '$python# updated',
      name: '影探4K.py',
    );
    expect(first.isScript, isTrue);
    expect(SourcePackage.kindOf(first.text), SourcePackageKind.python);
    final meta = SourceMetadata.parseHeader(first.text)!;
    expect(meta.name, '影探4K');
    expect(meta.category, isEmpty);
    expect(SourceMetadata.parseHeader(second.text)!.id, meta.id);
    expect(SourcePackage.prepare(first.text), first.text);
  });

  test('Python 明确声明的漫画或视频归属不被导入入口改写', () {
    for (final section in [Section.comic, Section.video]) {
      final raw =
          '# LumeSource: {"id":"declared-py","name":"PY","version":"1","category":"${section.id}"}\n$python';
      final metadata = SourceMetadata.parseHeader(
        SourcePackage.prepare(raw, name: 'source.py'),
      )!;
      expect(metadata.sectionMismatch(section), isNull);
      expect(
        metadata.sectionMismatch(
          section == Section.comic ? Section.video : Section.comic,
        ),
        isNotNull,
      );
    }
  });

  test('Python / ESM / CommonJS 订阅识别，URL 身份不随正文变化', () async {
    for (final text in [
      python,
      'export default {list(){return []}}',
      'module.exports = {list(){return []}}',
    ]) {
      expect(SourceSubscription.looksLikeScript(text), isTrue);
      final script = SourcePackage.prepare(
        text,
        originUrl: 'https://example.org/测试.py',
      );
      final updated = SourcePackage.prepare(
        '$text\n// revision',
        originUrl: 'https://example.org/测试.py',
      );
      expect(
        SourceMetadata.parseHeader(script)!.id,
        SourceMetadata.parseHeader(updated)!.id,
      );
    }
  });

  test('非 UTF-8 Python 文件保留字节，交由 CPython 按编码声明解码', () {
    final script = SourcePackage.fromBytes([
      ...ascii.encode('# coding: latin-1\nclass Spider:\n    title="'),
      0xe9,
      ...ascii.encode('"\n'),
    ], name: 'legacy.py');
    expect(script, contains('# LumePythonBytes: '));
    expect(SourcePackage.kindOf(script), SourcePackageKind.python);
    final utf8Script = SourcePackage.fromBytes([
      0xef,
      0xbb,
      0xbf,
      ...utf8.encode(python),
    ], name: 'bom.py');
    expect(utf8Script, isNot(contains('\ufeff')));
  });

  test('模块只改语法 token，不篡改字符串和注释', () {
    final wrapped = ModuleScript.wrap(r'''
// export default and module.exports in a comment
const text = "export default {broken}";
const template = `export default {also literal}`;
export const list = () => [{id: 'one', title: text}];
export default {list};
''');
    expect(wrapped, contains('"export default {broken}"'));
    expect(wrapped, contains('`export default {also literal}`'));
    expect(wrapped, contains('module.exports.default = {list}'));
    expect(wrapped, contains('exports["list"] = list;'));
    expect(
      () => ModuleScript.wrap('import x from "remote"; export default x;'),
      throwsFormatException,
    );
    expect(
      () => ModuleScript.wrap('export {source} from "remote";'),
      throwsFormatException,
    );
  });

  Map<String, dynamic> payload(
    String mode, {
    bool encrypt = true,
    String data = '',
  }) => {
    'algorithm': mode == 'chacha' ? 'chacha' : 'aes',
    'mode': mode == 'gcm' ? 11 : 2,
    'key': base64Encode(List.filled(mode == 'chacha' ? 32 : 16, 0)),
    'iv': base64Encode(List.filled(16, 0)),
    'nonce': base64Encode(List.filled(mode == 'chacha' ? 24 : 12, 0)),
    'aad': '',
    'data': data,
    'encrypt': encrypt,
  };
  String hex(String encoded) =>
      base64Decode(encoded)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

  test('AES CBC / GCM 对照 NIST 已知结果', () {
    expect(
      hex(
        PythonCrypto.run(
          payload('cbc', data: base64Encode(List.filled(16, 0))),
        ),
      ),
      '66e94bd4ef8a2c3b884cfa59ca342b2e',
    );
    expect(
      hex(PythonCrypto.run(payload('gcm'))),
      '58e2fccefa7e3061367f1d57a4e7455a',
    );
    final input = base64Encode(utf8.encode('中文明文'));
    final encrypted = PythonCrypto.run(payload('gcm', data: input));
    expect(
      PythonCrypto.run(payload('gcm', encrypt: false, data: encrypted)),
      input,
    );
    final altered = base64Decode(encrypted)..[0] ^= 1;
    expect(
      () => PythonCrypto.run(
        payload('gcm', encrypt: false, data: base64Encode(altered)),
      ),
      throwsA(anything),
    );
  });

  test('AES CTR 对照 NIST 向量，CFB / OFB 支持不足一块的文本', () {
    List<int> unhex(String value) => [
      for (var i = 0; i < value.length; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16),
    ];
    final request = payload(
      'cbc',
      data: base64Encode(unhex('6bc1bee22e409f96e93d7e117393172a')),
    );
    request['mode'] = 6;
    request['key'] = base64Encode(unhex('2b7e151628aed2a6abf7158809cf4f3c'));
    request['iv'] = base64Encode(unhex('f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff'));
    expect(hex(PythonCrypto.run(request)), '874d6191b620e3261bef6864990db6ce');
    for (final mode in [3, 5]) {
      final input = base64Encode(utf8.encode('不足一块'));
      final settings = {
        ...request,
        'mode': mode,
        'segmentSize': 128,
        'data': input,
      };
      final encrypted = PythonCrypto.run(settings);
      expect(
        PythonCrypto.run({...settings, 'encrypt': false, 'data': encrypted}),
        input,
      );
    }
  });

  test('XChaCha20 Poly1305 使用独立 libsodium 向量并校验认证标签', () {
    // Draft XChaCha test vector: key 80..9f, nonce 40..57, AAD 5051...
    List<int> unhex(String value) => [
      for (var i = 0; i < value.length; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16),
    ];
    final request = payload(
      'chacha',
      data: base64Encode(
        ascii.encode(
          "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.",
        ),
      ),
    );
    request['key'] = base64Encode(List.generate(32, (i) => 0x80 + i));
    request['nonce'] = base64Encode(List.generate(24, (i) => 0x40 + i));
    request['aad'] = base64Encode(unhex('50515253c0c1c2c3c4c5c6c7'));
    final encrypted = PythonCrypto.run(request);
    expect(
      hex(encrypted),
      'bd6d179d3e83d43b9576579493c0e939572a1700252bfaccbed2902c21396cbb731c7f1b0b4aa6440bf3a82f4eda7e39ae64c6708c54c216cb96b72e1213b4522f8c9ba40db5d945b11b69b982c1bb9e3f3fac2bc369488f76b2383565d3fff921f9664c97637da9768812f615c68b13b52ec0875924c1c7987947deafd8780acf49',
    );
    expect(
      PythonCrypto.run({...request, 'data': encrypted, 'encrypt': false}),
      request['data'],
    );
  });
}
