import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/cat/cat_service.dart';

/// Shares the existing process-wide Node host. No user address or download.
class BuiltinDanmakuService {
  static final instance = BuiltinDanmakuService();
  static const address = 'lumebox://local-danmaku';
  Future<Uri>? _starting;
  Timer? _idle;
  static bool _licenseRegistered = false;

  static void registerLicense() {
    if (_licenseRegistered) return;
    _licenseRegistered = true;
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        'danmu_api / LogVar (AGPL-3.0)',
      ], await rootBundle.loadString('assets/local_danmaku/LICENSE'));
    });
  }

  Future<Uri> ensureStarted() {
    registerLicense();
    _idle?.cancel();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<Uri> _start() async {
    if (!Platform.isIOS) throw UnsupportedError('内置本机弹幕服务目前仅支持 iPhone／iPad');
    final base = await CatService.instance.startLocalDanmaku();
    // Search/comments are downloaded on demand; idle service needs no open socket.
    _idle = Timer(const Duration(minutes: 2), () => unawaited(stop()));
    return base;
  }

  Future<void> stop() async {
    _idle?.cancel();
    _idle = null;
    try {
      await _starting;
      await CatService.instance.stopLocalDanmaku();
    } catch (_) {
      // An external service selection must still be saved if Node has stopped.
    }
  }
}
