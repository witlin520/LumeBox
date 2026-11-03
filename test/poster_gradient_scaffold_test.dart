import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/shared/widgets/poster_gradient_scaffold.dart';

void main() {
  test('相同海报合并并发取色，后续直接命中缓存', () async {
    final key = Object();
    final ready = Completer<Color?>();
    var calls = 0;
    Future<Color?> extract() {
      calls++;
      return ready.future;
    }

    final first = PosterPaletteCache.resolve(key, extract);
    final second = PosterPaletteCache.resolve(key, extract);
    expect(calls, 1);
    ready.complete(const Color(0xff542424));
    expect(await first, const Color(0xff542424));
    expect(await second, const Color(0xff542424));
    expect(
      await PosterPaletteCache.resolve(key, extract),
      const Color(0xff542424),
    );
    expect(calls, 1);
  });

  test('没有暗柔和色回黑，加载失败下次允许重新取色', () async {
    expect(
      await PosterPaletteCache.resolve(Object(), () async => null),
      Colors.black,
    );
    final key = Object();
    expect(
      await PosterPaletteCache.resolve(
        key,
        () async => throw StateError('offline'),
      ),
      Colors.black,
    );
    expect(
      await PosterPaletteCache.resolve(key, () async => Colors.brown),
      Colors.brown,
    );
  });

  test('缓存有上限，淘汰最久未访问的海报', () async {
    final key = Object();
    await PosterPaletteCache.resolve(key, () async => Colors.red);
    for (var i = 0; i < 64; i++) {
      await PosterPaletteCache.resolve(Object(), () async => Colors.blue);
    }
    expect(
      await PosterPaletteCache.resolve(key, () async => Colors.green),
      Colors.green,
    );
  });

  test('三段蒙层底部与页面同色，顶部保留原图', () {
    const color = Color(0xff542424);
    final gradient = posterOverlayGradient(color);
    expect(gradient.colors, hasLength(3));
    expect(gradient.stops, [0, .55, 1]);
    expect(gradient.colors.first.a, 0);
    expect(gradient.colors.last, color);
  });
}
