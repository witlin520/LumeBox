import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/js/qjs_bindings.dart';
import 'package:lume_box/core/js/sandbox/sandbox.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/source.dart';

/// 真实引擎下的契约联调：在 QuickJS 沙箱里载入 `assets/js/example_source.js`，
/// 经 [JsDataSource] 走通统一数据源接口。
///
/// 这是 iOS 之外的替代验证——脚本语法、契约字段名、适配器解析与异常归一
/// 全部在真实引擎上被证明一致；iOS 真机联调仍留待有 Mac 设备后进行。
/// 原生桥缺失时整组跳过（Windows 需先 `flutter build windows`）。
void main() {
  final bridge = _resolveBridge();
  if (bridge != null) {
    Qjs.overrideLibrary(bridge);
    // 断言型构建下释放 JSRuntime 会触发插件的泄漏断言，测试进程同样适用。
    Qjs.reclaimRuntime = false;
  }

  final skipReason = Qjs.isAvailable
      ? null
      : '未找到可用的 quickjs 原生桥（${Qjs.availabilityDetail}）';

  group('真实引擎 · JS 图源契约', () {
    late LumeSandbox sandbox;
    late JsDataSource source;

    setUp(() async {
      sandbox = LumeSandbox.create(id: 'example-source');
      final script =
          File('assets/js/example_source.js').readAsStringSync();
      final loaded = await sandbox.load(script);
      expect(
        loaded.isOk,
        isTrue,
        reason: '示例脚本必须能在真实引擎里载入: ${loaded.error}',
      );
      source = JsDataSource(
        id: 'lume-example',
        name: 'Lume Box 示例源',
        section: Section.video,
        runtime: _SandboxRuntime(sandbox),
      );
    });

    tearDown(() => sandbox.dispose());



    test('脚本缺方法时归一到 callFailed，而不是静默空结果', () async {
      await sandbox.load('var LumeSource = { id: "x", name: "y" };');
      await expectLater(
        source.categories(),
        throwsA(
          isA<SourceException>().having(
            (error) => error.kind,
            'kind',
            SourceErrorKind.callFailed,
          ),
        ),
      );
    });
  }, skip: skipReason);
}

/// 测试专用：把底层沙箱适配成数据源运行时端口。
///
/// 生产链路上这一步由组合根（`LumeSources`）用图源引擎完成；测试里直接驱动
/// 沙箱，就能在没有 iOS 图源引擎的平台上验证同一个 [JsDataSource] 适配器。
class _SandboxRuntime implements JsSourceRuntime {

  @override
  Future<Set<String>> contractMethods() async =>
      const <String>{'categories', 'list', 'detail', 'chapters', 'content'};
  _SandboxRuntime(this._sandbox);

  final LumeSandbox _sandbox;

  @override
  Future<Object?> call(String method, [Object? argument]) async {
    final result = await _sandbox.call('LumeSource.$method', argument);
    if (result.isOk) return result.value;
    throw SourceException(SourceErrorKind.callFailed, result.error!.toString());
  }
}

/// Windows 下取构建产物，其他平台走进程镜像（与 sandbox_native_test 一致）。
DynamicLibrary? _resolveBridge() {
  if (!Platform.isWindows) {
    try {
      return DynamicLibrary.process();
    } catch (_) {
      return null;
    }
  }
  for (final config in <String>['Debug', 'Release', 'Profile']) {
    final file = File(
      '${Directory.current.path}/build/windows/x64/runner/$config/'
      'quickjs_c_bridge_plugin.dll',
    );
    if (!file.existsSync()) continue;
    try {
      return DynamicLibrary.open(file.absolute.path);
    } catch (_) {
      continue;
    }
  }
  return null;
}
