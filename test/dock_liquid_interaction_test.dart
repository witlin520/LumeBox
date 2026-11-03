import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/shell/shell_settings.dart';
import 'package:lume_box/core/theme/frosted_settings.dart';
import 'package:lume_box/core/theme/glass_modules.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/settings/tab_bar_settings_page.dart';
import 'package:lume_box/features/shell/dock_liquid_lens.dart';
import 'package:lume_box/features/shell/dock_liquid_surface.dart';
import 'package:lume_box/features/shell/dock_native_glass.dart';
import 'package:lume_box/features/shell/shell_dock_bar.dart';

void main() {
  const entries = [
    ShellDockEntry(
      id: 'a',
      label: 'A',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    ShellDockEntry(
      id: 'b',
      label: 'B',
      icon: Icons.book_outlined,
      selectedIcon: Icons.book,
    ),
    ShellDockEntry(
      id: 'c',
      label: 'C',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
  ];

  Future<void> scene(
    WidgetTester tester,
    ValueChanged<String> onSelect, {
    bool reduced = false,
    DockAppearance appearance = const DockAppearance(),
  }) async {
    await tester.binding.setSurfaceSize(const Size(440, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(440, 400),
            disableAnimations: reduced,
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.center,
              child: ShellDockBar(
                entries: entries,
                activeId: 'a',
                onSelect: onSelect,
                appearance: appearance,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('按住预览不切页，触摸被系统取消后水滴与胶囊均回原位', (tester) async {
    final selections = <String>[];
    await scene(tester, selections.add);
    final pill = find.byKey(ShellDockBar.selectionPillKey);
    final original = tester.getRect(pill);
    final gesture = await tester.startGesture(tester.getCenter(find.text('C')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      tester.getRect(pill).center.dx,
      greaterThan(original.center.dx + 100),
    );
    expect(selections, isEmpty, reason: '按下仅预览，不能提前打开其他页面');
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(selections, isEmpty, reason: '系统取消手势不能触发切页');
    expect(tester.getRect(pill).left, closeTo(original.left, .01));
    expect(tester.getRect(pill).height, closeTo(original.height, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动态效果时不膨胀，仍能点击切换一次', (tester) async {
    final selections = <String>[];
    await scene(tester, selections.add, reduced: true);
    final pill = find.byKey(ShellDockBar.selectionPillKey);
    final before = tester.getRect(pill);
    final gesture = await tester.startGesture(before.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getRect(pill), before);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selections, ['a']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('按压中隐藏再返回底栏，水滴恢复原位且不残留按压折射', (tester) async {
    var visible = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              body: Center(
                child: ShellDockBar(
                  entries: entries,
                  activeId: 'a',
                  onSelect: (_) {},
                  appearance: const DockAppearance(),
                  visible: visible,
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pill = find.byKey(ShellDockBar.selectionPillKey);
    final original = tester.getRect(pill);
    final gesture = await tester.startGesture(tester.getCenter(find.text('C')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.getRect(pill).height, greaterThan(original.height));
    update(() => visible = false);
    await tester.pumpAndSettle();
    update(() => visible = true);
    await tester.pumpAndSettle();
    expect(tester.getRect(pill), original);
    expect(find.byKey(const Key('shell.dock.lens.filter')), findsNothing);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('按压提亮遵循全白端点，全透端点按压后会先被提亮', (tester) async {
    final modules = FrostedSettings.instance;
    final original = modules.style(GlassModule.all, GlassPart.dock);
    addTearDown(
      () => modules.setStyle(
        GlassModule.all,
        GlassPart.dock,
        original,
        persist: false,
      ),
    );
    for (final opacity in [.08, 1.0]) {
      await modules.setStyle(
        GlassModule.all,
        GlassPart.dock,
        original.withValue(GlassParameter.opacity, opacity),
        persist: false,
      );
      await scene(tester, (_) {});
      Color fill() {
        final surface = tester.widget<DockLiquidSurface>(
          find.byType(DockLiquidSurface),
        );
        if (DockLiquidSurface.shaderSupported) {
          return surface.tintColor.withValues(alpha: surface.tintOpacity);
        }
        final filter = tester.widget<BackdropFilter>(
          find.byKey(ShellDockBar.capsuleFilterKey),
        );
        return ((filter.child! as DecoratedBox).decoration as BoxDecoration)
            .color!;
      }

      final idleAlpha = fill().a;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ShellDockBar.selectionPillKey)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final heldAlpha = fill().a;
      if (opacity == 1) {
        // 全白端点按压后仍是全白。
        expect(heldAlpha, 1);
      } else {
        // 参考录屏：按压会提亮；全透端点不再保持 0，但不会超过提亮上限。
        expect(heldAlpha, greaterThan(idleAlpha));
        expect(heldAlpha, lessThanOrEqualTo(.4));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }
  });
  testWidgets('减少动态效果时收腰裁剪与透镜采样都不启动', (tester) async {
    final waisted = const DockLiquidSettings().withValue(
      DockLiquidParameter.waist,
      1,
    );
    await scene(
      tester,
      (_) {},
      reduced: true,
      appearance: DockAppearance(liquid: waisted),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(ShellDockBar.selectionPillKey)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final surface = tester.widget<DockLiquidSurface>(
      find.byType(DockLiquidSurface),
    );
    expect(surface.clipPath, isNull);
    expect(find.byKey(DockLiquidLens.filterKey), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('局部收腰与水滴膨胀同步，关闭后恢复规则底座', (tester) async {
    Path? waistPath() => tester
        .widget<DockLiquidSurface>(find.byType(DockLiquidSurface))
        .clipPath;
    await scene(tester, (_) {});
    expect(waistPath(), isNull, reason: '静止时底座保持规则轮廓');
    final pill = find.byKey(ShellDockBar.selectionPillKey);
    final idleHeight = tester.getSize(pill).height;
    var gesture = await tester.startGesture(
      tester.getCenter(find.byKey(ShellDockBar.selectionPillKey)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(waistPath(), isNotNull, reason: '按下局部内收');
    expect(tester.getSize(pill).height, greaterThan(idleHeight));
    await gesture.up();
    await tester.pumpAndSettle();

    final waisted = const DockLiquidSettings().withValue(
      DockLiquidParameter.waist,
      0,
    );
    await scene(tester, (_) {}, appearance: DockAppearance(liquid: waisted));
    expect(waistPath(), isNull, reason: '未按压时保持规则胶囊');
    gesture = await tester.startGesture(
      tester.getCenter(find.byKey(ShellDockBar.selectionPillKey)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(waistPath(), isNull, reason: '强度为零时关闭局部内收');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('玻璃渲染方式默认 Flutter 自绘，旧配置迁移与序列化安全', () {
    expect(const DockLiquidSettings().glassRenderer, DockGlassRenderer.flutter);
    final native = const DockLiquidSettings().withGlassRenderer(
      DockGlassRenderer.nativeIos,
    );
    final restored = DockLiquidSettings.fromJson(native.toJson());
    expect(restored.glassRenderer, DockGlassRenderer.nativeIos);
    expect(restored, native);
    expect(
      DockLiquidSettings.fromJson({'glassRenderer': 'unknown'}).glassRenderer,
      DockGlassRenderer.flutter,
    );
    expect(
      const DockLiquidSettings().nativeGlassStyle,
      DockNativeGlassStyle.regular,
    );
    final styled = native
        .withNativeGlassStyle(DockNativeGlassStyle.thin)
        .withValue(DockLiquidParameter.nativeTint, .2);
    expect(DockLiquidSettings.fromJson(styled.toJson()), styled);
    expect(
      DockLiquidSettings.fromJson({'nativeGlassStyle': 'unknown'})
          .nativeGlassStyle,
      DockNativeGlassStyle.regular,
    );
    expect(styled.value(DockLiquidParameter.nativeTint), closeTo(.2, .001));
    final reduced = native.withReduceTransparency(true);
    expect(DockLiquidSettings.fromJson(reduced.toJson()), reduced);
    expect(reduced.reduceTransparency, isTrue);
  });

  testWidgets('减少透明效果时关闭清澈区并提高底座白度', (tester) async {
    await scene(
      tester,
      (_) {},
      appearance: DockAppearance(
        liquid: const DockLiquidSettings().withReduceTransparency(true),
      ),
    );
    final surface = tester.widget<DockLiquidSurface>(
      find.byType(DockLiquidSurface),
    );
    expect(surface.clarity, 0);
    expect(surface.tintOpacity, greaterThanOrEqualTo(.85));
    expect(tester.takeException(), isNull);
  });

  testWidgets('非 iOS 设备选择原生材质时自动回退 Flutter 自绘', (tester) async {
    final native = const DockLiquidSettings().withGlassRenderer(
      DockGlassRenderer.nativeIos,
    );
    await scene(tester, (_) {}, appearance: DockAppearance(liquid: native));
    expect(find.byType(DockLiquidSurface), findsOneWidget);
    expect(find.byType(DockNativeGlass), findsNothing);
    expect(find.byType(UiKitView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧页面兼容入口仅展示系统材质，不恢复已删除的自绘预设', (tester) async {
    final controller = ShellSettingsController.instance;
    final original = controller.appearance;
    addTearDown(() => controller.setAppearance(original));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: LumeTheme.build(), home: const TabBarSettingsPage()),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('dock-liquid-preset-softFree')),
      findsNothing,
    );
    expect(find.text('系统材质'), findsOneWidget);
    expect(controller.appearance, original);
  });

  testWidgets('按压时整条底栏与图标文字一起放大', (tester) async {
    await scene(tester, (_) {});
    final aBefore = tester.getCenter(find.text('A'));
    final cBefore = tester.getCenter(find.text('C'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(ShellDockBar.selectionPillKey)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // getRect 返回局部尺寸，不叠祖先 Transform；用两个页签中心的实际距离
    // 判断整条底栏（含图标文字）是否按参考比例放大。
    final aAfter = tester.getCenter(find.text('A'));
    final cAfter = tester.getCenter(find.text('C'));
    final beforeGap = (cBefore - aBefore).distance;
    final afterGap = (cAfter - aAfter).distance;
    expect(afterGap, closeTo(beforeGap * 1.034, 4));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('三套液态预设只改液态参数，且差异可区分', () {
    const appearance = DockAppearance();
    final recommended = DockLiquidPreset.recommended.build();
    final clear = DockLiquidPreset.clearRules.build();
    final soft = DockLiquidPreset.softFree.build();
    expect(recommended, const DockLiquidSettings());
    expect(clear.shape, DockLensShape.capsule);
    expect(clear.freeDeform, isFalse);
    expect(clear.value(DockLiquidParameter.blurReduction), 1);
    expect(soft.shape, DockLensShape.roundedRect);
    expect(soft.freeDeform, isTrue);
    expect(soft.value(DockLiquidParameter.shapeRoundness), .7);
    for (final liquid in [recommended, clear, soft]) {
      final next = appearance.copyWith(liquid: liquid);
      // 预设不碰尺寸 / 动效时长 / 排序等外观字段。
      expect(next.height, appearance.height);
      expect(next.animationMs, appearance.animationMs);
      expect(next.horizontalMargin, appearance.horizontalMargin);
      // 预设可被序列化后在重启时原样恢复。
      expect(DockAppearance.fromJson(next.toJson()).liquid, liquid);
    }
  });

  test('旧外观配置自动补齐液态参数，越界和坏值恢复有效范围', () {
    final legacy = DockAppearance.fromJson({'height': 68, 'animationMs': 1010});
    expect(legacy.height, 68);
    expect(legacy.liquid, const DockLiquidSettings());
    final configured = legacy.copyWith(
      liquid: legacy.liquid
          .withValue(DockLiquidParameter.pressMs, 300)
          .withEnabled(DockLiquidEffect.clarity, false),
    );
    expect(DockAppearance.fromJson(configured.toJson()), configured);
    final shaped = legacy.copyWith(
      liquid: legacy.liquid
          .withShape(DockLensShape.roundedRect)
          .withFreeDeform(false)
          .withValue(DockLiquidParameter.shapeRoundness, .4),
    );
    expect(DockAppearance.fromJson(shaped.toJson()), shaped);
    expect(shaped.liquid.shape, DockLensShape.roundedRect);
    expect(shaped.liquid.freeDeform, isFalse);
    expect(
      DockLiquidSettings.fromJson({'shape': 'unknown'}).shape,
      DockLensShape.capsule,
    );
    final broken = DockLiquidSettings.fromJson({
      'values': {'lift': 99, 'spread': double.nan},
      'disabled': ['clarity', 'unknown'],
    });
    expect(
      broken.value(DockLiquidParameter.lift),
      DockLiquidParameter.lift.max,
    );
    expect(
      broken.value(DockLiquidParameter.spread),
      DockLiquidParameter.spread.initial,
    );
    expect(broken.enabled(DockLiquidEffect.clarity), isFalse);
    // 新增材质参数对旧配置自动补默认值（不无提示覆盖原有设置）。
    for (final parameter in <DockLiquidParameter>[
      DockLiquidParameter.lensGlow,
      DockLiquidParameter.lensDesaturate,
      DockLiquidParameter.clarityFeather,
      DockLiquidParameter.coreAlpha,
      DockLiquidParameter.backgroundAdapt,
    ]) {
      expect(broken.value(parameter), parameter.initial);
    }
  });

  testWidgets('圆形基础形状保持正圆，自由形变关闭时拖动不拉伸', (tester) async {
    final circle = const DockLiquidSettings().withShape(DockLensShape.circle);
    await scene(tester, (_) {}, appearance: DockAppearance(liquid: circle));
    final pill = find.byKey(ShellDockBar.selectionPillKey);
    final circleRect = tester.getRect(pill);
    expect(circleRect.width, closeTo(circleRect.height, 1.0));

    final rigid = const DockLiquidSettings()
        .withShape(DockLensShape.capsule)
        .withFreeDeform(false);
    await scene(tester, (_) {}, appearance: DockAppearance(liquid: rigid));
    final before = tester.getRect(pill);
    final gesture = await tester.startGesture(before.center);
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveBy(const Offset(90, 0));
    await tester.pump(const Duration(milliseconds: 60));
    // 自由形变关闭时不能有速度驱动的拉伸量。
    final lens = tester.widget<DockLiquidLens>(find.byType(DockLiquidLens));
    expect(lens.stretch, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('液态滑杆全部拉满仍可按住拖动，不产生非法透明度或布局错误', (tester) async {
    var liquid = const DockLiquidSettings();
    for (final p in DockLiquidParameter.values) {
      liquid = liquid.withValue(p, p.max);
    }
    await scene(
      tester,
      (_) {},
      appearance: DockAppearance(liquid: liquid, height: 40),
    );
    final gesture = await tester.startGesture(tester.getCenter(find.text('A')));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveBy(const Offset(110, -12));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
