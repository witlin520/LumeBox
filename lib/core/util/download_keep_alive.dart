import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// iOS 后台 / 锁屏下载保活。
///
/// `VideoDownloadCenter` 的下载是一个纯 Dart 的 `HttpClient` 循环，跑在 Dart
/// isolate 里；一锁屏 iOS 就把 App 挂起，下载随即冻结。这里用 method channel
/// 让原生侧在「下载队列活动期间」播放一段**静音循环音频**——`Info.plist` 已声明
/// `UIBackgroundModes=audio`，只要音频会话处于播放态，App 就不会被挂起，锁屏后
/// 下载就能继续。队列空了再由 `stop()` 停掉音频、结束后台任务。
///
/// 仅在 iOS 生效；Android / 其它平台是空操作（Android 后台下载走前台服务，属另一套）。
class DownloadKeepAlive {
  DownloadKeepAlive._();

  static const _channel = MethodChannel('lumebox/download_keepalive');

  static bool _active = false;

  /// 是否可用：只在 iOS（且非 Web）上真正调用原生侧。
  static bool get isSupported => !kIsWeb && Platform.isIOS;

  /// 开启保活（幂等：重复调用不会叠加）。[force] 用于在已开启时仍强制原生侧重置。
  static Future<void> start({bool force = false}) async {
    if (!isSupported) return;
    if (_active && !force) return;
    try {
      await _channel.invokeMethod<void>('start');
      _active = true;
    } catch (_) {
      // 原生通道不可用时静默降级：只是下载锁屏会停，不阻断下载本身。
    }
  }

  /// 关闭保活（幂等）。
  static Future<void> stop() async {
    if (!isSupported || !_active) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // 同上：静默降级。
    }
    _active = false;
  }
}
