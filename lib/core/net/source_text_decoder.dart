import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class SourceTextDecoder {
  static Future<String?> decode(
    List<int> bytes,
    Map<String, String> headers,
  ) async {
    final contentType =
        headers.entries
            .where((e) => e.key.toLowerCase() == 'content-type')
            .firstOrNull
            ?.value ??
        '';
    if (bytes.length > 8 * 1024 * 1024 ||
        (contentType.isNotEmpty &&
            !RegExp(
              r'text|json|xml|javascript|mpegurl',
              caseSensitive: false,
            ).hasMatch(contentType))) {
      return null;
    }
    if (bytes.length >= 2 &&
        ((bytes[0] == 255 && bytes[1] == 254) ||
            (bytes[0] == 254 && bytes[1] == 255))) {
      final little = bytes[0] == 255;
      return String.fromCharCodes([
        for (var i = 2; i + 1 < bytes.length; i += 2)
          little
              ? bytes[i] | (bytes[i + 1] << 8)
              : (bytes[i] << 8) | bytes[i + 1],
      ]);
    }
    final prefix = latin1.decode(bytes.take(4096).toList());
    final charset = RegExp(
      "charset\\s*=\\s*[\"']?([a-zA-Z0-9_-]+)",
      caseSensitive: false,
    ).firstMatch('$contentType $prefix')?.group(1)?.toLowerCase();
    if (charset == null || ['utf-8', 'utf8'].contains(charset)) {
      try {
        return utf8.decode(bytes);
      } on FormatException {
        /* Detect legacy below. */
      }
    }
    if (['iso-8859-1', 'latin1'].contains(charset)) return latin1.decode(bytes);
    if (Platform.isIOS) {
      return const MethodChannel('lumebox/source_web').invokeMethod<String>(
        'decodeText',
        {'body': base64Encode(bytes), 'charset': charset ?? 'gb18030'},
      );
    }
    return null;
  }
}
