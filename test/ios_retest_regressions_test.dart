import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:lume_box/core/net/lume_http.dart';
import 'package:lume_box/core/player/abstract_player.dart';
import 'package:lume_box/core/player/player_factory.dart';
import 'package:lume_box/core/player/player_settings.dart';
import 'package:lume_box/core/player/player_stats.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/comic/comic_page.dart';
import 'package:lume_box/features/reading/explore_view.dart';
import 'package:lume_box/features/video/danmaku/danmaku_settings.dart';
import 'package:lume_box/features/video/player_speed_meter.dart';
import 'package:lume_box/features/video/video_player_page.dart';

import 'support/fake_source_manager.dart';

/// iOS 复测（2026-10-12）查实的几处缺陷的回归用例。
///
/// 每条用例都对着一次**真机 / 模拟器的实测现象**写，不是照着实现反推的：
/// - 漫画导入订阅后探索页报「Bad state: This database has already been closed」；
/// - 弹幕开关关掉后重开视频又变回「开」；
/// - 点「测速」之后什么都没有（失败与「还没测」共用同一个占位文案）；
/// - MPV 内核销毁播放器必崩（SIGABRT，mp_destroy_client）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('lume_box_ios_retest');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? root.path
              : null,
        );
    // 阅读库在**真实时钟**里先打开：testWidgets 的 fake-async 里等不到真实 IO。
    await ReadingLibrary.open(Section.comic);
  });

  tearDown(() async {
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await SectionScope.closeAll();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// 按固定帧数推进（不用 `pumpAndSettle`：页面里只要有转圈动画它就永远等不到
  /// 「无新帧」，而这里要的只是「让异步链路跑完几轮」）。
  Future<void> advance(WidgetTester tester, [int frames = 8]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  // ------------------------------------------------------------------ P1-2

  group('图源板块：探索页与板块级注册表的资源归属', () {
    Future<FakeSourceManager> pumpComicBoard(WidgetTester tester) async {
      final manager = FakeSourceManager(
        sources: const <SourceDescriptor>[
          SourceDescriptor(
            id: 'demo-comic',
            name: '示例漫画源',
            version: '1.0.0',
            enabled: true,
          ),
        ],
      );
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: LumeTheme.build(),
          home: ComicPage(runtimeAvailable: true, manager: manager),
        ),
      );
      await advance(tester);
      return manager;
    }

    testWidgets('图源变更后探索页**原地**刷新：不换 Key 重挂', (tester) async {
      await pumpComicBoard(tester);
      expect(find.byType(ExploreView), findsOneWidget, reason: '板块把探索页挂上了');
      final before = tester.state(find.byType(ExploreView));

      // 「源管理」返回 = 走一遍宿主的 `_onSourcesChanged()`（图源变更代数 +1）。
      // 曾经的写法用 `ValueKey(revision)` 重挂探索页：新实例的首次解析会同步拿到
      // 旧的板块注册表，同一帧末尾旧实例 dispose 把它连同数据库一起关掉，新实例
      // 在飞的那条读就报「数据库已关闭」（真机在漫画导入订阅后复现）。
      await tester.tap(find.byKey(const ValueKey('open-source-picker')));
      await advance(tester);
      await tester.tap(find.byTooltip('源管理'));
      await advance(tester);
      expect(find.widgetWithText(AppBar, '漫画 · 源管理'), findsOneWidget);

      await tester.pageBack();
      await advance(tester);
      await tester.tap(find.byTooltip('关闭'));
      await advance(tester);

      final after = tester.state(find.byType(ExploreView));
      expect(
        identical(before, after),
        isTrue,
        reason: '探索页必须原地刷新；重挂会与旧实例的 dispose 抢同一份板块注册表',
      );
      expect(find.byType(ExploreView), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('板块页卸载：探索页不关掉板块级的图源管理器', (tester) async {
      final manager = await pumpComicBoard(tester);

      // 卸载整个板块页：探索页退出时**只归还借用**，不 close——它一 close 就是
      // 关掉整个板块的图源库，书架 / 详情 / 播放页随后都会报「库已关闭」。
      await tester.pumpWidget(const SizedBox.shrink());
      await advance(tester);

      expect(manager.closed, isFalse, reason: '板块共享的图源管理器由板块页收尾（与阅读库同一条纪律）');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // ------------------------------------------------------------------ P2-4

  group('弹幕设置的持久化', () {
    Future<void> pumpPlayerUnready(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: LumeTheme.build(),
          home: VideoPlayerPage(
            fullscreenOnly: false,
            media: PlayerMedia(uri: Uri.parse('https://example.com/a.mp4')),
            catalog: const _AvailableCatalog(),
            playerFactory: (kernel) => _SilentPlayer(kernel),
          ),
        ),
      );
      // 故意**不**预开视频板块的阅读库：`_boot` 的读盘会一直悬着（fake-async 里
      // 真实 IO 完不成），这正是「用户的点击早于读盘完成」的那个时刻——控制栏在
      // 库就绪前就画出来了。
      await tester.pump();
    }

    testWidgets('库还没打开就改了开关：不被读盘结果盖回去，并补落库', (tester) async {
      await pumpPlayerUnready(tester);
      expect(find.byTooltip('弹幕：开'), findsWidgets, reason: '默认是开');

      // 用户点开关（此刻 _library 还是 null，落库无从谈起）。
      await tester.longPress(find.byTooltip('弹幕：开').first);
      await advance(tester, 2);
      expect(find.byTooltip('弹幕：关'), findsWidgets, reason: '界面当场就变了');

      // 放开真实 IO，让**页面自己那次**读盘回来（旧实现会在这里用存下来的默认值
      // 覆盖用户的点击）。交替「跑一会儿真实时钟 + 推一帧」，让真实的目录 / 库
      // 打开完成、fake-async 里的续体也跟上。
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (ReadingLibrary.find(Section.video) != null) break;
      }
      await advance(tester);
      expect(
        ReadingLibrary.find(Section.video),
        isNotNull,
        reason: '页面的阅读库应当已经打开（否则这条用例测不到读盘之后的行为）',
      );

      expect(find.byTooltip('弹幕：关'), findsWidgets, reason: '读盘回来不得盖掉用户刚改的那一份');
      expect(find.byTooltip('弹幕：开'), findsNothing);

      // 而且真的落库了：下次进播放页读出来就是「关」。
      final library = ReadingLibrary.find(Section.video)!;
      expect(
        DanmakuSettingsStore(library).load().enabled,
        isFalse,
        reason: '库就绪前改的那一次也要补落库，不能静默丢掉',
      );
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // ------------------------------------------------------------------ O-3

  group('测速', () {
    Future<PlaybackSpeedMeter> pumpPlayer(WidgetTester tester) async {
      final meter = PlaybackSpeedMeter(
        // 站点的探测请求没给出有效数据（这里用一份「长度不足」的响应复现同一
        // 结论）：界面必须如实说「测速失败」，而不是继续显示「测速」装作没点过。
        http: LumeHttp(client: _TinyResponseClient(), source: '测速'),
      );
      addTearDown(meter.dispose);
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: LumeTheme.build(),
          home: VideoPlayerPage(
            fullscreenOnly: false,
            media: PlayerMedia(uri: Uri.parse('https://example.com/a.mp4')),
            catalog: const _AvailableCatalog(),
            speedMeter: meter,
            playerFactory: (kernel) => _SilentPlayer(kernel),
          ),
        ),
      );
      await tester.pump();
      return meter;
    }

    testWidgets('原测速失败入口已删除', (tester) async {
      final meter = await pumpPlayer(tester);
      meter.failed.value = true;
      await advance(tester);
      expect(find.textContaining('测速'), findsNothing);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // ------------------------------------------------------------------ P0-1

  group('MPV 内核的销毁时序（静态守卫）', () {
    // 这条缺陷在真机（模拟器）上是 SIGABRT，Windows 上跑不到 libmpv，因此这里守
    // **源码纪律**而不是行为：引擎绝不能在 media_kit 之外自行销毁视频输出。
    //
    // 根因回顾：iOS 的视频输出就是 libmpv 的 render context，媒体库只在
    // `Player.dispose()` 的 release 链里释放它（`VideoOutputManager.Dispose`），
    // 再延迟 5 秒 `mpv_terminate_destroy`。谁抢先动一下视频控制器（尤其是基类
    // 那个只关 ValueNotifier 的 dispose），release 链里的原生释放就会被二次
    // dispose 异常吃掉 → `mp_destroy_client` 发现 render context 还在 → `abort()`：
    // `Broken API use: mpv_render_context_free() not called.`
    test('引擎不得自行销毁视频输出（否则 mpv 客户端销毁时 abort）', () {
      final lines = File('lib/core/player/media_kit_mpv_engine.dart')
          .readAsStringSync()
          .split('\n');
      // 只看**代码**，注释里允许出现这个名字（上面那段说明就得写它）。
      final code = lines
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        code.contains('_video.platform'),
        isFalse,
        reason:
            '视频输出的收尾只能由 media_kit 自己按序做：'
            '引擎里出现 _video.platform（再配一次 dispose）就会重现真机的 SIGABRT',
      );
      expect(
        code.contains('await _player.dispose()'),
        isTrue,
        reason: '释放 Player 才是唯一的收尾入口（它的 release 链负责视频输出）',
      );
    });
  });
}

/// 内核目录替身：只回答「有哪些内核可用」。
class _AvailableCatalog implements PlayerKernelCatalog {
  const _AvailableCatalog();

  @override
  bool isAvailable(PlayerKernel kernel) => true;

  @override
  String? unavailableReason(PlayerKernel kernel) => null;
}

/// 静默播放器：只让页面有「就绪」的落点，不产生任何快照。
class _SilentPlayer extends AbstractPlayer {
  _SilentPlayer(this.kernel);

  final PlayerKernel kernel;

  final ValueNotifier<PlayerSnapshot> _snapshot = ValueNotifier<PlayerSnapshot>(
    const PlayerSnapshot(),
  );
  late final ValueNotifier<PlayerStats> _stats = ValueNotifier<PlayerStats>(
    PlayerStats(engineLabel: kernel.label),
  );

  @override
  ValueListenable<PlayerSnapshot> get snapshot => _snapshot;

  @override
  ValueListenable<PlayerStats> get stats => _stats;

  @override
  Future<void> load(PlayerMedia media) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> applySettings(PlayerSettings settings) async {}

  @override
  Widget buildView() => const SizedBox.shrink();

  @override
  Future<void> dispose() async {
    _snapshot.dispose();
    _stats.dispose();
  }
}

/// 回一份「太短」的探测响应：与「站点拒绝 / 回错误页」在测速里是同一个结论
/// （读不到有效数据 → 没有读数）。
class _TinyResponseClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return http.StreamedResponse(
      Stream<List<int>>.value(List<int>.filled(300, 0)),
      200,
    );
  }
}
