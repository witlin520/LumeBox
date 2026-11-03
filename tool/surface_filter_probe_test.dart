/// 调试探针：把生产用 [DockLiquidSurface] / [DockLiquidSurfaceFilter] 放进
/// 受控场景，确认“内层 blur 是否真的生效”。
///
/// 运行：`flutter test --enable-impeller tool/surface_filter_probe_test.dart`
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/features/shell/dock_liquid_surface.dart';

const Key _captureKey = Key('sfp.capture');
const Rect _barRect = Rect.fromLTWH(20, 120, 320, 55);
const Rect _lensLocal = Rect.fromLTWH(100, 4, 96, 47);

class _Stripes extends StatelessWidget {
  const _Stripes();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _StripesPainter(), child: const SizedBox.expand());
}

class _StripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[
            Color(0xFF1E3A8A),
            Color(0xFFFF6B6B),
            Color(0xFF14B8A6),
          ],
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

class _DirectFilter implements ImageFilterConfig {
  _DirectFilter({
    required this.shader,
    required this.clarity,
    required this.origin,
    required this.reversed,
    this.mode = 'compose',
  });

  final ui.FragmentShader shader;
  final double clarity;
  final Offset Function() origin;
  final bool reversed;
  final String mode;

  @override
  ui.ImageFilter? get filter => null;

  @override
  String get debugShortDescription => 'direct';

  @override
  ui.ImageFilter resolve(ImageFilterContext context) {
    final o = origin();
    shader
      ..setFloat(2, o.dx + _lensLocal.left)
      ..setFloat(3, o.dy + _lensLocal.top)
      ..setFloat(4, _lensLocal.width)
      ..setFloat(5, _lensLocal.height)
      ..setFloat(6, 23)
      ..setFloat(7, 14)
      ..setFloat(8, clarity)
      ..setFloat(9, .45)
      ..setFloat(10, .06)
      ..setFloat(11, 1)
      ..setFloat(12, 1)
      ..setFloat(13, 1)
      ..setFloat(14, .5);
    final shaderFilter = ui.ImageFilter.shader(shader);
    if (mode == 'plain') return shaderFilter;
    final blur = ui.ImageFilter.blur(
      sigmaX: 15,
      sigmaY: 15,
      tileMode: TileMode.mirror,
    );
    return reversed
        ? ui.ImageFilter.compose(outer: blur, inner: shaderFilter)
        : ui.ImageFilter.compose(outer: shaderFilter, inner: blur);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('surface filter probe', (tester) async {
    if (!DockLiquidSurface.shaderSupported) {
      // ignore: avoid_print
      print('SFP skipped: shader filters unavailable');
      return;
    }
    await tester.binding.setSurfaceSize(const Size(360, 220));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final program = (await tester.runAsync(
      () => ui.FragmentProgram.fromAsset(DockLiquidSurface.shaderAsset),
    ))!;
    final shader = program.fragmentShader();
    final originKey = GlobalKey(debugLabel: 'bar');
    Offset origin() {
      final box = originKey.currentContext?.findRenderObject();
      return box is RenderBox ? box.localToGlobal(Offset.zero) : Offset.zero;
    }

    Widget scene(String mode, double clarity) {
      final Widget surface;
      switch (mode) {
        case 'widget':
          surface = DockLiquidSurface(
            borderRadius: BorderRadius.circular(27.5),
            blurSigma: 15,
            fallbackSigma: 15,
            fallbackChild: ColoredBox(
              color: Colors.white.withValues(alpha: .45),
            ),
            lensRect: _lensLocal,
            lensRadius: 23,
            lensScale: 1,
            feather: 14,
            clarity: clarity,
            coreAlpha: .06,
            backgroundAdapt: .5,
            tintColor: Colors.white,
            tintOpacity: .45,
            pixelRatio: 1,
            stageOrigin: origin,
          );
        case 'direct':
        case 'direct-reversed':
        case 'plain':
          surface = ClipRRect(
            borderRadius: BorderRadius.circular(27.5),
            child: BackdropFilter(
              filterConfig: _DirectFilter(
                shader: shader,
                clarity: clarity,
                origin: origin,
                reversed: mode == 'direct-reversed',
                mode: mode == 'plain' ? 'plain' : 'compose',
              ),
              child: const SizedBox.expand(),
            ),
          );
        default:
          surface = const SizedBox.expand();
      }
      return ColoredBox(
        color: Colors.black,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(child: _Stripes()),
            if (mode != 'raw')
              Positioned.fromRect(
                rect: _barRect,
                child: KeyedSubtree(key: originKey, child: surface),
              ),
          ],
        ),
      );
    }

    Future<Uint8List> capture(String name) async {
      final png = (await tester.runAsync(() async {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(_captureKey))
            .toImage(pixelRatio: 1);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        image.dispose();
        return bytes;
      }))!;
      final out = Directory('build/surface-filter-probe')
        ..createSync(recursive: true);
      File('${out.path}/$name.png').writeAsBytesSync(png);
      final px = (await tester.runAsync(() async {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(_captureKey))
            .toImage(pixelRatio: 1);
        final bytes = (await image.toByteData())!.buffer.asUint8List();
        image.dispose();
        return bytes;
      }))!;
      return px;
    }

    Future<void> pump(String mode, double clarity) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(key: _captureKey, child: scene(mode, clarity)),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pump();
    }

    double edge(Uint8List data, Rect area) {
      int index(int x, int y) => (y * 360 + x) * 4;
      double l(int x, int y) {
        final i = index(x, y);
        return .299 * data[i] + .587 * data[i + 1] + .114 * data[i + 2];
      }

      var total = 0.0;
      var count = 0;
      for (var y = area.top.toInt(); y < area.bottom.toInt(); y++) {
        for (var x = area.left.toInt(); x < area.right.toInt() - 1; x++) {
          total += (l(x, y) - l(x + 1, y)).abs();
          count++;
        }
      }
      return count == 0 ? 0 : total / count;
    }

    final probes = <String, Uint8List>{};
    for (final mode in [
      'raw',
      'widget',
      'direct',
      'direct-reversed',
      'plain',
    ]) {
      for (final clarity in [0.0, 1.0]) {
        await pump(mode, clarity);
        probes['$mode-$clarity'] = await capture('$mode-$clarity');
      }
    }
    for (final entry in probes.entries) {
      // ignore: avoid_print
      print(
        'SFP ${entry.key} outside=${edge(entry.value, const Rect.fromLTWH(24, 153, 60, 8)).toStringAsFixed(2)} '
        'lens=${edge(entry.value, const Rect.fromLTWH(140, 153, 50, 8)).toStringAsFixed(2)}',
      );
    }
  });
}
