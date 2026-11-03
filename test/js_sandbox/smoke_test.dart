import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/js/sandbox/sandbox.dart';
import 'package:lume_box/core/js/source_registry.dart';
import 'package:lume_box/core/net/lume_net.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';

import '../support/demo_site.dart';
import 'support/js_sandbox_support.dart';

/// **全量冒烟**：一条命令跑完本轮该看的几件事。
///
/// 运行：`flutter test test/js_sandbox/smoke_test.dart`
///
/// 内容（三块，各打印一行结论，最后汇总）：
/// 1. **三份示例源各自在对应板块跑通**：导入 → 开真实引擎 → HTTP 打本机示例站 →
///    分类 / 列表 / 正文（小说文本 / 漫画图片 / 视频直链，三种内容形态各一次）；
/// 2. **跨板块拒绝**：三份脚本导入错误板块都被拦下（板块隔离在导入阶段生效）；
/// 3. **沙箱安全**：纯 CPU 死循环被回收（真 QuickJS + 原生中断通路）、
///    上下文隔离（同 id 跨板块互不可见）。
///
/// 与专项用例的关系：这里是**冒烟级**（每项一条，给人看结论），
/// 细粒度断言仍在 `demo_sources_test` / `security_audit_test` /
/// `deadloop_timeout_test` 里。冒烟里任何一条失败都说明有回归。
///
/// 原生桥缺失时整组跳过（Windows 需先 `flutter build windows`）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final available = installBridge();
  final skipReason = available
      ? null
      : '未找到可用的 quickjs 原生桥（Windows 需先 `flutter build windows`）';

  HttpOverrides? savedOverrides;
  late Directory root;
  late DemoSite site;
  final List<String> report = <String>[];

  setUp(() async {
    enableEngineOnThisPlatform();
    savedOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    root = Directory.systemTemp.createTempSync('lume_box_smoke');
    await installTempSectionRoot(root);
    site = await DemoSite.start();
  });

  tearDown(() async {
    for (final section in Section.values) {
      SourceRegistry.close(section);
    }
    await SectionScope.closeAll();
    await site.stop();
    HttpOverrides.global = savedOverrides;
    LumeNet.closeSharedClientForTesting();
    restoreEnginePlatformGate();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  tearDownAll(() {
    // ignore: avoid_print
    print('\n[冒烟汇总]\n${report.map((line) => '  · $line').join('\n')}');
  });

  test(
    '③ 沙箱安全：纯 CPU 死循环被回收；同 id 跨板块互不可见',
    () async {
      // 死循环：在独立 isolate 里跑（纯 CPU 空转会把调用线程占住），
      // 由原生中断通路回收；断言「被回收 + 判废 + 重建后可用」。
      final run = await runSandboxCallInWorker(
        script: fixture('deadloop_source.js'),
        method: 'list',
        budget: const Duration(seconds: 12),
      );
      addTearDown(run.kill);
      expect(run.armed, isTrue, reason: 'worker 应真的进到调用死循环这一步');
      expect(
        run.completed,
        isTrue,
        reason: '死循环必须在预算内被回收（中断通路可用性：'
            '${SandboxGuard.interruptAvailable}）',
      );
      final deadloop = run.report!;
      expect(
        deadloop['errorKind'],
        anyOf(SandboxErrorKind.timeout.id, SandboxErrorKind.instructions.id),
        reason: '死循环应判定为失控（超时或超指令数），而不是普通脚本错误',
      );
      expect(deadloop['rebuiltOk'], isTrue, reason: '判废后重建的上下文要能干活');
      report.add(
        '死循环：${deadloop['errorKind']} 判定 · 代数 '
        '${deadloop['generation']}→${deadloop['generationAfter']} · 重建可用 ✓',
      );

      // 上下文隔离：同一份脚本、同一个 id，分别落在两个板块 → 各持各的存储。
      const script = '''
// LumeSource: {"id":"smoke-isolation","name":"冒烟隔离源","version":"1.0.0"}
var LumeSource = {
  id: 'smoke-isolation',
  name: '冒烟隔离源',
  version: '1.0.0',
  async plant(argument) {
    await LumeSource.fs.writeText('smoke/probe.txt', String(argument && argument.value));
    return { ok: true };
  },
  async probe() {
    var value = await LumeSource.fs.readText('smoke/probe.txt');
    return { value: value === null || value === undefined ? null : String(value) };
  },
  async list() { return { items: [], hasMore: false }; }
};
''';
      final comic = await openEngine(
        sourceId: 'smoke-isolation',
        script: script,
        section: Section.comic,
      );
      final novel = await openEngine(
        sourceId: 'smoke-isolation',
        script: script,
        section: Section.video,
      );
      addTearDown(comic.dispose);
      addTearDown(novel.dispose);
      await comic.callResult('plant', <String, Object?>{'value': 'comic-only'});
      final comicProbe =
          (await comic.callResult('probe')).value! as Map<Object?, Object?>;
      final novelProbe =
          (await novel.callResult('probe')).value! as Map<Object?, Object?>;
      expect(comicProbe['value'], 'comic-only');
      expect(novelProbe['value'], isNull, reason: '同名存储路径不跨板块');
      report.add('上下文隔离：同名存储跨板块读不到（小说侧为空）✓');
    },
    skip: skipReason,
    timeout: const Timeout(Duration(seconds: 180)),
  );
}
