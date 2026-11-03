import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/source/source_favicon.dart';
import 'package:lume_box/features/source/source_preferences_page.dart';

import 'package:lume_box/core/source/source_preferences.dart';
import 'package:lume_box/shared/widgets/source_icon.dart';

import 'support/fake_source_manager.dart';

class FixtureIcons extends SourceFavicon {
  bool available = false;
  String? requestedOrigin;
  @override
  Future<Uint8List?> loadBest({
    required String origin,
    List<String> explicit = const [],
    Section? section,
    String? sourceId,
  }) => load(
    origin: origin,
    explicit: explicit,
    section: section,
    sourceId: sourceId,
  );
  @override
  Future<Uint8List?> load({
    required String origin,
    List<String> explicit = const [],
    Section? section,
    String? sourceId,
  }) async {
    requestedOrigin = origin;
    return available
        ? Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)))
        : null;
  }
}

void main() {
  testWidgets('一键获取图标失败保留自定义值，成功后恢复自动图标并提示保存', (tester) async {
    final root = Directory.systemTemp.createTempSync('source-icon-settings-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
    await tester.runAsync(() => ReadingLibrary.open(Section.video));
    addTearDown(() async {
      ReadingLibrary.disposeAll();
      ReadingStore.disposeAll();
      await SectionScope.closeAll();
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      root.deleteSync(recursive: true);
    });
    const source = SourceDescriptor(
      id: 'icons',
      name: '示例站点',
      version: '1',
      enabled: true,
      section: Section.video,
      siteUrl: 'https://fixture.example',
    );
    final icons = FixtureIcons();
    await tester.pumpWidget(
      MaterialApp(
        home: SourcePreferencesPage(
          section: Section.video,
          sourceId: source.id,
          name: source.name,
          siteUrl: source.siteUrl,
          descriptor: source,
          manager: FakeSourceManager(sources: [source]),
          favicon: icons,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('图标与外观'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('图标与外观'));
    await tester.pumpAndSettle();
    final input = find.widgetWithText(TextField, '自定义源图标');
    await tester.ensureVisible(input);
    await tester.enterText(input, 'https://icons.example/custom.png');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final button = find.text('一键获取站点图标');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(input).controller!.text,
      'https://icons.example/custom.png',
    );
    expect(find.textContaining('已保留原设置'), findsOneWidget);
    icons.available = true;
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    expect(find.text('图标已准备好，点右上角「保存」后使用'), findsOneWidget);
    expect(icons.requestedOrigin, 'https://fixture.example');
    await tester.tap(find.text('保存').first);
    await tester.pumpAndSettle();
    final saved = SourcePreferences.read(Section.video, source.id);
    expect(saved.iconUrl, isEmpty);
    expect(base64Decode(saved.iconData), isNotEmpty);
    await tester.pumpWidget(const SizedBox());
    // 模拟重启：丢弃解析缓存，站点地址也与获取时的 origin 不同。
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await tester.runAsync(() => ReadingLibrary.open(Section.video));
    icons.available = false;
    icons.requestedOrigin = null;
    await tester.pumpWidget(
      MaterialApp(
        home: SourceIcon(
          name: source.name,
          siteUrl: '${source.siteUrl}/changed/path',
          section: Section.video,
          sourceId: source.id,
          favicon: icons,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(icons.requestedOrigin, isNull, reason: '已保存的图标无需再次联网获取');
    expect(tester.takeException(), isNull);
  });
}
