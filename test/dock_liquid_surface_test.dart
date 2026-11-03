import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/shell/shell_settings.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/shell/dock_liquid_lens.dart';
import 'package:lume_box/features/shell/dock_liquid_surface.dart';
import 'package:lume_box/features/shell/shell_dock_bar.dart';

const Key _captureKey = Key('surface.capture');

class _StripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF14B8A6)],
        ).createShader(rect),
    );
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 3, size.height),
        Paint()..color = Colors.white.withValues(alpha: .92),
      );
      canvas.drawRect(
        Rect.fromLTWH(x + 3, 0, 3, size.height),
        Paint()..color = const Color(0xFF10131A).withValues(alpha: .85),
      );
    }
  }

  @override
  bool shouldRepaint(_StripesPainter oldDelegate) => false;
}

class _DockScene extends StatelessWidget {
  const _DockScene({
    this.appearance = const DockAppearance(),
    this.white = false,
  });
  final DockAppearance appearance;
  final bool white;

  static const List<ShellDockEntry> entries = [
    ShellDockEntry(
      id: 'comic',
      label: '漫画',
      icon: Icons.auto_stories_outlined,
      selectedIcon: Icons.auto_stories_rounded,
    ),
    ShellDockEntry(
      id: 'video',
      label: '视频',
      icon: Icons.play_circle_outline_rounded,
      selectedIcon: Icons.play_circle_fill_rounded,
    ),
    ShellDockEntry(
      id: 'cat',
      label: '猫源',
      icon: Icons.pets_outlined,
      selectedIcon: Icons.pets_rounded,
    ),
    ShellDockEntry(
      id: 'settings',
      label: '设置',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: LumeTheme.build(),
    home: RepaintBoundary(
      key: _captureKey,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: white
                  ? const ColoredBox(color: Colors.white)
                  : CustomPaint(painter: _StripesPainter()),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: ShellDockBar(
                entries: entries,
                activeId: 'comic',
                onSelect: _noop,
                appearance: appearance,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  static void _noop(String _) {}
}

Future<Uint8List> _pixels(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(find.byKey(_captureKey))
          .toImage(pixelRatio: 1);
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      image.dispose();
      return bytes;
    }))!;

double _edgeEnergy(Uint8List data, int width, Rect area) {
  int index(int x, int y) => (y * width + x) * 4;
  double luminance(int x, int y) {
    final i = index(x, y);
    return .299 * data[i] + .587 * data[i + 1] + .114 * data[i + 2];
  }

  var total = 0.0;
  var count = 0;
  for (var y = area.top.toInt(); y < area.bottom.toInt(); y++) {
    for (var x = area.left.toInt(); x < area.right.toInt() - 1; x++) {
      total += (luminance(x, y) - luminance(x + 1, y)).abs();
      count++;
    }
  }
  return count == 0 ? 0 : total / count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('玻璃背景提亮至最大仍保留选中图标文字的饱和原色', (tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final glow in [0.0, 1.0]) {
      await tester.pumpWidget(
        _DockScene(
          white: true,
          appearance: DockAppearance(
            liquid: const DockLiquidSettings().withValue(
              DockLiquidParameter.lensGlow,
              glow,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('视频')),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      final region = tester
          .getRect(find.byKey(ShellDockBar.selectionPillKey))
          .deflate(8);
      final pixels = await _pixels(tester);
      final target = LumeTheme.accent;
      var matching = 0;
      for (var y = region.top.ceil(); y < region.bottom.floor(); y++) {
        for (var x = region.left.ceil(); x < region.right.floor(); x++) {
          final at = (y * 440 + x) * 4;
          if ((pixels[at] - target.r * 255).abs() < 10 &&
              (pixels[at + 1] - target.g * 255).abs() < 10 &&
              (pixels[at + 2] - target.b * 255).abs() < 10) {
            matching++;
          }
        }
      }
      expect(matching, greaterThan(20), reason: '背景提亮 $glow 时前景不能被白色洗淡');
      await gesture.up();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('回退路径保留底座磨砂与胶囊滤镜入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const _DockScene());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    final filter = tester.widget<BackdropFilter>(
      find.byKey(ShellDockBar.capsuleFilterKey),
    );
    if (DockLiquidSurface.shaderSupported) {
      expect(filter.filterConfig, isA<DockLiquidSurfaceFilter>());
    } else {
      expect(filter.filter, isNotNull);
    }
    expect(find.byType(DockLiquidSurface), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('按压时透镜区域保留清晰背景，底座其余部分仍然磨砂', (tester) async {
    // 该断言依赖 ImageFilter.shader（Impeller）；Skia 下由回退路径测试覆盖。
    if (!DockLiquidSurface.shaderSupported) return;
    await tester.binding.setSurfaceSize(const Size(440, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _DockScene());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('视频')),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      final filters = tester
          .widgetList<BackdropFilter>(find.byKey(ShellDockBar.capsuleFilterKey))
          .where((filter) => filter.filterConfig is DockLiquidSurfaceFilter);
      if (filters.isNotEmpty && i > 8) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }

    final lens = tester.getRect(find.byType(DockLiquidLens));
    final capsule = tester.getRect(find.byKey(ShellDockBar.capsuleSurfaceKey));
    final image = await _pixels(tester);
    const width = 440;
    final inside = Rect.fromLTWH(lens.center.dx - 24, lens.top + 6, 48, 8);
    final outside = Rect.fromLTWH(capsule.left + 30, lens.top + 6, 60, 8);
    final insideEnergy = _edgeEnergy(image, width, inside);
    final outsideEnergy = _edgeEnergy(image, width, outside);
    expect(
      insideEnergy,
      greaterThan(outsideEnergy * 3),
      reason: '透镜内应保留清晰背景（当前 $insideEnergy，外部磨砂 $outsideEnergy）',
    );
    expect(outsideEnergy, lessThan(12));

    await gesture.up();
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(tester.takeException(), isNull);
  });
}
