import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../util/lume_log.dart';
import 'liquid_glass_style.dart';
import 'glass_modules.dart';
import 'native_glass_style.dart';
export 'native_glass_style.dart';
export 'liquid_glass_style.dart';

/// Persisted shared material, with module/part overrides and a solid fallback.
class FrostedSettings extends ChangeNotifier {
  FrostedSettings();
  static final instance = FrostedSettings();
  static const fileName = 'frosted_settings.json';
  bool _frostedEnabled = true;
  bool get frostedEnabled => _frostedEnabled;
  final Map<String, LiquidGlassStyle> _styles = {};
  bool reduceTransparency = false;
  NativeGlassStyle native = const NativeGlassStyle();
  Future<void> setNative(NativeGlassStyle value, {bool persist = true}) {
    native = value;
    notifyListeners();
    return persist ? save() : Future<void>.value();
  }

  String _key(GlassModule module, GlassPart? part) =>
      '${module.name}:${part?.name ?? 'all'}';
  LiquidGlassStyle style(GlassModule module, GlassPart? part) =>
      _styles[_key(module, part)] ??
      _styles[_key(module, null)] ??
      _styles[_key(GlassModule.all, part)] ??
      _styles['all:all'] ??
      const LiquidGlassStyle();
  bool hasOverride(GlassModule module, GlassPart? part) =>
      _styles.containsKey(_key(module, part));
  Future<void> setStyle(
    GlassModule module,
    GlassPart? part,
    LiquidGlassStyle value, {
    bool persist = true,
  }) {
    _styles[_key(module, part)] = value;
    notifyListeners();
    return persist ? save() : Future<void>.value();
  }

  Future<void> resetStyle(GlassModule module, GlassPart? part) {
    _styles.remove(_key(module, part));
    notifyListeners();
    return save();
  }

  Future<void> setReduceTransparency(bool value) {
    reduceTransparency = value;
    notifyListeners();
    return save();
  }

  File? _file;
  Future<void> _pending = Future<void>.value();
  Future<void> boot({Directory? directory}) async {
    await _pending;
    _frostedEnabled = true;
    _styles.clear();
    reduceTransparency = false;
    native = const NativeGlassStyle();
    try {
      final base = directory ?? await getApplicationSupportDirectory();
      _file = File('${base.path}/$fileName');
      final legacy = File('${base.path}/glass_effects_settings.json');
      final source = await _file!.exists() ? _file! : legacy;
      if (await source.exists()) {
        final data = jsonDecode(await source.readAsString());
        if (data is Map) {
          _frostedEnabled = data['frostedEnabled'] != false;
          reduceTransparency = data['reduceTransparency'] == true;
          if (data['native'] is Map) {
            native = NativeGlassStyle.fromJson(data['native'] as Map);
          }
          if (data['styles'] is Map) {
            for (final entry in (data['styles'] as Map).entries) {
              final valid = [
                for (final m in GlassModule.values)
                  for (final p in [
                    'all',
                    ...GlassPart.values.map((p) => p.name),
                  ])
                    '${m.name}:$p',
              ];
              if (valid.contains(entry.key) && entry.value is Map) {
                _styles['${entry.key}'] = LiquidGlassStyle.fromJson(
                  entry.value as Map,
                );
              }
            }
          }
        }
      }
    } catch (error) {
      LumeLog.warn('毛玻璃设置读取失败：$error');
    }
    notifyListeners();
  }

  Future<void> setFrostedEnabled(bool value) {
    _frostedEnabled = value;
    notifyListeners();
    return save();
  }

  Future<void> save() {
    final contents = jsonEncode({
      'frostedEnabled': _frostedEnabled,
      'reduceTransparency': reduceTransparency,
      'native': native.toJson(),
      'styles': {for (final e in _styles.entries) e.key: e.value.toJson()},
    });
    void write() {
      try {
        _file!.parent.createSync(recursive: true);
        final temp = File('${_file!.path}.tmp');
        temp.writeAsStringSync(contents, flush: true);
        temp.renameSync(_file!.path);
      } catch (error) {
        LumeLog.warn('玻璃设置保存失败：$error');
      }
    }

    // Settings are small. Commit atomically on gesture release, never on each tick.
    if (_file != null) {
      write();
      return Future<void>.value();
    }
    _pending = _pending.then((_) async {
      try {
        _file = File(
          '${(await getApplicationSupportDirectory()).path}/$fileName',
        );
        write();
      } catch (error) {
        LumeLog.warn('玻璃设置保存失败：$error');
      }
    });
    return _pending;
  }
}
