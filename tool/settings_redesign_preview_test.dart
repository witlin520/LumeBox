import 'dart:io';

import 'package:lume_box/features/settings/native_navigation_settings_card.dart';

import 'package:lume_box/features/settings/tab_bar_settings_page.dart';
import 'package:lume_box/features/settings/navigation_settings_page.dart';
import 'package:lume_box/core/shell/shell_settings.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/core/theme/frosted_settings.dart';
import 'package:lume_box/features/settings/settings_page.dart';
import 'package:lume_box/features/settings/display_settings_group.dart';
import 'package:lume_box/features/settings/liquid_glass_settings_page.dart';

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

ThemeData _theme(Brightness brightness) {
  final base = LumeTheme.build(brightness: brightness);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'CJK'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'CJK'),
    listTileTheme: base.listTileTheme.copyWith(
      titleTextStyle: base.listTileTheme.titleTextStyle?.copyWith(
        fontFamily: 'CJK',
      ),
      subtitleTextStyle: base.listTileTheme.subtitleTextStyle?.copyWith(
        fontFamily: 'CJK',
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: (base.chipTheme.labelStyle ?? const TextStyle()).copyWith(
        fontFamily: 'CJK',
      ),
    ),

    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'CJK',
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);
  testWidgets('设置重排真实组件截图', (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'lume-settings-preview',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    await tester.runAsync(
      () => FrostedSettings.instance.boot(directory: directory),
    );
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    tester.view.viewPadding = const FakeViewPadding(top: 118, bottom: 68);
    tester.view.padding = const FakeViewPadding(top: 118, bottom: 68);
    addTearDown(tester.view.reset);
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final view = tester.binding.renderViews.first;
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          view.paintBounds,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        Directory('build/ui_snapshot').createSync(recursive: true);
        File('build/ui_snapshot/$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    final referenceKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 350,
              child: RepaintBoundary(
                key: referenceKey,
                child: DockAppearancePreview(
                  appearance: DockAppearance.defaults,
                  entries: navigationPreviewEntries(),
                  reference: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          referenceKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      Directory('assets/reference').createSync(recursive: true);
      File('assets/reference/dock_default.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        home: const SettingsPage(runtimeAvailable: true),
      ),
    );
    await capture('settings_redesign_home');
    await tester.tap(find.text('个性与界面'));
    await capture('settings_redesign_personal');
    await tester.tap(find.text('页面底色'));
    await capture('settings_redesign_background');
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        home: const LiquidGlassSettingsPage(),
      ),
    );
    await capture('settings_redesign_glass');
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        home: NativeNavigationSettingsPage(
          entries: navigationPreviewEntries(),
          controller: ShellSettingsController.instance,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture('settings_native_navigation');

    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.dark),
        home: const AppearancePalettePage(backgroundOnly: true),
      ),
    );
    await capture('settings_redesign_background_dark');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(() => FrostedSettings.instance.save());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    directory.deleteSync(recursive: true);
  });
}
