import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;

/// Stream-copy remuxing: no re-encoding and no media bytes on the method channel.
///
/// iOS 用内嵌的 FFmpeg（ffmpeg_kit_flutter_new，含 crypto 协议）直接合并 AES-128
/// HLS。原生 Aether 库缺 mp4/mov muxer，已废弃。桌面仍用系统 ffmpeg。
class VideoDownloadMerger {
  final _processes = <String, Process>{};
  final _ffmpegSessions = <String, FFmpegSession>{};
  final _cancelled = <String>{};

  Future<void> merge(Directory directory, File output, String id) async {
    _cancelled.remove(id);
    if (Platform.isIOS) {
      await _mergeIOS(directory, output, id);
      return;
    }
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      throw UnsupportedError('当前平台尚未提供视频合并');
    }
    // Desktop builds can use an installed FFmpeg. iOS uses its bundled libraries.
    final process = await Process.start('ffmpeg', [
      '-hide_banner',
      '-loglevel',
      'error',
      '-nostdin',
      '-y',
      '-protocol_whitelist',
      'file,crypto,data',
      '-allowed_extensions',
      'ALL',
      '-extension_picky',
      '0',
      '-i',
      p.join(directory.path, 'index.m3u8'),
      '-map',
      '0:v:0',
      '-map',
      '0:a?',
      '-c',
      'copy',
      '-avoid_negative_ts',
      'make_zero',
      '-movflags',
      '+faststart',
      '-f',
      'mp4',
      output.path,
    ]);
    _processes[id] = process;
    if (_cancelled.contains(id)) process.kill();
    // Drain diagnostics without retaining site paths or unbounded output.
    final errors = process.stderr.drain<void>();
    final stdout = process.stdout.drain<void>();
    try {
      final code = await process.exitCode;
      await Future.wait([errors, stdout]);
      if (code != 0) throw StateError('MP4 合并失败，原始分片已保留（$code）');
    } finally {
      _processes.remove(id);
      _cancelled.remove(id);
    }
  }

  /// iOS 合并：使用内嵌 FFmpeg（ffmpeg_kit_flutter_new，含 crypto 协议）直接合并 AES-128
  /// HLS。原生 Aether 库缺 mp4/mov muxer，已完全废弃，不再回退。
  ///
  /// 必须用 `executeWithArguments`（而非 `execute(String)`）：后者按空格重新拆分命令串，
  /// iOS 容器路径常含空格（如 `Library/Application Support/...`），会被拆坏导致
  /// `No such file or directory`。参数数组原样传给原生层即可。
  Future<void> _mergeIOS(Directory directory, File output, String id) async {
    final args = [
      '-hide_banner',
      '-loglevel',
      'error',
      '-nostdin',
      '-y',
      '-protocol_whitelist',
      'file,crypto,data',
      '-allowed_extensions',
      'ALL',
      '-i',
      p.join(directory.path, 'index.m3u8'),
      '-map',
      '0:v:0',
      '-map',
      '0:a?',
      '-c:v',
      'copy',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-avoid_negative_ts',
      'make_zero',
      '-movflags',
      '+faststart',
      '-f',
      'mp4',
      output.path,
    ];
    final session = await FFmpegKit.executeWithArguments(args);
    _ffmpegSessions[id] = session;
    final rc = await session.getReturnCode();
    _ffmpegSessions.remove(id);
    if (ReturnCode.isSuccess(rc)) return;
    if (_cancelled.contains(id)) throw StateError('合并已暂停');
    final logs = (await session.getAllLogsAsString())?.trim() ?? '';
    throw StateError('MP4 合并失败，原始分片已保留（${rc?.getValue() ?? '?'}）${logs.isNotEmpty ? '：$logs' : ''}');
  }

  Future<void> cancel(String id) async {
    if (Platform.isIOS) {
      _cancelled.add(id);
      final session = _ffmpegSessions.remove(id);
      if (session != null) {
        await FFmpegKit.cancel(session.getSessionId());
      }
      return;
    }
    _cancelled.add(id);
    _processes[id]?.kill();
  }
}
