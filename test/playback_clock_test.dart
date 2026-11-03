import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/player/playback_clock.dart';
import 'package:lume_box/features/source/source_login_page.dart';

void main() {
  for (final sampleMs in [200, 400, 500]) {
    for (final rate in [0.5, 1.0, 2.0]) {
      test('位置每 $sampleMs ms 更新、$rate 倍速时逐帧前进，不按内核采样跳动', () {
        final clock = PlaybackClock();
        var previous = Duration.zero;
        for (var frameMs = 0; frameMs <= 3000; frameMs += 10) {
          final sample = Duration(
            microseconds: ((frameMs ~/ sampleMs) * sampleMs * 1000 * rate)
                .round(),
          );
          final now = clock.advance(
            sample: sample,
            frame: Duration(milliseconds: frameMs),
            playing: true,
            rate: rate,
          );
          if (frameMs > 0) {
            expect(
              (now - previous).inMicroseconds,
              inInclusiveRange((9000 * rate).round(), (11000 * rate).round()),
            );
          }
          previous = now;
        }
      });
    }
  }
  test('轻微位置回抖平滑处理，真正跳转立即重定位，暂停静止', () {
    final c = PlaybackClock();
    c.advance(
      sample: const Duration(seconds: 10),
      frame: Duration.zero,
      playing: true,
    );
    final before = c.advance(
      sample: const Duration(seconds: 10),
      frame: const Duration(milliseconds: 100),
      playing: true,
    );
    final jitter = c.advance(
      sample: const Duration(milliseconds: 9980),
      frame: const Duration(milliseconds: 110),
      playing: true,
    );
    expect(jitter > before, true);
    final seek = c.advance(
      sample: const Duration(seconds: 3),
      frame: const Duration(milliseconds: 120),
      playing: true,
    );
    expect(seek, const Duration(seconds: 3));
    final paused = c.advance(
      sample: seek,
      frame: const Duration(milliseconds: 130),
      playing: false,
    );
    expect(
      c.advance(
        sample: seek,
        frame: const Duration(seconds: 1),
        playing: false,
      ),
      paused,
    );
  });
  test('真正停止报告位置后不会无限前进；恢复帧节拍不倒退', () {
    final c = PlaybackClock();
    c.advance(sample: Duration.zero, frame: Duration.zero, playing: true);
    for (var ms = 10; ms < 2500; ms += 10) {
      final at = c.advance(
        sample: Duration.zero,
        frame: Duration(milliseconds: ms),
        playing: true,
      );
      expect(at <= const Duration(seconds: 1), true);
    }
    expect(
      c.advance(
        sample: const Duration(seconds: 6),
        frame: Duration.zero,
        playing: true,
      ),
      const Duration(seconds: 6),
    );
  });
  test('有账号配置、CF 页面或登录表单不会被说成已成功登录', () {
    expect(SourceLoginPage.status({'loginForm': true}, {}), contains('尚未登录'));
    expect(
      SourceLoginPage.status({'blocked': true}, {'wordpress_logged_in_x': 'x'}),
      contains('拒绝访问'),
    );
    expect(
      SourceLoginPage.status({'loggedIn': true}, {}),
      contains('已检测到站点登录'),
    );
    expect(SourceLoginPage.status({}, {}), contains('未提供可识别'));
  });
}
