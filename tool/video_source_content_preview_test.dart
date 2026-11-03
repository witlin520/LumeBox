// Real-widget snapshots for the JS source content categories.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/cat/cat_service.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/privacy_settings.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/source/source_preferences.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/source/video_source_picker.dart';

import '../test/support/fake_source_manager.dart';

class _PreviewService extends CatService {
  // Development snapshot uses the same isolated service as widget tests.
  // ignore: invalid_use_of_visible_for_testing_member
  _PreviewService() : super.testing();
  @override
  Future<void> boot() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final cjk = File(r'C:\Windows\Fonts\Deng.ttf');
    if (cjk.existsSync()) {
      for (final family in ['Roboto', 'Ahem', 'CJK']) {
        final loader = FontLoader(family)
          ..addFont(
            cjk.readAsBytes().then((bytes) => bytes.buffer.asByteData()),
          );
        await loader.load();
      }
    }
    final icons = File(
      r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            icons.readAsBytes().then((bytes) => bytes.buffer.asByteData()),
          ))
          .load();
    }
  });
  testWidgets('capture production JS picker content tabs', (tester) async {
    final root = Directory.systemTemp.createTempSync('source-content-preview-');
    final service = _PreviewService();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    await tester.runAsync(() async {
      await ReadingLibrary.open(Section.video);
      await ReadingLibrary.open(Section.cat);
      await PrivacySettings.instance.setShowAdult(true);
      await const SourcePreferences(pinned: true).save(Section.video, '360');
    });
    final manager = FakeSourceManager(
      sources: const [
        SourceDescriptor(
          id: '360',
          name: '360资源站',
          version: '1.0.1',
          enabled: true,
          contentCategory: 'movie',
        ),
        SourceDescriptor(
          id: 'cinema-a',
          name: '影视示例 A',
          version: '1',
          enabled: true,
          contentCategory: 'movie',
        ),
        SourceDescriptor(
          id: 'cinema-b',
          name: '影视示例 B',
          version: '1',
          enabled: true,
          contentCategory: 'movie',
        ),
        SourceDescriptor(
          id: 'cinema-c',
          name: '名称较长的影视示例站点',
          version: '1',
          enabled: true,
          contentCategory: 'movie',
        ),
        SourceDescriptor(
          id: 'cinema-d',
          name: '短剧示例源',
          version: '1',
          enabled: true,
          contentCategory: 'movie',
        ),
        SourceDescriptor(
          id: 'cinema-e',
          name: '动漫示例源',
          version: '1',
          enabled: true,
          contentCategory: 'movie',
        ),
        SourceDescriptor(
          id: 'milk',
          name: '奶香香资源网',
          version: '1.0.1',
          enabled: true,
        ),
        SourceDescriptor(
          id: 'adult-b',
          name: '成人示例 B',
          version: '1',
          enabled: true,
        ),
        SourceDescriptor(
          id: 'adult-c',
          name: '成人示例 C',
          version: '1',
          enabled: true,
        ),
        SourceDescriptor(
          id: 'adult-d',
          name: '成人示例 D',
          version: '1',
          enabled: true,
        ),
        SourceDescriptor(
          id: 'new-a',
          name: '新导入源 A',
          version: '1',
          enabled: true,
        ),
        SourceDescriptor(
          id: 'new-b',
          name: '新导入源 B',
          version: '1',
          enabled: true,
        ),
      ],
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final output = Directory('build/ui_snapshot')..createSync(recursive: true);
    try {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        manager.selected = brightness == Brightness.light ? '360' : 'milk';
        final base = LumeTheme.build(brightness: brightness, fontFamily: 'CJK');
        final theme = base.copyWith(
          chipTheme: base.chipTheme.copyWith(
            labelStyle: base.chipTheme.labelStyle?.copyWith(fontFamily: 'CJK'),
            secondaryLabelStyle: base.chipTheme.secondaryLabelStyle?.copyWith(
              fontFamily: 'CJK',
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'CJK'),
            ),
            home: RepaintBoundary(
              key: const ValueKey('preview-capture'),
              child: Scaffold(
                backgroundColor: LumeTheme.base,
                body: SafeArea(
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Text(
                            '视频',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              color: LumeTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: VideoSourcePicker(
                          key: ValueKey(brightness),
                          manager: manager,
                          service: service,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        final desired = brightness == Brightness.light ? 'movie' : 'adult';
        for (final category in [
          desired == 'movie' ? 'adult' : 'movie',
          desired,
        ]) {
          await tester.tap(
            find.byKey(ValueKey('video-source-content-$category')),
          );
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        // Standalone DefaultTextStyle instances use the tester's square font.
        // Replace only that fallback for legible Chinese in this preview.
        InlineSpan fonts(InlineSpan span) => span is TextSpan
            ? TextSpan(
                text: span.text,
                style: span.style?.fontFamily == 'MaterialIcons'
                    ? span.style
                    : (span.style ?? const TextStyle()).copyWith(
                        fontFamily: 'CJK',
                      ),
                children: span.children?.map(fonts).toList(),
              )
            : span;
        for (final element in find.byType(RichText).evaluate()) {
          final paragraph = element.renderObject;
          if (paragraph is RenderParagraph) {
            paragraph.text = fonts(paragraph.text);
          }
        }
        await tester.pump();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('preview-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${output.path}/video-source-content-$desired-${brightness.name}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }
    } finally {
      await tester.pumpWidget(const SizedBox());
      service.dispose();
      tester.view.reset();
      await tester.runAsync(() async {
        await PrivacySettings.instance.setShowAdult(false);
        ReadingLibrary.disposeAll();
        ReadingStore.disposeAll();
        await SectionScope.closeAll();
        root.deleteSync(recursive: true);
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
    }
  });
}
