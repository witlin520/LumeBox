import '../reading/reading_identity.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../reading/reading.dart';
import '../util/lume_log.dart';
import 'bangumi_client.dart';

/// Bangumi 账号与非敏感偏好。令牌优先放系统钥匙串；钥匙串不可用的平台
/// （Android / Windows / 测试环境）退回应用支持目录里的本地文件。
class BangumiSettings extends ChangeNotifier {
  static final instance = BangumiSettings();
  static const MethodChannel channel = MethodChannel('lumebox/speech');

  bool autoSync = true;
  String username = '';
  int userId = 0;
  String? _token;
  bool _loaded = false;

  Future<File> get _file async =>
      File('${(await getApplicationSupportDirectory()).path}/bangumi.json');

  Future<File> get _tokenFile async =>
      File('${(await getApplicationSupportDirectory()).path}/bangumi.token');

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file;
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return;
      autoSync = data['autoSync'] != false;
      username = data['username'] is String ? data['username'] as String : '';
      userId = data['userId'] is num ? (data['userId'] as num).toInt() : 0;
      notifyListeners();
    } catch (error) {
      LumeLog.warn('[bangumi] 读取设置失败：$error');
    }
  }

  Future<void> save() async {
    try {
      final file = await _file;
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'autoSync': autoSync,
          'username': username,
          'userId': userId,
        }),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (error) {
      LumeLog.warn('[bangumi] 保存设置失败：$error');
    }
  }

  Future<String> token() async {
    if (_token != null) return _token!;
    try {
      final raw = await channel.invokeMethod<String>('speechGetKey', {
        'kind': 'bangumi',
      });
      if (raw != null && raw.isNotEmpty) return _token = raw;
    } on MissingPluginException {
      // 非 iOS：用本地文件。
    } catch (error) {
      LumeLog.warn('[bangumi] 读取钥匙串失败：$error');
    }
    try {
      final file = await _tokenFile;
      if (await file.exists()) {
        _token = (await file.readAsString()).trim();
      }
    } catch (error) {
      LumeLog.warn('[bangumi] 读取本地令牌失败：$error');
    }
    return _token ?? '';
  }

  Future<void> setToken(String value) async {
    _token = value.trim();
    var stored = false;
    try {
      await channel.invokeMethod<void>('speechSetKey', {
        'kind': 'bangumi',
        'key': _token,
      });
      stored = true;
    } on MissingPluginException {
      // 非 iOS：落本地文件。
    } catch (error) {
      LumeLog.warn('[bangumi] 钥匙串不可用，改用本地文件：$error');
    }
    if (stored) return;
    try {
      final file = await _tokenFile;
      await file.parent.create(recursive: true);
      if (_token!.isEmpty) {
        if (await file.exists()) await file.delete();
      } else {
        await file.writeAsString(_token!, flush: true);
      }
    } catch (error) {
      LumeLog.warn('[bangumi] 保存本地令牌失败：$error');
    }
  }

  /// 退出账号：清掉令牌与用户名；自动同步偏好保留。
  Future<void> signOut() async {
    await setToken('');
    username = '';
    userId = 0;
    notifyListeners();
    await save();
  }
}

/// 本地条目 ↔ Bangumi 条目的绑定。章节 ID 缓存下来，进度同步时不必每次
/// 重新拉整季章节；章节列表变化时由用户重新绑定。
class BangumiBinding {
  const BangumiBinding({
    required this.subjectId,
    required this.name,
    this.episodes = const <int>[],
  });

  final int subjectId;
  final String name;
  final List<int> episodes;

  static String keyFor(String itemId, {String sourceId = ''}) =>
      'bangumi.binding.${sourceId.isEmpty ? itemId : ReadingIdentity.key(sourceId, itemId)}';

  BangumiBinding withEpisodes(List<int> value) =>
      BangumiBinding(subjectId: subjectId, name: name, episodes: value);

  String encode() =>
      jsonEncode({'subjectId': subjectId, 'name': name, 'episodes': episodes});

  static BangumiBinding? decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final subjectId = data['subjectId'];
      if (subjectId is! num) return null;
      final episodes = <int>[];
      final saved = data['episodes'];
      if (saved is List) {
        for (final id in saved) {
          if (id is num) episodes.add(id.toInt());
        }
      }
      return BangumiBinding(
        subjectId: subjectId.toInt(),
        name: '${data['name'] ?? ''}',
        episodes: episodes,
      );
    } catch (_) {
      return null;
    }
  }
}

/// 播放进度 → Bangumi。失败只记日志，绝不把异常抛回播放链路。
class BangumiSyncService {
  BangumiSyncService({
    BangumiSettings? settings,
    BangumiClient Function(String token)? clientFactory,
  }) : settings = settings ?? BangumiSettings.instance,
       _clientFactory = clientFactory ?? ((token) => BangumiClient(token));

  static final instance = BangumiSyncService();

  final BangumiSettings settings;
  final BangumiClient Function(String token) _clientFactory;
  final Map<String, int> _lastChapter = <String, int>{};
  final Map<String, DateTime> _lastAttempt = <String, DateTime>{};

  Future<void> afterProgress(
    ReadingLibrary library,
    VideoProgress progress, {
    bool force = false,
  }) async {
    try {
      await settings.load();
      // 手动同步（force）不受自动同步开关限制；开关只控制播放中的自动写入。
      if (!settings.autoSync && !force) return;
      if (!force) {
        final last =
            _lastAttempt[ReadingIdentity.key(
              progress.sourceId,
              progress.itemId,
            )];
        if (last != null &&
            DateTime.now().difference(last) < const Duration(seconds: 10)) {
          return;
        }
        if (_lastChapter[ReadingIdentity.key(
              progress.sourceId,
              progress.itemId,
            )] ==
            progress.chapterIndex) {
          return;
        }
      }
      final token = await settings.token();
      if (token.isEmpty) return;
      final binding = BangumiBinding.decode(
        library.setting(
          library.itemSettingKey(
            'bangumi.binding.',
            progress.sourceId.isEmpty
                ? progress.itemId
                : ReadingIdentity.key(progress.sourceId, progress.itemId),
          ),
        ),
      );
      if (binding == null) return;
      _lastAttempt[ReadingIdentity.key(progress.sourceId, progress.itemId)] =
          DateTime.now();
      final client = _clientFactory(token);
      try {
        var episodes = binding.episodes;
        if (episodes.isEmpty) {
          final list = await client.episodes(binding.subjectId);
          episodes = [for (final episode in list) episode.id];
          if (episodes.isNotEmpty) {
            library.setSetting(
              BangumiBinding.keyFor(
                progress.itemId,
                sourceId: progress.sourceId,
              ),
              binding.withEpisodes(episodes).encode(),
            );
          }
        }
        final watched = episodes.isEmpty
            ? 0
            : (progress.chapterIndex + 1).clamp(0, episodes.length);
        await client.markEpisodes(
          binding.subjectId,
          episodes.take(watched).toList(),
        );
        final finished =
            episodes.isNotEmpty &&
            watched >= episodes.length &&
            progress.isFinished;
        await client.updateCollection(binding.subjectId, finished ? 2 : 3);
        _lastChapter[ReadingIdentity.key(progress.sourceId, progress.itemId)] =
            progress.chapterIndex;
      } finally {
        client.close();
      }
    } catch (error, stackTrace) {
      LumeLog.warn('[bangumi] 同步进度失败：$error');
      LumeLog.error(error, stackTrace);
    }
  }

  /// 重新绑定 / 解绑后清掉节流状态，下一次进度写入立即同步。
  void forget(String itemId, {String sourceId = ''}) {
    itemId = ReadingIdentity.key(sourceId, itemId);
    _lastChapter.remove(itemId);
    _lastAttempt.remove(itemId);
  }
}
