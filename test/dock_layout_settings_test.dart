import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/shell/shell_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final controller = ShellSettingsController.instance;
  late Directory directory;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('dock-layout');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    controller.resetForTesting();
    await controller.boot();
  });
  tearDown(() {
    controller.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    directory.deleteSync(recursive: true);
  });
  test('尺寸持久化，窄屏与搜索预留空间内不越界', () async {
    const custom = DockAppearance(
      leftMargin: 70,
      rightMargin: 20,
      preferredWidth: 280,
      horizontalOffset: 95,
      verticalOffset: -65,
      height: 83,
      safeGap: 11,
    );
    expect(DockAppearance.fromJson(custom.toJson()), custom);
    await controller.setAppearance(custom, persist: false);
    await controller.setAppearance(controller.appearance);
    await controller.boot();
    expect(controller.appearance, custom);
    for (final width in [0.0, 120.0, 320.0, 390.0, 844.0]) {
      for (final reserve in [0.0, 48.0]) {
        for (final offset in [-100.0, 0.0, 100.0]) {
          final layout = custom
              .copyWith(horizontalOffset: offset)
              .layoutFor(width, trailingWidth: reserve.clamp(0, width));
          expect(layout.left, greaterThanOrEqualTo(-.001));
          expect(layout.right, greaterThanOrEqualTo(-.001));
          expect(layout.width, greaterThanOrEqualTo(0));
          expect(
            layout.left + layout.width + layout.right,
            closeTo(width, .001),
          );
        }
      }
    }
    expect(custom.bottomFor(34), 110);
    expect(custom.copyWith(verticalOffset: 80, safeGap: -50).bottomFor(34), 0);
    final normal = const DockAppearance(
      leftMargin: 10,
      rightMargin: 30,
      preferredWidth: 200,
    ).layoutFor(390);
    expect(normal.width, 200);
    expect(normal.left, 85);
    expect(normal.right, 105);
  });
}
