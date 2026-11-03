import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/source/source_presentation_cache.dart';

String script(
  String site, {
  String icon = '/icon.png',
  String kind = 'video',
}) =>
    '// LumeSource: {"id":"fixture","name":"Fixture","version":"1.0.0","category":"video","mediaType":"$kind","contentCategory":"movie","mirrors":["$site"],"icon":"$icon"}\n'
    '// LumeRuntime: javascript\nvar BASE_URL = "$site";';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'catalog parsing yields to UI events and reuses unchanged metadata',
    () async {
      final cache = SourcePresentationCache();
      final entries = [
        for (var i = 0; i < 150; i++)
          (
            key: 'video/$i',
            script: '${script('https://site$i.test')}\n//${'x' * 20000}',
          ),
      ];
      var responsive = false;
      Timer.run(() => responsive = true);
      final first = await cache.prepare(entries);
      expect(
        responsive,
        isTrue,
        reason: 'cold catalog parsing must leave the UI event loop free',
      );
      final second = await cache.prepare(entries);
      expect(first.length, 150);
      for (var i = 0; i < first.length; i++) {
        expect(identical(first[i], second[i]), isTrue);
      }
      expect(first.first.siteUrl, 'https://site0.test');
      expect(first.first.iconUrl, 'https://site0.test/icon.png');
    },
  );

  test('same-version changed scripts invalidate derived fields and sections stay isolated', () async {
    final cache = SourcePresentationCache();
    final old = script('https://old.test');
    final initial = await cache.prepare([
      (key: 'video/a', script: old),
      (key: 'comic/a', script: old),
    ]);
    final next = await cache.prepare([
      (key: 'video/a', script: script('https://new.test', kind: 'audio')),
      (key: 'comic/a', script: old),
    ]);
    expect(next[0].siteUrl, 'https://new.test');
    expect(next[0].mediaKind, 'audio');
    expect(identical(initial[1], next[1]), isTrue);
    cache.clearSection('video');
    expect(identical(cache.read('comic/a', old), next[1]), isTrue);
    expect(identical(cache.read('video/a', old), initial[0]), isFalse);
  });

  test('catalogs larger than cache limits still return worker results for every source', () async {
    final cache = SourcePresentationCache(maxEntries: 1, maxCharacters: 350);
    final entries = [
      for (var i = 0; i < 3; i++)
        (key: 'video/$i', script: script('https://site$i.test')),
    ];
    final infos = await cache.prepare(entries);
    expect(infos.map((i) => i.siteUrl), [
      'https://site0.test',
      'https://site1.test',
      'https://site2.test',
    ]);
    expect(
      identical(cache.read(entries.last.key, entries.last.script), infos.last),
      isTrue,
    );
    expect(
      identical(
        cache.read(entries.first.key, entries.first.script),
        infos.first,
      ),
      isFalse,
    );
  });

  test(
    'overlapping catalog loads share parsing and do not mix section results',
    () async {
      final cache = SourcePresentationCache();
      final entry = (key: 'video/a', script: script('https://shared.test'));
      final first = cache.prepare([entry]);
      final second = cache.prepare([entry]);
      expect(identical((await first).single, (await second).single), isTrue);
    },
  );
}
