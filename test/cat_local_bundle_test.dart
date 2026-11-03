import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/cat/cat_local_bundle.dart';

void main() {
  List<int> zip(Map<String, String> files) {
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile.string(entry.key, entry.value));
    }
    return ZipEncoder().encode(archive);
  }

  final fixture = {
    'index.js': 'module.exports={start(){}}',
    'index.config.js': 'module.exports={sites:[]}',
  };
  test('根目录与单层目录运行包，校验文件可选', () {
    for (final prefix in ['', 'dist/']) {
      final parsed = CatLocalBundle.fromZip(
        zip({for (final e in fixture.entries) '$prefix${e.key}': e.value}),
      );
      expect(
        parsed.hash,
        md5.convert(fixture['index.js']!.codeUnits).toString(),
      );
    }
  });
  test('校验文件存在时严格匹配，修改内容会被拒绝', () {
    final files = {
      ...fixture,
      'index.js.md5': md5.convert(fixture['index.js']!.codeUnits).toString(),
    };
    expect(CatLocalBundle.fromZip(zip(files)).index, isNotEmpty);
    files['index.js'] = 'changed';
    expect(() => CatLocalBundle.fromZip(zip(files)), throwsFormatException);
  });
  test('缺失配置、多份入口与越界路径均拒绝', () {
    for (final files in [
      {'index.js': 'test'},
      {...fixture, 'other/index.js': 'test'},
      {...fixture, '../outside.js': 'test'},
    ]) {
      expect(() => CatLocalBundle.fromZip(zip(files)), throwsFormatException);
    }
  });
}
