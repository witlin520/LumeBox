import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/web/html_home_import.dart';
import 'package:lume_box/core/web/html_home_sdk.dart';

void main() {
  test(
    'verify caller-supplied HTML and emit the actual SDK for Node contracts',
    () {
      final directory = Platform.environment['LUME_HTML_HOME_DIR'];
      final output = Directory('build/html-home-checks')
        ..createSync(recursive: true);
      final results = <Map<String, Object?>>[];
      if (directory != null) {
        for (final file
            in Directory(directory).listSync().whereType<File>().where(
              (f) => [
                '各大平台直播合集.html',
                'lzxwwogg.html',
                '玩偶聚合.html',
              ].contains(f.uri.pathSegments.last),
            )) {
          final bytes = file.readAsBytesSync();
          final source = HtmlHomeImport.decode(
            file.uri.pathSegments.last,
            bytes,
          );
          expect(source.isLocal, true);
          expect(source.html, contains('fm.'));
          results.add({
            'file': file.path,
            'id': source.id,
            'name': source.name,
            'bytes': bytes.length,
          });
        }
        expect(results, hasLength(3));
      }
      File('${output.path}/sdk.js').writeAsStringSync(
        htmlHomeSdk(
          'http://127.0.0.1:1111/session/rpc',
          {'theme': 'green', 'escaped': '</script>'},
          {'chromeMode': 'normal', 'safeTop': 0, 'safeBottom': 0},
        ),
      );
      File(
        '${output.path}/files.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
    },
  );
}
