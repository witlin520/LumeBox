import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/app.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/theme/appearance.dart';
import 'package:lume_box/features/shell/app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lume-dock-routes-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    AppearanceController.instance.resetForTesting();
    for (final section in Section.values) {
      await ReadingLibrary.open(section);
    }
  });
  tearDown(() async {
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await SectionScope.closeAll();
    AppearanceController.instance.resetForTesting();
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('二级设置页改主题后逐级返回，导航监听器不更换且隐藏令牌完全释放', (tester) async {
    await tester.pumpWidget(const LumeBoxApp());
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final observer = app.navigatorObservers!.single;
    final dock = tester.widget<AppShell>(find.byType(AppShell)).controller!;
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('一级设置')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('二级设置')),
      ),
    );
    await tester.pumpAndSettle();
    expect(dock.visible, isFalse);
    AppearanceController.instance.apply(
      const AppearanceSettings(mode: ThemeMode.dark, accent: ThemeAccent.mint),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .navigatorObservers!
          .single,
      same(observer),
    );
    navigator.pop();
    await tester.pumpAndSettle();
    expect(dock.visible, isFalse, reason: '仍在一级设置时继续隐藏');
    navigator.pop();
    await tester.pumpAndSettle();
    expect(dock.visible, isTrue, reason: '返回首页必须释放所有路由隐藏令牌');

    final playing = Object();
    dock.hide(playing);
    navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(dock.visible, isFalse, reason: '恢复路由不能清掉仍在播放的独立令牌');
    dock.show(playing);
    await tester.pumpAndSettle();
    expect(dock.visible, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
