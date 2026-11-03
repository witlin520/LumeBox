import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Per-playback diagnostics. Never stores request headers, credentials or query
/// strings; bounded independently from the app-wide in-memory log.
class PlaybackLogs {
  PlaybackLogs(this.directory);
  final Directory directory;
  static const maxFiles = 20;
  static const maxTotalBytes = 50 * 1024 * 1024;
  static const maxFileBytes = 2 * 1024 * 1024;
  static Future<PlaybackLogs> open() async => PlaybackLogs(
    Directory(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'reference_playback_logs',
      ),
    ),
  );
  List<File> files(String kernel) {
    if (!directory.existsSync()) return [];
    final pattern = RegExp('^${RegExp.escape(kernel)}-[0-9]+\\.log\$');
    return directory
        .listSync()
        .whereType<File>()
        .where((file) => pattern.hasMatch(p.basename(file.path)))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }

  int bytes(String kernel) =>
      files(kernel).fold(0, (sum, file) => sum + file.lengthSync());
  PlaybackLogSession start(String kernel, Uri uri) {
    directory.createSync(recursive: true);
    final file = File(
      p.join(
        directory.path,
        '$kernel-${DateTime.now().microsecondsSinceEpoch}.log',
      ),
    );
    file.createSync();
    prune(kernel);
    final session = PlaybackLogSession(file);
    session.write('OPEN $kernel ${safeUri(uri)}');
    return session;
  }

  void prune(String kernel) {
    var total = 0;
    final entries = files(kernel);
    for (var index = 0; index < entries.length; index++) {
      final file = entries[index];
      total += file.lengthSync();
      if (index >= maxFiles || total > maxTotalBytes) file.deleteSync();
    }
  }

  void clear(String kernel) {
    for (final file in files(kernel)) {
      file.deleteSync();
    }
  }

  Uint8List zip(String kernel) {
    final archive = Archive();
    for (final file in files(kernel)) {
      final data = file.readAsBytesSync();
      archive.addFile(ArchiveFile(p.basename(file.path), data.length, data));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String safeUri(Uri uri) => uri.hasAuthority
      ? '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}'
      : '${uri.scheme}://${p.basename(uri.path)}';
  static String redact(String value) => value
      .replaceAllMapped(RegExp(r'https?://[^\s\]<>]+'), (match) {
        final uri = Uri.tryParse(match[0]!);
        return uri == null ? '[address]' : safeUri(uri);
      })
      .replaceAll(
        RegExp(
          r'(authorization|password|token|secret|appkey|apikey)\s*[:=]\s*\S+',
          caseSensitive: false,
        ),
        '[credential redacted]',
      );
}

class PlaybackLogSession {
  PlaybackLogSession(this.file);
  final File file;
  DateTime? _lastSnapshot;
  bool _closed = false;
  void write(String message) {
    if (_closed || !file.existsSync()) return;
    final line =
        '${DateTime.now().toIso8601String()} ${PlaybackLogs.redact(message)}\n';
    if (file.lengthSync() + utf8.encode(line).length >
        PlaybackLogs.maxFileBytes) {
      return;
    }
    file.writeAsStringSync(line, mode: FileMode.append);
  }

  void snapshot({
    required int positionMs,
    required bool playing,
    required bool buffering,
    String? error,
  }) {
    final now = DateTime.now();
    if (error == null &&
        _lastSnapshot != null &&
        now.difference(_lastSnapshot!) < const Duration(seconds: 1)) {
      return;
    }
    _lastSnapshot = now;
    write(
      'STATE positionMs=$positionMs playing=$playing buffering=$buffering'
      '${error == null ? '' : ' error=$error'}',
    );
  }

  void close() {
    write('CLOSE');
    _closed = true;
  }
}
