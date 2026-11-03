import 'package:flutter/services.dart';

class ReaderVolumeKeys {
  static const channel = MethodChannel('lumebox/reader_keys');
  bool _disposed = false;

  ReaderVolumeKeys(void Function(int direction) onTurn) {
    channel.setMethodCallHandler((call) async {
      if (!_disposed && call.method == 'turn' && call.arguments is num) {
        onTurn((call.arguments as num).toInt());
      }
    });
  }

  Future<void> configure(bool enabled) async {
    if (_disposed) return;
    try {
      await channel.invokeMethod<void>('configure', {'enabled': enabled});
    } on MissingPluginException {
      // Desktop preview has no hardware-volume bridge.
    } on PlatformException {
      // A rejected system audio session must not block reading.
    }
  }

  void dispose() {
    configure(false);
    _disposed = true;
    channel.setMethodCallHandler(null);
  }
}
