import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/app.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/features/shell/app_shell.dart';

/// 应用入口的验证：启动直接进入三页签导航壳（不再有卡片仪表盘首页）、
/// 页签文案与顺序、板块页平台边界，以及设置里的图源总管理入口。
void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const LumeBoxApp());
    await tester.pumpAndSettle();
  }

  /// 当前平台的排布：桌面端是左侧栏，移动端是底部 Dock。
  Finder navItemFinder() =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux
      ? find.byKey(AppShell.railKey)
      : find.byKey(AppShell.dockKey);

  Finder navItem(String label) =>
      find.descendant(of: navItemFinder(), matching: find.text(label));

  testWidgets('启动即导航壳：三个页签，文案为 漫画 / 视频 / 设置', (tester) async {
    await pumpApp(tester);

    for (final label in <String>[
      Section.comic.label,
      Section.video.label,
      '设置',
    ]) {
      expect(navItem(label), findsOneWidget, reason: '导航缺少页签：$label');
    }

    // 旧的卡片仪表盘首页已移除：它当时把项目名放在每个卡片里。
    expect(find.text('自定义视频'), findsNothing);
    expect(find.widgetWithText(AppBar, '设置'), findsNothing);
  });

  testWidgets('板块页标题显示对应板块名称', (tester) async {
    await pumpApp(tester);

    for (final section in [Section.comic, Section.video]) {
      await tester.tap(navItem(section.label));
      for (var n = 0; n < 8; n++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();

      // 猫源通过视频页源选择器进入，不再有独立导航项。
      final expectedTitle = section.label;
      expect(find.text(expectedTitle), findsWidgets);
      expect(
        tester.getCenter(find.text(expectedTitle).last).dy,
        lessThan(160),
        reason: '板块名称应显示在顶部',
      );
    }
  });

  testWidgets('非 iOS 平台进入板块只显示空页面骨架，没有添加图源入口', (tester) async {
    await pumpApp(tester);

    await tester.tap(navItem(Section.video.label));
    await tester.pumpAndSettle();

    expect(find.text('当前平台在 Phase1 仅保留页面骨架'), findsOneWidget);
    expect(find.byTooltip('添加源'), findsNothing);
  }, skip: Platform.isIOS);
}
