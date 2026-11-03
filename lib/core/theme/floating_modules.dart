import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../util/lume_log.dart';

enum FloatingModule {
  navigation('顶部导航'),
  home('首页功能、分类与筛选'),
  dock('底部导航'),
  overlay('其他悬浮面板');

  const FloatingModule(this.label);
  final String label;
}

class FloatingStyle {
  const FloatingStyle({
    this.opacity = .72,
    this.x = 0,
    this.y = 0,
    this.blur = 6,
  });

  /// 底部导航的默认材质：极透的白玻璃 + 15 度磨砂。
  ///
  /// 参考图口径是「能看见背后海报的色块走向」：白底再厚一点（65%）就会把
  /// 模糊后的内容盖成一块塑料，所以这里收到 45%；磨砂给到 15，玻璃才有
  /// 厚度。其余悬浮模块保持原来的 6 度微磨砂——顶部栏贴着文字，糊得太狠
  /// 会读不清。
  static const FloatingStyle dockDefault = FloatingStyle(
    opacity: .45,
    blur: 15,
  );

  /// 各模块的默认值（新建配置 / 重置时用）。
  static FloatingStyle defaultFor(FloatingModule module) =>
      module == FloatingModule.dock
      ? dockDefault
      : module == FloatingModule.navigation || module == FloatingModule.home
      ? const FloatingStyle(opacity: .95)
      : const FloatingStyle();

  final double opacity, x, y, blur;
  Offset get offset => Offset.zero;
  FloatingStyle copyWith({
    double? opacity,
    double? x,
    double? y,
    double? blur,
  }) => FloatingStyle(
    opacity: opacity ?? this.opacity,
    x: x ?? this.x,
    y: y ?? this.y,
    blur: blur ?? this.blur,
  );
  Map<String, double> toJson() => {
    'opacity': opacity,
    'x': x,
    'y': y,
    'blur': blur,
  };
  factory FloatingStyle.fromJson(Map value) {
    double read(String key, double fallback, double min, double max) {
      final raw = value[key];
      return raw is num && raw.isFinite
          ? raw.toDouble().clamp(min, max)
          : fallback;
    }

    return FloatingStyle(
      opacity: read('opacity', .72, 0, 1),
      x: read('x', 0, -40, 40),
      y: read('y', 0, -40, 80),
      blur: read('blur', 6, 0, 30),
    );
  }
}

class FloatingModules extends ChangeNotifier {
  FloatingModules._();
  static final instance = FloatingModules._();
  final Map<FloatingModule, FloatingStyle> _styles = {};
  File? _file;
  FloatingStyle style(FloatingModule module) =>
      FloatingStyle.defaultFor(module)
          .copyWith(opacity: _styles[module]?.opacity);
  Future<void> boot() async {
    try {
      _styles.clear();
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/floating_modules.json');
      if (_file!.existsSync()) {
        final data = jsonDecode(_file!.readAsStringSync());
        if (data is Map) {
          for (final module in FloatingModule.values) {
            final raw = data[module.name];
            if (raw is Map) {
              final previous = FloatingStyle.fromJson(raw);
              final readable = data['_readableGlassVersion'] == 1
                  ? previous
                  : previous.copyWith(opacity: .72, blur: 6);
              // 底部导航这一轮换成「45% 白 + 15 度磨砂」：给旧配置做一次性
              // 迁移（沿用旧版的用户也能看到新材质）。迁移后滑块照常生效。
              _styles[module] =
                  module == FloatingModule.dock &&
                      data['_dockGlassVersion'] != 2
                  ? previous.copyWith(
                      opacity: FloatingStyle.dockDefault.opacity,
                      blur: FloatingStyle.dockDefault.blur,
                    )
                  : readable;
              if ((module == FloatingModule.home ||
                      module == FloatingModule.navigation) &&
                  data['_topGlassVersion'] != 1) {
                _styles[module] = _styles[module]!.copyWith(
                  opacity: FloatingStyle.defaultFor(module).opacity,
                );
              }
            }
          }
        }
      }
      save();
      notifyListeners();
    } catch (error) {
      LumeLog.warn('悬浮设置读取失败：$error');
    }
  }

  void set(FloatingModule module, FloatingStyle value) {
    value = value.copyWith(blur: value.blur.clamp(0, 30));
    _styles[module] = module == FloatingModule.dock
        ? value.copyWith(y: value.y.clamp(-40, 20))
        : value;
    notifyListeners();
  }

  void reset(FloatingModule module) =>
      set(module, FloatingStyle.defaultFor(module));
  void save() {
    final file = _file;
    if (file == null) return;
    try {
      final temp = File('${file.path}.tmp');
      temp.writeAsStringSync(
        jsonEncode({
          '_clearGlassVersion': 1,
          '_microGlassVersion': 1,
          '_readableGlassVersion': 1,
          '_dockGlassVersion': 2,
          '_topGlassVersion': 1,
          for (final e in _styles.entries) e.key.name: e.value.toJson(),
        }),
        flush: true,
      );
      temp.renameSync(file.path);
    } catch (error) {
      LumeLog.warn('悬浮设置保存失败：$error');
    }
  }
}
