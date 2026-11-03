import 'dart:async';

import 'package:flutter/services.dart';

/// Revokes browser capabilities without deleting a user's login cookies.
class WebSessionLifecycle {
  static const _channel = MethodChannel('lumebox/source_web');
  static int _all = 0;
  static final Map<String, int> _hosts = {};

  static String revision(String url) =>
      '$_all:${_hosts[Uri.parse(url).host] ?? 0}';

  static void invalidate({Set<String>? hosts}) {
    if (hosts != null && hosts.isEmpty) return;
    if (hosts == null) {
      _all++;
      _hosts.clear();
    } else {
      for (final host in hosts) {
        _hosts[host] = (_hosts[host] ?? 0) + 1;
      }
      if (_hosts.length > 512) {
        _all++;
        _hosts.clear();
        hosts = null;
      }
    }
    unawaited(
      _channel
          .invokeMethod<void>('session.invalidate', {
            if (hosts != null) 'hosts': hosts.toList(),
          })
          .catchError((_) {}),
    );
  }
}
