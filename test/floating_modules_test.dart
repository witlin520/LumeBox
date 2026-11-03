import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/theme/floating_modules.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('透明度保存重启仍生效，旧位移和模糊参数不恢复', () async {
    final root = Directory.systemTemp.createTempSync('floating-modules');
    addTearDown(() => root.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    final controller = FloatingModules.instance;
    await controller.boot();
    controller.set(
      FloatingModule.home,
      const FloatingStyle(opacity: .1, y: 12, blur: 4),
    );
    controller.set(
      FloatingModule.dock,
      const FloatingStyle(opacity: .3, y: 20),
    );
    controller.save();
    controller.reset(FloatingModule.home);
    await controller.boot();
    expect(controller.style(FloatingModule.home).opacity, .1);
    expect(controller.style(FloatingModule.home).offset, Offset.zero);
    expect(controller.style(FloatingModule.dock).opacity, .3);
    expect(controller.style(FloatingModule.dock).offset, Offset.zero);
    final clamped = FloatingStyle.fromJson({
      'opacity': -1,
      'x': 400,
      'y': -900,
      'blur': 200,
    });
    expect(clamped.opacity, 0);
    expect(clamped.x, 40);
    expect(clamped.y, -40);
    expect(clamped.blur, 30);
    File('${root.path}/floating_modules.json').writeAsStringSync(
      jsonEncode({
        'home': {'opacity': .7, 'x': 8, 'y': 19, 'blur': 24},
      }),
    );
    await controller.boot();
    expect(controller.style(FloatingModule.home).opacity, .95);
    expect(controller.style(FloatingModule.home).offset.dx, 0);
    expect(controller.style(FloatingModule.home).offset.dy, 0);
    expect(controller.style(FloatingModule.home).blur, 6);
    // 迁移只执行一次，之后保存的新透明度必须生效。
    controller.set(FloatingModule.home, const FloatingStyle(opacity: .4));
    controller.save();
    await controller.boot();
    expect(controller.style(FloatingModule.home).opacity, .4);
  });

  test('旧底栏材质数据不改变当前默认样式', () async {
    final root = Directory.systemTemp.createTempSync('floating-dock-glass');
    addTearDown(() => root.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );

    expect(FloatingStyle.dockDefault.opacity, .45);
    expect(FloatingStyle.dockDefault.blur, 15);

    // 旧版配置：底栏只有位置/透明度，没有新材质的版本号。
    File('${root.path}/floating_modules.json').writeAsStringSync(
      jsonEncode({
        'dock': {'opacity': .9, 'x': 3, 'y': 4, 'blur': 2},
      }),
    );
    final controller = FloatingModules.instance;
    await controller.boot();
    final migrated = controller.style(FloatingModule.dock);
    expect(migrated.opacity, .45, reason: '一次性换成更透的白玻璃');
    expect(migrated.blur, 15, reason: '模糊半径拉到设置上限');
    expect(migrated.x, 0);
    expect(migrated.offset.dy, 0);

    // 迁移之后滑块照常生效：再次启动不能把用户的新值覆盖回去。
    controller.set(
      FloatingModule.dock,
      const FloatingStyle(opacity: .4, blur: 15),
    );
    controller.save();
    await controller.boot();
    expect(controller.style(FloatingModule.dock).opacity, .4);
    expect(controller.style(FloatingModule.dock).blur, 15);
  });
}
