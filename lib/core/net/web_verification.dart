import 'dart:convert';

import 'package:flutter/services.dart';

/// Read-only DOM inspection; CAPTCHA interaction always belongs to the user.
class WebVerification {
  static Future<String>? _probe;
  static Future<String> script({
    List<String> selectors = const [],
    int status = 200,
    bool confirmed = false,
    int elapsedMs = 0,
  }) async {
    final source = await (_probe ??= rootBundle.loadString(
      'assets/js/verification_probe.js',
    ));
    return '($source)(${jsonEncode(selectors)},$status,$confirmed,$elapsedMs)';
  }

  static Map<String, dynamic>? decode(Object? raw) {
    try {
      var value = raw;
      for (var i = 0; value is String && i < 2; i++) {
        value = jsonDecode(value);
      }
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (_) {
      return null;
    }
  }

  static String cookieFingerprint(List<Object?> cookies, String url) {
    final host = Uri.parse(url).host;
    final scoped =
        cookies
            .whereType<Map>()
            .where((cookie) {
              final domain = '${cookie['domain'] ?? ''}';
              final bare = domain.replaceFirst(RegExp(r'^\.'), '');
              return host == bare ||
                  (domain.startsWith('.') && host.endsWith('.$bare'));
            })
            .map(
              (cookie) => jsonEncode([
                cookie['domain'],
                cookie['path'],
                cookie['name'],
                cookie['value'],
              ]),
            )
            .toList()
          ..sort();
    return jsonEncode(scoped);
  }

  static bool passed(
    Map before,
    Map now, {
    required String target,
    required bool cookieChanged,
  }) {
    final page = Uri.tryParse('${now['url'] ?? ''}');
    if (page == null ||
        !['http', 'https'].contains(page.scheme) ||
        page.host.isEmpty ||
        page.origin != Uri.parse(target).origin ||
        now['heavy'] == true ||
        now['retry'] == true ||
        now['ready'] != true ||
        now['business'] != true) {
      return false;
    }
    final changedUrl = now['url'] != before['url'];
    if (now['blocking'] == true &&
        now['token'] != true &&
        now['success'] != true) {
      return false;
    }
    final iframeLeft =
        (before['verificationFrames'] as List? ?? []).isNotEmpty &&
        (now['verificationFrames'] as List? ?? []).isEmpty;
    final restored = before['business'] != true;
    if (before['kind'] == 'unknown') return changedUrl || restored;
    String storage(Object? value) {
      final entries = value is Map ? value.entries.toList() : <MapEntry>[];
      entries.sort((a, b) => '${a.key}'.compareTo('${b.key}'));
      return jsonEncode(Map.fromEntries(entries));
    }

    final storageChanged = [
      'localStorage',
      'sessionStorage',
    ].any((area) => storage(now[area]) != storage(before[area]));
    return (now['blocking'] != true ||
            now['token'] == true ||
            now['success'] == true) &&
        (changedUrl ||
            iframeLeft ||
            cookieChanged ||
            storageChanged ||
            now['token'] == true ||
            now['success'] == true);
  }
}
