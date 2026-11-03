import 'package:flutter/services.dart';

/// Converts cumulative native transfer counters into interval throughput.
class DownloadSpeedSampler {
  int? _bytes;
  Duration? _time;

  double? sample(int? bytes, Duration elapsed) {
    if (bytes == null || bytes < 0) {
      reset();
      return null;
    }
    final previous = _bytes;
    final at = _time;
    _bytes = bytes;
    _time = elapsed;
    if (previous == null || at == null || bytes < previous) return null;
    final micros = (elapsed - at).inMicroseconds;
    if (micros <= 0) return null;
    return (bytes - previous) * Duration.microsecondsPerSecond / micros;
  }

  void reset() {
    _bytes = null;
    _time = null;
  }
}

class AvNetworkStatistics {
  static const channel = MethodChannel('lumebox/av_network');
  static Future<void> applyBuffering(
    int playerId,
    double seconds,
    bool wait,
  ) async {
    try {
      await channel.invokeMethod<void>('applyBuffering', {
        'playerId': playerId,
        'seconds': seconds,
        'wait': wait,
      });
    } on MissingPluginException {
      /* Older native hosts keep their existing policy. */
    } on PlatformException {
      /* A disposed player cannot receive updates. */
    }
  }

  static Future<int?> readBytes(int playerId) async {
    try {
      final value = await channel.invokeMethod<num>('readBytes', {
        'playerId': playerId,
      });
      return value != null && value.isFinite && value >= 0
          ? value.toInt()
          : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
