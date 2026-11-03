import 'builtin_danmaku_service.dart';
import 'danmaku_presets.dart';

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class DandanplayCredentials {
  const DandanplayCredentials(
    this.appId,
    this.appSecret, {
    this.baseUrl = defaultBase,
  });
  static const defaultBase = BuiltinDanmakuService.address;
  static const officialBase = 'https://api.dandanplay.net';
  static const builtinBase = BuiltinDanmakuService.address;
  bool get builtin => baseUrl == builtinBase;
  final String baseUrl;
  final String appId;
  final String appSecret;
  bool get official => isOfficial(Uri.tryParse(baseUrl.trim()));
  bool get configured => appId.trim().isNotEmpty && appSecret.trim().isNotEmpty;

  static bool isOfficial(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'api.dandanplay.net' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty;

  static Future<DandanplayCredentials> load() async {
    final value = await DanmakuSourcesStore.read();
    return DandanplayCredentials(
      value['appId'] ?? '',
      value['appSecret'] ?? '',
      baseUrl: value['baseUrl'] ?? defaultBase,
    );
  }

  Future<void> save() => DanmakuSourcesStore.saveCredentials(this);
}

/// Both players and settings use the same device-only native credential store.
/// The old iOS single-service item is read only when no profile has been saved.
class DanmakuSourcesStore {
  static final revision = ValueNotifier<int>(0);
  static const channel = MethodChannel('lumebox/reference_danmaku_credentials');
  static const _legacy = MethodChannel('lumebox/danmaku_credentials');

  static Future<Map<String, String>> read() async {
    Map<String, String>? data;
    try {
      data = await channel.invokeMapMethod<String, String>('read');
    } on MissingPluginException {
      // Older hosts only registered the single-service channel.
    }
    if (data == null || data.isEmpty) {
      try {
        data = await _legacy.invokeMapMethod<String, String>('read');
      } on MissingPluginException {
        return {};
      }
    }
    if (data == null) return {};
    if (!data.containsKey('profilesJson')) {
      if (!DanmakuPresets.retiredUrls.contains(data['baseUrl'])) return data;
      return {
        ...data,
        'baseUrl': DandanplayCredentials.builtinBase,
        'appId': '',
        'appSecret': '',
      };
    }
    final all = profiles(data);
    final sources = all
        .where((source) => !DanmakuPresets.retired(source))
        .toList();
    if (sources.length != all.length) {
      final active =
          sources.where((s) => s['id'] == data!['activeId']).firstOrNull ??
          sources.where((s) => s['type'] != 'builtin').firstOrNull ??
          sources.firstOrNull;
      data = {
        ...data,
        'profilesJson': jsonEncode(sources),
        'activeId': active?['id'] ?? '',
        'baseUrl': active?['url'] ?? DandanplayCredentials.builtinBase,
      };
      await channel.invokeMethod<void>('write', data);
    }
    final selected = sources
        .where((s) => s['id'] == data!['activeId'])
        .firstOrNull;
    return {
      ...data,
      'baseUrl': selected?['url'] ?? DandanplayCredentials.defaultBase,
      'appId': selected?['appId'] ?? '',
      'appSecret': selected?['appSecret'] ?? '',
    };
  }

  static List<Map<String, String>> profiles(Map<String, String> data) {
    final raw = jsonDecode(data['profilesJson'] ?? '[]');
    if (raw is! List) return [];
    return [
      for (final row in raw)
        if (row is Map)
          {
            for (final entry in row.entries)
              if (entry.key is String && entry.value is String)
                entry.key as String: entry.value as String,
          },
    ];
  }

  static Future<void> save(
    List<Map<String, String>> sources,
    String active,
  ) async {
    sources = sources
        .where((s) => !DanmakuPresets.retired(s))
        .where((s) => s['type'] != 'builtin' || s['id'] == active)
        .toList();
    final selected = sources.where((s) => s['id'] == active).firstOrNull;
    await channel.invokeMethod<void>('write', {
      'profilesJson': jsonEncode(sources),
      'activeId': active,
      'baseUrl': selected?['url'] ?? DandanplayCredentials.defaultBase,
      'appId': selected?['appId'] ?? '',
      'appSecret': selected?['appSecret'] ?? '',
    });
    revision.value++;
    if (selected?['url'] != DandanplayCredentials.builtinBase) {
      await BuiltinDanmakuService.instance.stop();
    }
  }

  static Future<void> saveCredentials(DandanplayCredentials config) async {
    final data = await read();
    final sources = profiles(data);
    if (config.builtin) {
      await save([
        ...sources.where((s) => s['type'] != 'builtin'),
        {
          'id': 'builtin-local',
          'name': '内置本机服务',
          'type': 'builtin',
          'url': DandanplayCredentials.builtinBase,
        },
      ], 'builtin-local');
      return;
    }
    final base = config.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    // 同一个地址可能保存了多个 AppSecret（密钥 1 / 密钥 2）。更新时优先
    // 更新“当前正在使用”的那条，而不是永远命中列表里的第一条。
    final activeId = data['activeId'] ?? '';
    final active = sources.where((s) => s['id'] == activeId).firstOrNull;
    final existing = (active != null && active['url'] == base)
        ? active
        : sources.where((s) => s['url'] == base).firstOrNull;
    final id =
        existing?['id'] ?? 'service-${DateTime.now().microsecondsSinceEpoch}';
    final next = {
      'id': id,
      'name':
          existing?['name'] ??
          (config.official ? '弹弹play 开放平台' : Uri.parse(base).host),
      'type': config.official ? 'official' : 'logvar',
      'url': base,
      'appId': config.appId.trim(),
      'appSecret': config.appSecret.trim(),
    };
    await save([
      for (final source in sources)
        if (source['id'] != id) source,
      next,
    ], id);
  }
}
