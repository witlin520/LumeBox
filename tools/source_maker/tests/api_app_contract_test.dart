import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume_box/core/js/lume_js_engine.dart';
import 'package:lume_box/core/js/source_engine.dart';
import 'package:lume_box/core/net/lume_http.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/source/source_package.dart';

import '../../../test/js_sandbox/support/js_sandbox_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final available = installBridge();
  late Directory root;
  late Map<String, dynamic> responses;
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('maker-api-contract-');
    final result = await Process.run('python', [
      'tools/source_maker/tests/make_api_fixture.py',
      root.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    responses = jsonDecode(
      File('${root.path}/responses.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    enableEngineOnThisPlatform();
    await installTempSectionRoot(root);
  });
  tearDownAll(() async {
    await SectionScope.closeAll();
    restoreEnginePlatformGate();
    await root.delete(recursive: true);
  });
  for (final target in ['video', 'module']) {
    test(
      'MediaCMS $target uses real App models for covers, taxonomy, filters and media',
      () async {
        final requests = <Uri>[];
        final engine = await LumeJsEngine.create(
          sourceId: 'maker-api-$target',
          section: Section.video,
          http: LumeHttp(
            client: MockClient((r) async {
              requests.add(r.url);
              final pairs =
                  r.url.queryParameters.entries
                      .map((e) => [e.key, e.value])
                      .toList()
                    ..sort((a, b) => a[0].compareTo(b[0]));
              final key = '${r.url.path}?${jsonEncode(pairs)}';
              return http.Response(
                responses[key] as String? ?? 'missing fixture',
                responses.containsKey(key) ? 200 : 404,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        );
        addTearDown(engine.dispose);
        final ext = target == 'module' ? 'cjs' : 'js';
        final raw = File('${root.path}/$target.$ext').readAsStringSync();
        final adapter = QuickJsSourceEngine(engine);
        expect(
          await adapter.loadScript(SourcePackage.prepare(raw)),
          isTrue,
          reason: '${adapter.loadFailure}',
        );
        final source = JsDataSource(
          id: 'maker-api-$target',
          name: 'Public CMS',
          section: Section.video,
          runtime: _Runtime(engine),
        );
        final cats = await source.categories();
        expect(cats.last.title, '科学 教学');
        expect((await source.filters()).length, 3);
        final first = await source.list();
        expect(first.items.length, 2);
        expect(
          first.items.first.cover.toString(),
          'https://example.test/cover-one.jpg',
        );
        final category = await source.list(categoryId: cats.last.id);
        expect(category.items.single.id, endsWith('m=two'));
        expect(requests.last.queryParameters['c'], '科学 教学');
        expect(
          (await source.list(filters: {'sort_by': 'views_desc'}))
              .items
              .first
              .id,
          endsWith('m=two'),
        );
        expect(
          (await source.list(filters: {'duration': '0-20'})).items.single.id,
          endsWith('m=one'),
        );
        expect(
          (await source.list(filters: {'upload_date': 'today'})).items,
          isEmpty,
        );
        expect(
          (await source.list(page: 2)).items.single.id,
          endsWith('m=three'),
        );
        final id = first.items.first.id;
        expect((await source.detail(id))!.title, 'Lesson');
        final chapters = await source.chapters(id);
        final content = await source.content(
          itemId: id,
          chapterId: chapters.single.id,
        ) as VideoContent;
        expect(content.url.toString(), 'https://example.test/lesson.mp4');
        expect(content.headers['Referer'], id);
      },
      skip: available ? false : 'QuickJS bridge unavailable',
    );
  }
  for (final target in ['nuxt', 'wordpress']) {
    test(
      '$target generated source runs through actual App QuickJS and content models',
      () async {
        final requests = <Uri>[];
        final engine = await LumeJsEngine.create(
          sourceId: 'maker-api-$target',
          section: Section.video,
          http: LumeHttp(
            client: MockClient((r) async {
              requests.add(r.url);
              final pairs =
                  r.url.queryParameters.entries
                      .map((e) => [e.key, e.value])
                      .toList()
                    ..sort((a, b) => a[0].compareTo(b[0]));
              final key = '${r.url.path}?${jsonEncode(pairs)}';
              return http.Response(
                responses[key] as String? ?? 'missing fixture $key',
                responses.containsKey(key) ? 200 : 404,
                headers: {'content-type': 'text/html; charset=utf-8'},
              );
            }),
          ),
        );
        addTearDown(engine.dispose);
        final raw = File('${root.path}/$target.js').readAsStringSync();
        final adapter = QuickJsSourceEngine(engine);
        expect(
          await adapter.loadScript(SourcePackage.prepare(raw)),
          isTrue,
          reason: '${adapter.loadFailure}',
        );
        final source = JsDataSource(
          id: 'maker-api-$target',
          name: 'Public data',
          section: Section.video,
          runtime: _Runtime(engine),
        );
        final list = await source.list();
        expect(list.items.length, target == 'nuxt' ? 2 : 1);
        expect(list.items.first.cover, isNotNull);
        if (target == 'wordpress') {
          final categories = await source.categories();
          expect(categories.last.title, 'Science');
          expect(
            (await source.list(categoryId: categories.last.id)).items.single.id,
            '8',
          );
          expect(
            (await source.list(filters: {'sort_by': 'oldest'})).items.single.id,
            '8',
          );
          expect((await source.list(keyword: '中文')).items.single.id, '8');
        }
        final id = list.items.first.id;
        expect((await source.detail(id))!.title, isNotEmpty);
        final chapter = (await source.chapters(id)).first;
        final content = await source.content(
          itemId: id,
          chapterId: chapter.id,
        ) as VideoContent;
        expect(
          content.url.toString(),
          target == 'nuxt'
              ? 'https://media.test/lesson.mp4'
              : 'https://example.test/blog/media/lesson.mp4',
        );
        if (target == 'wordpress') {
          expect(
            content.headers['Referer'],
            'https://example.test/blog/lesson/',
          );
          expect(
            requests.every((u) => u.queryParameters['lang'] == 'zh'),
            isTrue,
          );
          expect(
            requests.every(
              (u) => u.queryParameters['rest_route']!.startsWith('/wp/v2/'),
            ),
            isTrue,
          );
        }
      },
      skip: available ? false : 'QuickJS bridge unavailable',
    );
  }
  test(
    'Yeguo generated JS uses real App AES tools and episode models',
    () async {
      final fixture = jsonDecode(
        File('${root.path}/yeguo-responses.json').readAsStringSync(),
      ) as Map;
      final engine = await LumeJsEngine.create(
        sourceId: 'maker-api-yeguo',
        section: Section.video,
        http: LumeHttp(
          client: MockClient((request) async {
            final args = Uri.splitQueryString(request.body);
            expect(args['token'], '');
            return http.Response(
              fixture[request.url.path] as String? ?? '{}',
              fixture.containsKey(request.url.path) ? 200 : 404,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      addTearDown(engine.dispose);
      final adapter = QuickJsSourceEngine(engine);
      expect(
        await adapter.loadScript(
          SourcePackage.prepare(
            File('${root.path}/yeguo.js').readAsStringSync(),
          ),
        ),
        isTrue,
        reason: '${adapter.loadFailure}',
      );
      final source = JsDataSource(
        id: 'maker-api-yeguo',
        name: 'Fixture',
        section: Section.video,
        runtime: _Runtime(engine),
      );
      final list = await source.list();
      expect(list.items.single.id, '7');
      final chapters = await source.chapters('7');
      expect(chapters.single.id, '91:1');
      final content = await source.content(
        itemId: '7',
        chapterId: chapters.single.id,
      ) as VideoContent;
      expect(content.url.toString(), 'https://cdn.test/granted.m3u8');
    },
    skip: available ? false : 'QuickJS bridge unavailable',
  );
  test(
    'generic HTML5 feed uses real App list, chapters and video content',
    () async {
      final engine = await LumeJsEngine.create(
        sourceId: 'maker-api-inline',
        section: Section.video,
        http: LumeHttp(
          client: MockClient((request) async {
            expect(request.url.toString(), 'https://example.test/');
            return http.Response(
              File('${root.path}/inline.html').readAsStringSync(),
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }),
        ),
      );
      addTearDown(engine.dispose);
      final adapter = QuickJsSourceEngine(engine);
      expect(
        await adapter.loadScript(
          SourcePackage.prepare(
            File('${root.path}/inline.js').readAsStringSync(),
          ),
        ),
        isTrue,
      );
      final source = JsDataSource(
        id: 'maker-api-inline',
        name: 'Fixture',
        section: Section.video,
        runtime: _Runtime(engine),
      );
      final list = await source.list();
      expect(list.items.length, 3);
      expect(list.items.first.cover, 'https://cdn.test/0.jpg');
      final chapters = await source.chapters(list.items.first.id);
      final content = await source.content(
        itemId: list.items.first.id,
        chapterId: chapters.single.id,
      ) as VideoContent;
      expect(content.url.toString(), 'https://cdn.test/0.mp4');
    },
    skip: available ? false : 'QuickJS bridge unavailable',
  );
}

class _Runtime implements JsSourceRuntime {
  _Runtime(this.engine);
  final LumeJsEngine engine;
  @override
  Future<Object?> call(String method, [Object? argument]) =>
      engine.call(method, argument);
  @override
  Future<Set<String>> contractMethods() => engine.contractMethods();
}
