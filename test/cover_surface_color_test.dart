import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/theme/cover_palette.dart';

void main() {
  test('海报下半部的暖色服装优先于大面积低饱和天空', () {
    final rgba = Uint8List.fromList([
      for (var y = 0; y < 12; y++)
        for (var x = 0; x < 12; x++)
          ...y < 8 ? [140, 152, 175, 255] : [160, 40, 45, 255],
    ]);
    final color = immersiveArtworkColor(rgba, width: 12, height: 12)!;
    final hsv = HSVColor.fromColor(color);
    expect(hsv.hue > 340 || hsv.hue < 20, isTrue);
    expect(hsv.saturation, greaterThan(.6));
  });

  test('中性海报不捏造暖色，透明像素不参与取色', () {
    expect(
      immersiveArtworkColor(
        Uint8List.fromList([255, 0, 0, 0]),
        width: 1,
        height: 1,
      ),
      isNull,
    );
    expect(
      immersiveArtworkColor(
        Uint8List.fromList([255, 255, 255, 255]),
        width: 1,
        height: 1,
      ),
      Colors.white,
    );
  });

  test('沉浸详情底色保留海报色相，红色海报不会统一混成蓝灰色', () {
    for (final input in [Colors.red, Colors.pink, Colors.green, Colors.blue]) {
      final original = HSVColor.fromColor(input);
      final surface = HSVColor.fromColor(immersiveCoverSurface(input));
      expect(surface.hue, closeTo(original.hue, 1));
      expect(surface.saturation, greaterThanOrEqualTo(.35));
      expect(surface.value, inInclusiveRange(.28 - 1 / 255, .38 + 1 / 255));
      expect(
        1.05 / (immersiveCoverSurface(input).computeLuminance() + .05),
        greaterThan(6),
      );
    }
  });
  test('灰阶与小面积彩色标记不会被放大成红色页面', () {
    for (final value in [0, 80, 180, 255]) {
      final rgba = Uint8List.fromList([
        for (var i = 0; i < 64 * 64; i++) ...[value, value, value, 255],
      ]);
      // A tiny saturated red mark in otherwise neutral artwork.
      rgba.setRange(0, 4, [255, 0, 0, 255]);
      final color = immersiveArtworkColor(rgba, width: 64, height: 64)!;
      final surface = immersiveCoverSurface(color);
      expect((surface.r - surface.g).abs(), lessThan(.01));
      expect((surface.g - surface.b).abs(), lessThan(.01));
      expect(1.05 / (surface.computeLuminance() + .05), greaterThan(10));
    }
  });

  test('不同明暗的同色衣服合并计权，蓝绿色仍保留各自色相', () {
    for (final hue in [0.0, 120.0, 210.0]) {
      final rgba = Uint8List.fromList([
        for (var y = 0; y < 24; y++)
          for (var x = 0; x < 24; x++)
            ...y < 15
                ? [140, 152, 175, 255]
                : () {
                    final color = HSVColor.fromAHSV(
                      1,
                      (hue + (x.isEven ? 358 : 2)) % 360,
                      .75,
                      x.isEven ? .35 : .65,
                    ).toColor();
                    return [
                      (color.r * 255).round(),
                      (color.g * 255).round(),
                      (color.b * 255).round(),
                      255,
                    ];
                  }(),
      ]);
      final color = immersiveArtworkColor(rgba, width: 24, height: 24)!;
      final actual = HSVColor.fromColor(immersiveCoverSurface(color));
      final delta = (actual.hue - hue + 180) % 360 - 180;
      expect(delta.abs(), lessThan(4));
    }
  });
}
