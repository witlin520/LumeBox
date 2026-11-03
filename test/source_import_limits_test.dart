import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/net/rex_collection.dart';
import 'package:lume_box/core/net/source_import_input.dart';
import 'package:lume_box/core/net/source_subscription.dart';
import 'package:lume_box/core/source/source_package.dart';

void main() {
  test('default pasted manifests accept 2000 URLs rather than 20 or 200', () {
    final input = SourceImportInput.classify(
      [for (var i = 0; i < 2001; i++) 'https://fixture.test/$i.js'].join('\n'),
    );
    expect(input.urls, hasLength(2000));
    expect(SourceSubscription.defaultMaxScripts, 2000);
  });

  test('manifest comments mentioning LumeSource are not executed as JavaScript', () async {
    const manifest =
        '# Single-file source scripts (`// LumeSource: {...}` header)\n'
        'https://fixture.test/video/one.js\nhttps://fixture.test/video/two.js';
    expect(SourceSubscription.looksLikeScript(manifest), isFalse);
    final subscription = SourceSubscription(
      fetch: (url) async {
        final text = url.endsWith('/videos-hd')
            ? manifest
            : '// LumeSource: {}\nLumeSource = {};';
        return SourceFetchResult(bytes: utf8.encode(text), text: text);
      },
    );
    final refs = await subscription.resolveRefs([
      'https://fixture.test/videos-hd',
    ]);
    expect(refs.map((r) => r.url), [
      'https://fixture.test/video/one.js',
      'https://fixture.test/video/two.js',
    ]);
    expect(subscription.complete, isTrue);
  });

  test('nested subscription resolves 2000 sources and flags truncation', () async {
    final fetched = <String>[];
    final subscription = SourceSubscription(
      fetch: (url) async {
        fetched.add(url);
        final text = url.endsWith('/index')
            ? [for (var i = 0; i < 2001; i++) 'https://fixture.test/$i.js']
                  .join('\n')
            : '// LumeSource: ${jsonEncode({'id': url, 'name': 'fixture', 'version': '1', 'category': 'video'})}\nLumeSource = {};';
        return SourceFetchResult(bytes: utf8.encode(text), text: text);
      },
    );
    expect(
      await subscription.resolveRefs(['https://fixture.test/index']),
      hasLength(2000),
    );
    expect(subscription.complete, isFalse);
    expect(fetched, hasLength(2001));
  });

  test(
    'Rex collections accept 2000 entries and still bound malformed giant lists',
    () {
      String collection(int count) => jsonEncode({
        'widgets': [
          for (var i = 0; i < count; i++)
            {'id': '$i', 'url': 'https://fixture.test/$i.js'},
        ],
      });
      expect(RexCollection.parse(collection(2000)).entries, hasLength(2000));
      expect(
        () => RexCollection.parse(collection(2001)),
        throwsFormatException,
      );
    },
  );

  test('Rex homepage ZIP explains layout versus source instead of asking for lume.json', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'rex-manifest.json',
          jsonEncode({'format': 'video.fika.rex.home-package', 'version': 1}),
        ),
      )
      ..addFile(ArchiveFile.string('rex-scripts/home.js', 'REXENC\nencrypted'));
    expect(
      () => SourcePackage.fromBytes(
        ZipEncoder().encode(archive),
        name: 'home.rex',
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('首页布局包'),
        ),
      ),
    );
  });
}
