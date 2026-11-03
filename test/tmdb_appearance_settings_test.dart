import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/core/tmdb/tmdb.dart';
import 'package:lume_box/features/settings/tmdb_settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('tmdb-ui');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    final settings = TmdbSettings.instance;
    await settings.boot();
    await settings.disconnect();
    settings.posterStyle = TmdbPosterStyle.fixed;
  });
  tearDown(() async {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  testWidgets('紧凑外观面板支持宽范围调节、持久化和一键恢复', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: LumeTheme.build(), home: const TmdbSettingsPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('详情页外观调节'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNWidgets(5));
    final sliderFinder = find.byKey(
      const ValueKey('tmdb-appearance-backgroundBrightness'),
    );
    final slider = tester.widget<Slider>(sliderFinder);
    expect(slider.min, .3);
    expect(slider.max, 2.5);
    await tester.drag(sliderFinder, const Offset(45, 0));
    await tester.pumpAndSettle();
    final settings = TmdbSettings.instance;
    expect(settings.detailAppearance.value.backgroundBrightness, isNot(1));
    var done = false;
    settings.flush().then((_) => done = true);
    for (var i = 0; i < 60 && !done; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(done, isTrue);
    final restored = TmdbSettings();
    await tester.runAsync(restored.boot);
    expect(
      restored.detailAppearance.value.backgroundBrightness,
      settings.detailAppearance.value.backgroundBrightness,
    );
    await tester.ensureVisible(find.byKey(const Key('tmdb-appearance-reset')));
    await tester.tap(find.byKey(const Key('tmdb-appearance-reset')));
    await tester.pumpAndSettle();
    expect(
      settings.detailAppearance.value.toJson(),
      const TmdbDetailAppearance().toJson(),
    );
    done = false;
    settings.flush().then((_) => done = true);
    for (var i = 0; i < 60 && !done; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(done, isTrue);
    expect(tester.takeException(), isNull);
  });
}
