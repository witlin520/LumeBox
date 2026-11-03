import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../source/source_content_rating.dart';

enum AppUnlockMethod {
  face('面容识别'),
  passcode('锁屏密码');

  const AppUnlockMethod(this.label);
  final String label;
}

class PrivacySettings extends ChangeNotifier {
  static final instance = PrivacySettings();
  static const channel = MethodChannel('lumebox/privacy');
  static const fileName = 'privacy_settings.json';
  bool get appLock => _appLock;
  bool get showAdult => _showAdult;
  AppUnlockMethod get method => _method;
  bool authenticating = false;
  bool _appLock = false, _showAdult = false;
  AppUnlockMethod _method = AppUnlockMethod.passcode;
  File? _file;

  bool allowsSource(String id, [String name = '']) =>
      _showAdult || !SourceContentRating.isAdult(id, name);

  Future<void> boot({Directory? directory}) async {
    _appLock = false;
    _showAdult = false;
    _method = AppUnlockMethod.passcode;
    final base = directory ?? await getApplicationSupportDirectory();
    _file = File('${base.path}/$fileName');
    if (await _file!.exists()) {
      try {
        final data = jsonDecode(await _file!.readAsString());
        if (data is! Map || data['appLock'] is! bool) {
          throw const FormatException('Invalid privacy configuration');
        }
        {
          _appLock = data['appLock'] == true;
          _showAdult = data['showAdult'] == true;
          _method = data['method'] == 'face'
              ? AppUnlockMethod.face
              : AppUnlockMethod.passcode;
        }
      } catch (_) {
        /* A damaged existing lock configuration must fail closed. */
        _appLock = true;
      }
    }
    try {
      await channel.invokeMethod<void>('setEnabled', {'enabled': _appLock});
    } catch (_) {
      /* Authentication itself remains fail closed. */
    }
    notifyListeners();
  }

  Future<bool> authenticate({AppUnlockMethod? using}) async {
    if (authenticating) return false;
    authenticating = true;
    notifyListeners();
    try {
      return await channel.invokeMethod<bool>('authenticate', {
            'method': (using ?? _method).name,
          }) ==
          true;
    } finally {
      authenticating = false;
      notifyListeners();
    }
  }

  Future<bool> setAppLock(bool enabled) async {
    if (enabled == _appLock) return true;
    if (!await authenticate(
      using: enabled ? _method : AppUnlockMethod.passcode,
    )) {
      return false;
    }
    await _persist(appLock: enabled);
    try {
      await channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
    } catch (_) {
      /* Flutter lock remains authoritative. */
    }
    return true;
  }

  Future<bool> setMethod(AppUnlockMethod value) async {
    if (_method == value) return true;
    if (_appLock && !await authenticate(using: AppUnlockMethod.passcode)) {
      return false;
    }
    if ((!_appLock || value != AppUnlockMethod.passcode) &&
        !await authenticate(using: value)) {
      return false;
    }
    await _persist(method: value);
    return true;
  }

  Future<void> setShowAdult(bool value) => _persist(showAdult: value);

  Future<void>? _writing;
  Future<void> _persist({
    bool? appLock,
    bool? showAdult,
    AppUnlockMethod? method,
  }) {
    final previous = _writing;
    final next = previous == null
        ? _write(appLock: appLock, showAdult: showAdult, method: method)
        : previous
              .catchError((Object _) {})
              .then(
                (_) => _write(
                  appLock: appLock,
                  showAdult: showAdult,
                  method: method,
                ),
              );
    _writing = next;
    return next.whenComplete(() {
      if (identical(_writing, next)) _writing = null;
    });
  }

  Future<void> _write({
    bool? appLock,
    bool? showAdult,
    AppUnlockMethod? method,
  }) async {
    final file = _file ??= File(
      '${(await getApplicationSupportDirectory()).path}/$fileName',
    );
    final lock = appLock ?? _appLock,
        adult = showAdult ?? _showAdult,
        unlock = method ?? _method;
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'appLock': lock, 'showAdult': adult, 'method': unlock.name}),
      flush: true,
    );
    await temporary.rename(file.path);
    _appLock = lock;
    _showAdult = adult;
    _method = unlock;
    notifyListeners();
  }
}
