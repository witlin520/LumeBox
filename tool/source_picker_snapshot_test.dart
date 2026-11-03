/// 源选择抽屉布局预览快照（开发期用，不参与常规测试）。
///
/// 运行：`flutter test tool/source_picker_snapshot_test.dart`
/// 产物：`build/ui_snapshot/source_picker_light.png` / `_dark.png`
///
/// 用真字体渲染生产 [SourcePickerSheet]，覆盖长标题、1.0.0 版本号、18 角标、
/// 置顶与选中态，专门用于人眼检查 51 固定行高与 12px 边距。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/privacy_settings.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/source/source_picker_groups.dart';
import 'package:lume_box/core/source/source_preferences.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/source/source_picker_sheet.dart';

import '../test/support/fake_source_manager.dart';

const String _fontRoot = r'C:\flutter\bin\cache\artifacts\material_fonts';
const String _cjkFont = r'C:\Windows\Fonts\Deng.ttf';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final path = '$_fontRoot\\$file';
      if (!File(path).existsSync()) continue;
      loader.addFont(
        File(path).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
      );
    }
    await loader.load();
  }

  await load('Roboto', <String>[
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]);
  await load('MaterialIcons', <String>['materialicons-regular.otf']);
  final cjk = FontLoader('CJK');
  if (File(_cjkFont).existsSync()) {
    cjk.addFont(
      File(_cjkFont).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
    );
  }
  await cjk.load();
}

ThemeData _snapshotTheme(Brightness brightness) {
  final base = LumeTheme.build(brightness: brightness);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'CJK'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'CJK'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  final output = Directory('build/ui_snapshot');

  setUpAll(() async {
    await _loadFonts();
    output.createSync(recursive: true);
  });

  setUp(() async {
    root = Directory.systemTemp.createTempSync('lume_box_picker_preview');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? root.path
              : null,
        );
    await ReadingLibrary.open(Section.comic);
    await PrivacySettings.instance.setShowAdult(true);
    await SourcePreferences(pinned: true)
        .save(Section.comic, 'preview-comic-1');
  });

  tearDown(() async {
    await PrivacySettings.instance.setShowAdult(false);
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await SectionScope.closeAll();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  List<SourceDescriptor> sources() {
    final groups = SourcePickerGroups.forSection(Section.comic);
    return [
      for (final group in groups) ...[
        if (group.$1 == 'comic')
          const SourceDescriptor(
            id: 'preview-adult',
            name: '成人内容示例源',
            version: '1.0.0',
            enabled: true,
          ),
        for (var i = 0; i < 6; i++)
          SourceDescriptor(
            id: 'preview-${group.$1}-$i',
            name: i.isEven
                ? '${group.$2}示例源 ${i + 1}'
                : '一个比较长的${group.$2}站点名称 ${i + 1}',
            version: '1.0.0',
            enabled: true,
            group: group.$2,
          ),
      ],
    ];
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final renderView = tester.binding.renderViews.first;
      final layer = renderView.debugLayer! as OffsetLayer;
      final image = await layer.toImage(renderView.paintBounds, pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${output.path}/$name.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('源选择抽屉两列 · ${brightness.name}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(414, 896));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final entries = sources();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _snapshotTheme(brightness),
          home: Scaffold(
            backgroundColor: LumeTheme.base,
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SourcePickerSheet(
                section: Section.comic,
                sources: entries,
                currentId: 'preview-comic-1',
                manager: FakeSourceManager(sources: entries),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(find.byType(SourcePickerSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'source_picker_${brightness.name}');
    });
  }
}
