import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/features/video/danmaku/danmaku_overlay.dart';
import 'package:lume_box/features/video/danmaku/danmaku_models.dart';
import 'package:lume_box/features/video/danmaku/danmaku_settings.dart';

void main() {
  final track = DanmakuTrack.parse([
    {'time': 0, 'text': '清晰弹幕'},
  ]);
  Widget view({
    bool playing = true,
    Duration position = Duration.zero,
    double rate = 1,
  }) => MaterialApp(
    home: SizedBox(
      width: 400,
      height: 240,
      child: DanmakuOverlay(
        position: position,
        playing: playing,
        playbackRate: rate,
        track: track,
        settings: const DanmakuSettings(),
      ),
    ),
  );
  dynamic painter(WidgetTester tester) => tester
      .widget<CustomPaint>(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.painter.runtimeType.toString() == '_DanmakuPainter',
        ),
      )
      .painter;
  testWidgets('后台和隐藏页停止弹幕帧，恢复后继续绘制', (tester) async {
    await tester.pumpWidget(view());
    await tester.pump(const Duration(milliseconds: 100));
    final before = painter(tester).position;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 1));
    expect(painter(tester).position, before);
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(TickerMode(enabled: false, child: view()));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('没有当前弹幕的长空档不持续调度帧，进度更新到出现时恢复', (tester) async {
    final future = DanmakuTrack.parse([
      {'time': 30000, 'text': '稍后出现'},
    ]);
    Widget scene(Duration position) => MaterialApp(
      home: SizedBox(
        width: 400,
        height: 240,
        child: DanmakuOverlay(
          position: position,
          playing: true,
          track: future,
          settings: const DanmakuSettings(),
        ),
      ),
    );
    await tester.pumpWidget(scene(Duration.zero));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(scene(const Duration(seconds: 30)));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('逐帧推进且复用文字排版，清晰描边没有模糊阴影', (tester) async {
    await tester.pumpWidget(view());
    await tester.pump(const Duration(milliseconds: 16));
    final first = painter(tester);
    final fill = first.entries.first.fill;
    final picture = first.entries.first.picture;
    expect(picture, isNotNull);
    final initialPosition = first.position as Duration;
    expect(fill.text.style.shadows, isNull);
    expect(
      first.entries.first.outline.text.style.foreground.style,
      PaintingStyle.stroke,
    );
    await tester.pump(const Duration(milliseconds: 80));
    final next = painter(tester);
    expect(next.position, greaterThan(initialPosition));
    expect(identical(first, next), isTrue, reason: '帧动画仅重绘，不重建整个弹幕组件');
    expect(identical(fill, next.entries.first.fill), true);
    expect(
      identical(picture, next.entries.first.picture),
      true,
      reason: '滚动帧复用录制的文字与描边，而不是每帧重新提交两个段落',
    );
    // A slightly late engine report must not clear already visible comments.
    await tester.pumpWidget(view(position: const Duration(milliseconds: 60)));
    expect(painter(tester).entries.length, 1);
    await tester.pumpWidget(
      view(playing: false, position: const Duration(milliseconds: 60)),
    );
    final paused = painter(tester).position;
    await tester.pump(const Duration(seconds: 1));
    expect(painter(tester).position, paused);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('倍速与插值上限，失去引擎进度时不无限跑远', (tester) async {
    await tester.pumpWidget(view(rate: 2));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 200));
    expect(painter(tester).position.inMilliseconds, greaterThanOrEqualTo(400));
    await tester.pump(const Duration(seconds: 2));
    expect(
      painter(tester).position,
      lessThanOrEqualTo(const Duration(seconds: 2)),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(painter(tester).position, const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('引擎采样略落后时，滚动时钟不突然后退', (tester) async {
    await tester.pumpWidget(view());
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 200));
    final before = painter(tester).position as Duration;
    await tester.pumpWidget(view(position: const Duration(milliseconds: 150)));
    final after = painter(tester).position as Duration;
    expect((after - before).inMilliseconds, greaterThanOrEqualTo(-3));
    await tester.pump(const Duration(milliseconds: 16));
    expect(painter(tester).position, greaterThan(after));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('暂停情况下进度更新仍清理已经过期的文字', (tester) async {
    await tester.pumpWidget(view(playing: false));
    expect(painter(tester).entries.length, 1);
    await tester.pumpWidget(
      view(playing: false, position: const Duration(seconds: 10)),
    );
    expect(painter(tester).entries, isEmpty);
  });
  testWidgets('400毫秒进度采样有延迟时，每帧持续向前且不周期性跳动', (tester) async {
    await tester.pumpWidget(view());
    var previous = painter(tester).position as Duration;
    for (var frame = 1; frame <= 100; frame++) {
      if (frame % 25 == 0) {
        await tester.pumpWidget(
          view(position: Duration(milliseconds: frame * 16 - 100)),
        );
      }
      await tester.pump(const Duration(milliseconds: 16));
      final current = painter(tester).position as Duration;
      final step = (current - previous).inMicroseconds;
      expect(step, inInclusiveRange(14000, 19000), reason: '第$frame帧');
      previous = current;
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('两万条同秒拥挤弹幕不会积压到后续秒，下一秒仍按时投放', (tester) async {
    final dense = DanmakuTrack.parse([
      for (var i = 0; i < 20000; i++) {'time': 0, 'text': '突发弹幕 $i'},
      {'time': 1000, 'text': '下一秒'},
    ]);
    Widget scene(Duration position) => MaterialApp(
      home: SizedBox(
        width: 400,
        height: 240,
        child: DanmakuOverlay(
          position: position,
          playing: true,
          track: dense,
          settings: const DanmakuSettings(
            rows: 1,
            maxOnScreen: 1,
            showTop: true,
            blockedWords: ['突发弹幕'],
          ),
        ),
      ),
    );
    await tester.pumpWidget(scene(Duration.zero));
    expect(painter(tester).entries, isEmpty);
    await tester.pumpWidget(scene(const Duration(seconds: 1)));
    expect(painter(tester).entries.length, 1);
    expect(painter(tester).entries.first.item.text, '下一秒');
    await tester.pumpWidget(scene(const Duration(seconds: 9)));
    expect(painter(tester).entries, isEmpty, reason: '丢弃的弹幕不能延后补播');
    await tester.pumpWidget(const SizedBox());
  });
}
