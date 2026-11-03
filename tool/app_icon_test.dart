/// App 图标生成器（开发期工具，不参与常规测试）。
///
/// 为什么要程序化生成：图标要与全局浅色主题同步提亮（去掉过重的深色底），
/// 而位图是二进制资源——手绘或换一张图都看不出「提亮了多少」。把构图写成代码，
/// 配色就成了可审阅、可再改的一行行常量。
///
/// 构图沿用原图标的三层玻璃卡 + 播放键 + 折角：
/// 1. 底：极浅的蓝紫白渐变（浅色主题的底色口径）；
/// 2. 三层圆角卡：蓝→品牌紫的亮色渐变，逐层错位，白色描边；
/// 3. 前景：白色播放三角 + 右下折角（原图标的记号）。
///
/// 运行：`flutter test tool/app_icon_test.dart`
/// 产物：`assets/icon/app_icon_1024.png`（无 Alpha，可交给 flutter_launcher_icons）。
library;

import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double _size = 1024;
const _style = String.fromEnvironment('ICON_STYLE');

// ---------------------------------------------------------------------- 色板

/// 底：极浅（浅色主题的底色方向，不再压深色）。
const Color _bgTop = _style == 'Aurora'
    ? Color(0xFF041D2C)
    : _style == 'Obsidian'
    ? Color(0xFF111019)
    : _style == 'Solar'
    ? Color(0xFF211C16)
    : Color(0xFFF7F6FF);
const Color _bgBottom = _style == 'Aurora'
    ? Color(0xFF12394B)
    : _style == 'Obsidian'
    ? Color(0xFF29243C)
    : _style == 'Solar'
    ? Color(0xFF493627)
    : Color(0xFFE8ECFF);

/// 卡片渐变：亮蓝 → 品牌紫。
const Color _cardBlue = _style == 'Aurora'
    ? Color(0xFF26D5DA)
    : _style == 'Obsidian'
    ? Color(0xFF7B73BB)
    : _style == 'Solar'
    ? Color(0xFFC99647)
    : Color(0xFF6E9BFF);
const Color _cardPurple = _style == 'Aurora'
    ? Color(0xFF4187EB)
    : _style == 'Obsidian'
    ? Color(0xFFB3A0E5)
    : _style == 'Solar'
    ? Color(0xFFF0D29E)
    : Color(0xFF8B5CF6);

/// 前景：白（与卡片的高对比）。
const Color _fore = Color(0xFFFFFFFF);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('生成 1024 图标', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, _size, _size));

    _paintBackground(canvas);
    if (const ['Orbit', 'Prism', 'Spark'].contains(_style)) {
      _paintHighlightIcon(canvas);
    } else {
      _paintCards(canvas);
      _paintGlyph(canvas);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(_size.toInt(), _size.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (_style.isNotEmpty) {
      final template = jsonDecode(
        File('ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final directory = Directory(
        'ios/Runner/Assets.xcassets/$_style.appiconset',
      )..createSync(recursive: true);
      File('${directory.path}/Contents.json')
          .writeAsStringSync(jsonEncode(template));
      for (final entry in template['images'] as List) {
        final size =
            ((double.parse((entry['size'] as String).split('x').first)) *
                    double.parse(
                      (entry['scale'] as String).replaceAll('x', ''),
                    ))
                .round();
        final outputRecorder = ui.PictureRecorder();
        final outputCanvas = Canvas(outputRecorder)..scale(size / _size);
        outputCanvas.drawImage(image, Offset.zero, Paint());
        final outputPicture = outputRecorder.endRecording();
        final outputImage = await outputPicture.toImage(size, size);
        final bytes = await outputImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
        File('${directory.path}/${entry['filename']}')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        outputImage.dispose();
        outputPicture.dispose();
      }
    }
    for (final (density, size) in [
      ('mdpi', 48),
      ('hdpi', 72),
      ('xhdpi', 96),
      ('xxhdpi', 144),
      ('xxxhdpi', 192),
    ]) {
      final output = ui.PictureRecorder();
      final scaled = Canvas(output)..scale(size / _size);
      scaled.drawImage(
        image,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.high,
      );
      final recorded = output.endRecording();
      final rendered = await recorded.toImage(size, size);
      final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('android/app/src/main/res/mipmap-$density')
        ..createSync(recursive: true);
      File(
        '${directory.path}/ic_lume_${_style.isEmpty ? 'default' : _style.toLowerCase()}.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
      rendered.dispose();
      recorded.dispose();
    }
    image.dispose();
    picture.dispose();

    final file = File(
      _style.isEmpty
          ? 'assets/icon/app_icon_1024.png'
          : 'assets/icon/$_style.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(1000));
  });
}

/// Three distinct silhouettes, with restrained highlights that survive launcher sizing.
void _paintHighlightIcon(Canvas canvas) {
  const bounds = Rect.fromLTWH(0, 0, _size, _size);
  const center = Offset(512, 512);
  final colors = switch (_style) {
    'Orbit' => const [Color(0xFF34E5FF), Color(0xFF5D63FF)],
    'Prism' => const [Color(0xFFAB94FF), Color(0xFFFF72D5)],
    _ => const [Color(0xFF5BFFCC), Color(0xFF00BFEF)],
  };
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(1024, 1024),
        const [Color(0xFF10182D), Color(0xFF030814)],
      ),
  );
  canvas.drawCircle(
    center,
    460,
    Paint()
      ..shader = ui.Gradient.radial(
        center,
        460,
        [
          colors.first.withValues(alpha: .20),
          colors.last.withValues(alpha: .04),
          Colors.transparent,
        ],
        [0, .5, 1],
      ),
  );
  final luminous = Paint()
    ..shader = ui.Gradient.linear(
      const Offset(200, 200),
      const Offset(820, 820),
      colors,
    );
  void stroke(Path path, double width) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + 20
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = colors.first.withValues(alpha: .5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          path.getBounds().topLeft,
          path.getBounds().bottomRight,
          colors,
        ),
    );
  }

  if (_style == 'Orbit') {
    canvas.save();
    canvas.translate(512, 512);
    canvas.rotate(-math.pi / 7);
    for (final rect in [
      const Rect.fromLTWH(-330, -210, 660, 420),
      const Rect.fromLTWH(-210, -330, 420, 660),
    ]) {
      stroke(Path()..addOval(rect), 24);
    }
    canvas.restore();
    canvas.drawCircle(
      center,
      150,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(390, 390),
          const Offset(650, 650),
          [colors.first, colors.last],
        ),
    );
    canvas.drawCircle(
      const Offset(764, 318),
      25,
      Paint()..color = const Color(0xFFE9FCFF),
    );
  } else if (_style == 'Prism') {
    final top = Path()
      ..moveTo(512, 215)
      ..lineTo(790, 370)
      ..lineTo(512, 530)
      ..lineTo(234, 370)
      ..close();
    final left = Path()
      ..moveTo(234, 370)
      ..lineTo(512, 530)
      ..lineTo(512, 820)
      ..lineTo(234, 655)
      ..close();
    final right = Path()
      ..moveTo(512, 530)
      ..lineTo(790, 370)
      ..lineTo(790, 655)
      ..lineTo(512, 820)
      ..close();
    canvas.drawPath(
      top,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(234, 250),
          const Offset(790, 530),
          const [Color(0xFFEBE3FF), Color(0xFF8B86FF), Color(0xFFB855FF)],
          const [0, .5, 1],
        ),
    );
    canvas.drawPath(
      left,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(234, 370),
          const Offset(512, 820),
          const [Color(0xFF7FDFFF), Color(0xFF6256DC)],
        ),
    );
    canvas.drawPath(right, luminous);
    stroke(
      Path()
        ..moveTo(234, 370)
        ..lineTo(512, 530)
        ..lineTo(790, 370),
      5,
    );
    canvas.drawPath(
      Path()
        ..moveTo(512, 290)
        ..lineTo(580, 365)
        ..lineTo(512, 440)
        ..lineTo(444, 365)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: .75),
    );
    return;
  } else {
    final mark = Path()
      ..moveTo(330, 260)
      ..lineTo(330, 720)
      ..lineTo(720, 720);
    stroke(mark, 76);
    final beam = Path()
      ..moveTo(475, 315)
      ..lineTo(720, 485)
      ..lineTo(475, 620);
    stroke(beam, 50);
    canvas.drawCircle(
      const Offset(744, 720),
      17,
      Paint()..color = Colors.white,
    );
    return;
  }
  canvas.drawPath(
    Path()
      ..moveTo(475, 429)
      ..lineTo(590, 512)
      ..lineTo(475, 595)
      ..close(),
    Paint()..color = Colors.white,
  );
}

/// 底：整幅浅色渐变。
void _paintBackground(Canvas canvas) {
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, _size, _size),
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(_size, _size),
        <Color>[_bgTop, _bgBottom],
      ),
  );
}

/// 三层错位玻璃卡：越靠上越亮，右下角最深，做出「叠了一层」的层次。
void _paintCards(Canvas canvas) {
  const double cardSide = 470;
  const double radius = 96;
  // 三层从左下到右上的错位量。
  const List<double> offsets = <double>[-78, 0, 78];

  for (var index = 0; index < offsets.length; index++) {
    final dx = _size / 2 + offsets[index] - cardSide / 2;
    final dy = _size / 2 - offsets[index] - cardSide / 2;
    final rect = Rect.fromLTWH(dx, dy, cardSide, cardSide);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(radius));

    // 影子：只做极淡的一层，避免浅底上发灰。
    canvas.drawRRect(
      rrect.shift(const Offset(0, 14)),
      Paint()
        ..color = const Color(0x1A2A2A66)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );

    // 填充：左下的卡偏蓝、右上的卡偏紫，三层共用一条渐变轴。
    final warm = Color.lerp(
      _cardBlue,
      _cardPurple,
      index / (offsets.length - 1),
    )!;
    final cool = Color.lerp(_cardPurple, _cardBlue, 0.25 * index)!;
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft + const Offset(0, cardSide * 0.15),
          rect.bottomRight - const Offset(0, cardSide * 0.1),
          <Color>[
            warm.withValues(alpha: 0.92 - index * 0.06),
            cool.withValues(alpha: 0.86 - index * 0.06),
          ],
        ),
    );

    // 白色描边：玻璃边缘。
    canvas.drawRRect(
      rrect.deflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = _fore.withValues(alpha: 0.75),
    );
  }
}

/// 前景记号：播放三角 + 右下折角，画在最上面那张卡的中心。
void _paintGlyph(Canvas canvas) {
  const double cardSide = 470;
  final center = Offset(_size / 2, _size / 2);

  // 播放三角：略向右偏，视觉重心才在卡片中心。
  const double triSize = 190;
  final path = Path()
    ..moveTo(center.dx - triSize * 0.32, center.dy - triSize * 0.5)
    ..lineTo(center.dx + triSize * 0.52, center.dy)
    ..lineTo(center.dx - triSize * 0.32, center.dy + triSize * 0.5)
    ..close();
  canvas.drawPath(
    path,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(center.dx - triSize * 0.32, center.dy - triSize * 0.5),
        Offset(center.dx + triSize * 0.52, center.dy + triSize * 0.5),
        <Color>[const Color(0xFFEFF3FF), _fore],
      ),
  );

  // 折角：包住三角右下角，像屏幕的一角。
  const double armLength = 210;
  const double stroke = 26;
  final corner = Offset(
    center.dx + cardSide / 2 - 118,
    center.dy + cardSide / 2 - 118,
  );
  final bracket = Path()
    ..moveTo(corner.dx - armLength, corner.dy)
    ..lineTo(corner.dx, corner.dy)
    ..lineTo(corner.dx, corner.dy - armLength);
  canvas.drawPath(
    bracket,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _fore.withValues(alpha: 0.92),
  );

  // 三角与折角之间的呼吸感：一圈极淡的光晕。
  canvas.drawCircle(
    center,
    cardSide * 0.42,
    Paint()
      ..shader = ui.Gradient.radial(center, cardSide * 0.42, <Color>[
        _fore.withValues(alpha: 0.16),
        _fore.withValues(alpha: 0),
      ]),
  );
}

/// 供后续微调颜色时用的一键列印（保留：改配色时先看值再改）。
// ignore: unused_element
String debugPalette() => <Color>[
  _bgTop,
  _bgBottom,
  _cardBlue,
  _cardPurple,
].map((color) => color.toARGB32().toRadixString(16)).join(', ');

// 保持 math import 有用（圆形构图角度换算留给后续加弧形元素时用）。
// ignore: unused_element
double _deg(double value) => value * math.pi / 180;
