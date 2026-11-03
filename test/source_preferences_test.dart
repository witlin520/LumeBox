import 'package:lume_box/features/source/source_picker_sheet.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume_box/core/net/lume_http.dart';
import 'package:lume_box/core/net/network_settings.dart';
import 'package:lume_box/core/net/web_session_lifecycle.dart';
import 'package:lume_box/core/reading/reading_library.dart';
import 'package:lume_box/core/reading/reading_store.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source_preferences.dart';
import 'package:lume_box/core/cache/section_memory_cache.dart';
import 'package:lume_box/shared/widgets/missing_cover.dart';
import 'package:lume_box/core/source/data_source.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/source/source_section_page.dart';

import 'support/fake_source_manager.dart';

void main() {
  testWidgets(
    'narrow source manager searches by group and keeps a pinned source first after reopening',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'lume-source-manager-prefs',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => root.path,
          );
      addTearDown(() async {
        ReadingLibrary.disposeAll();
        ReadingStore.disposeAll();
        await SectionScope.closeAll();
        root.deleteSync(recursive: true);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
      });
      await tester.runAsync(() => ReadingLibrary.open(Section.video));
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final manager = FakeSourceManager(
        sources: const [
          SourceDescriptor(
            id: 'a',
            name: '甲源',
            version: '1',
            enabled: true,
            group: '阅读',
          ),
          SourceDescriptor(
            id: 'b',
            name: '乙源',
            version: '1',
            enabled: true,
            group: '收藏',
          ),
        ],
      );
      Future<void> showPage() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: LumeTheme.build(),
            home: SourceSectionPage(section: Section.video, manager: manager),
          ),
        );
        await tester.pumpAndSettle();
      }

      await showPage();
      await tester.enterText(find.byType(TextField), '收藏');
      await tester.pumpAndSettle();
      expect(find.text('甲源'), findsNothing);
      expect(find.text('乙源'), findsOneWidget);
      showSourcePicker(
        context: tester.element(find.byType(SourceSectionPage)),
        section: Section.video,
        sources: manager.sources,
        currentId: null,
        manager: manager,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-more-b')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('置顶此源'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(SourcePreferences.read(Section.video, 'b').pinned, isTrue);
      await tester.pumpWidget(const SizedBox());
      await showPage();
      expect(
        tester.getTopLeft(find.text('乙源')).dy,
        lessThan(tester.getTopLeft(find.text('甲源')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('custom domain only rewrites the exact origin, preserving encoded paths and queries', () {
    const p = SourcePreferences(
      originalOrigin: 'https://old.example',
      customOrigin: 'https://new.example:8443',
    );
    expect(
      p.rewrite('https://old.example/a%20b?q=1#page'),
      'https://new.example:8443/a%20b?q=1#page',
    );
    for (final u in [
      'https://cdn.example/a.jpg',
      'https://old.example.evil/a',
      'https://old.example:9443/a',
      'data:image/png,x',
      'relative/path',
    ]) {
      expect(p.rewrite(u), u);
    }
    expect(
      SourcePreferences.validOrigin('https://user:pass@example.com'),
      isFalse,
    );
    expect(SourcePreferences.validOrigin('https://example.com/path'), isFalse);
  });
  test('origin change strips old credentials and rewrites only the matching referer', () async {
    http.Request? sent;
    const p = SourcePreferences(
      originalOrigin: 'https://old.example',
      customOrigin: 'https://new.example',
    );
    final h = LumeHttp(
      client: MockClient((r) async {
        sent = r;
        return http.Response('ok', 200);
      }),
      profile: const NetworkProfile(cookie: 'session=old'),
      rewriteUrl: p.rewrite,
    );
    await h.send(
      url: 'https://old.example/api',
      headers: {
        'Authorization': 'Bearer old',
        'Referer': 'https://old.example/item',
      },
    );
    expect(sent!.url.toString(), 'https://new.example/api');
    expect(sent!.headers.containsKey('cookie'), isFalse);
    expect(sent!.headers.containsKey('authorization'), isFalse);
    expect(sent!.headers['referer'], 'https://new.example/item');
    h.dispose();
  });
  test('cache removal distinguishes source IDs containing separators', () {
    final c = SectionMemoryCache.instance;
    c.clearAll();
    c.write(Section.cat, 'cat', 'list', 1);
    c.write(Section.cat, 'cat|site', 'list', 2);
    c.write(Section.comic, 'cat', 'list', 3);
    expect(c.removeSource(Section.cat, 'cat'), 1);
    expect(c.read(Section.cat, 'cat|site', 'list'), 2);
    expect(c.read(Section.comic, 'cat', 'list'), 3);
    c.clearAll();
  });
  testWidgets(
    'placeholder cover fits both a tiny thumbnail and a tall poster',
    (tester) async {
      for (final size in [const Size(40, 60), const Size(150, 225)]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox.fromSize(
                size: size,
                child: const MissingCover(
                  title: '作品标题示例',
                  section: Section.video,
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(MissingCover), findsOneWidget);
      }
    },
  );
  test(
    'preferences persist independently across sections and source IDs',
    () async {
      final root = Directory.systemTemp.createTempSync('lume-source-prefs');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => root.path,
          );
      try {
        await const SourcePreferences(
          pinned: true,
          newestFirst: true,
          iconUrl: 'https://example.com/icon.png',
        ).save(Section.comic, 'same');
        await const SourcePreferences(pinned: false)
            .save(Section.video, 'same');
        expect(SourcePreferences.read(Section.comic, 'same').pinned, isTrue);
        expect(SourcePreferences.read(Section.video, 'same').pinned, isFalse);
        final before = WebSessionLifecycle.revision('https://old.example');
        await const SourcePreferences(
          originalOrigin: 'https://old.example',
          customOrigin: 'https://new.example',
        ).save(Section.video, 'same');
        expect(
          WebSessionLifecycle.revision('https://old.example'),
          isNot(before),
        );
        final configured = WebSessionLifecycle.revision('https://new.example');
        await SourcePreferences.read(
          Section.video,
          'same',
        ).copyWith(pinned: true).save(Section.video, 'same');
        expect(WebSessionLifecycle.revision('https://new.example'), configured);
        ReadingLibrary.disposeAll();
        ReadingStore.disposeAll();
        await SectionScope.closeAll();
        await ReadingLibrary.open(Section.comic);
        expect(
          SourcePreferences.read(Section.comic, 'same').newestFirst,
          isTrue,
        );
      } finally {
        ReadingLibrary.disposeAll();
        ReadingStore.disposeAll();
        await SectionScope.closeAll();
        root.deleteSync(recursive: true);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
      }
    },
  );
}
