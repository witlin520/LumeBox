import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../cat/cat_service.dart';

/// Portable Node source programs and collection metadata; account profiles stay in Keychain.
abstract final class CatConfigurationBackup {
  static Map<String, dynamic> validate(Object? raw) {
    if (raw is! Map ||
        raw['subscriptions'] is! List ||
        raw['bundles'] is! Map) {
      throw const FormatException('猫源备份结构无效');
    }
    final data = Map<String, dynamic>.from(raw);
    final ids = <String>{};
    for (final row in data['subscriptions'] as List) {
      if (row is! Map ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch('${row['id']}') ||
          !ids.add('${row['id']}')) {
        throw const FormatException('猫源订阅身份无效');
      }
      final record = CatSubscription.fromJson(Map<String, dynamic>.from(row));
      final url = Uri.tryParse(record.url);
      if (!(record.isLocal && record.url == 'local:${record.id}') &&
          (url == null ||
              !['http', 'https'].contains(url.scheme) ||
              url.host.isEmpty)) {
        throw const FormatException('猫源订阅地址无效');
      }
      final bundle = (data['bundles'] as Map)[record.id];
      if (record.isLocal && bundle == null) {
        throw const FormatException('本地猫源备份缺少程序包');
      }
      if (bundle == null) continue;
      if (bundle is! Map ||
          bundle['index'] is! String ||
          bundle['config'] is! String ||
          (bundle['index'] as String).length > 28 * 1024 * 1024 ||
          (bundle['config'] as String).length > 3 * 1024 * 1024 ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(record.hash) ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(record.configHash)) {
        throw const FormatException('猫源程序包格式无效');
      }
      final index = base64Decode(bundle['index'] as String),
          config = base64Decode(bundle['config'] as String);
      if (index.isEmpty ||
          config.isEmpty ||
          index.length > 20 * 1024 * 1024 ||
          config.length > 2 * 1024 * 1024 ||
          md5.convert(index).toString() != record.hash ||
          md5.convert(config).toString() != record.configHash) {
        throw const FormatException('猫源程序包校验失败');
      }
    }
    if ((data['bundles'] as Map).keys.any((key) => !ids.contains(key))) {
      throw const FormatException('猫源程序包没有对应订阅');
    }
    for (final name in ['history', 'bookmarks']) {
      if (data[name] is! List) throw const FormatException('猫源收藏或历史格式无效');
      for (final row in data[name] as List) {
        if (row is! Map ||
            row['id'] is! String ||
            row['site'] is! String ||
            row['title'] is! String ||
            row['time'] != null && row['time'] is! num) {
          throw const FormatException('猫源作品身份无效');
        }
      }
    }
    if (data['favorites'] is! List ||
        (data['favorites'] as List).any((v) => v is! String) ||
        data['siteColumns'] != null && ![1, 2].contains(data['siteColumns'])) {
      throw const FormatException('猫源收藏配置无效');
    }
    return data;
  }

  static Future<Map<String, dynamic>> export(
    Directory base,
    List<String> warnings,
  ) async {
    final file = File('${base.path}/sections/cat/node/subscriptions.json');
    final empty = <String, dynamic>{
      'subscriptions': [],
      'bundles': {},
      'favorites': [],
      'history': [],
      'bookmarks': [],
      'siteColumns': 1,
    };
    if (!await file.exists()) return empty;
    try {
      final raw = jsonDecode(await file.readAsString()) as Map;
      final subscriptions = <Map<String, dynamic>>[];
      final bundles = <String, Map<String, String>>{};
      for (final row in catMaps(raw['subscriptions'])) {
        final record = CatSubscription.fromJson(row);
        if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(record.id)) {
          throw const FormatException('invalid source ID');
        }
        if (RegExp(r'^[a-f0-9]{32}$').hasMatch(record.hash) &&
            RegExp(r'^[a-f0-9]{32}$').hasMatch(record.configHash)) {
          final path =
              '${file.parent.path}/bundles/${record.id}/${record.hash}-${record.configHash}';
          final index = File('$path/index.js'),
              config = File('$path/index.config.js');
          if (await index.exists() &&
              await config.exists() &&
              await index.length() <= 20 * 1024 * 1024 &&
              await config.length() <= 2 * 1024 * 1024) {
            bundles[record.id] = {
              'index': base64Encode(await index.readAsBytes()),
              'config': base64Encode(await config.readAsBytes()),
            };
          }
        }
        if (record.isLocal && !bundles.containsKey(record.id)) {
          warnings.add('本地猫源「${record.name}」程序包缺失，已跳过该源');
          continue;
        }
        subscriptions.add(record.toJson());
      }
      Map<String, dynamic> item(Map<String, dynamic> row) => {
        'id': catText(row['id']),
        'site': catText(row['site']),
        'title': catText(row['title']),
        if (row['cover'] is String) 'cover': row['cover'],
        if (row['subtitle'] is String) 'subtitle': row['subtitle'],
        if (row['time'] is num) 'time': row['time'],
      };
      return validate({
        'subscriptions': subscriptions,
        'bundles': bundles,
        'favorites': (raw['favorites'] as List? ?? [])
            .whereType<String>()
            .toList(),
        'history': catMaps(raw['history']).map(item).toList(),
        'bookmarks': catMaps(raw['bookmarks']).map(item).toList(),
        'siteColumns': raw['siteColumns'] ?? 1,
      });
    } catch (_) {
      warnings.add('猫源订阅或程序包损坏，已跳过；其他板块仍已备份');
      return empty;
    }
  }

  static Future<void> restore(
    CatService service,
    Map<String, dynamic> data,
  ) async {
    await service.restoreBackupState(
      catMaps(data['subscriptions']).map(CatSubscription.fromJson).toList(),
      favorites: (data['favorites'] as List).cast<String>(),
      history: catMaps(data['history']),
      bookmarks: catMaps(data['bookmarks']),
      siteColumns: data['siteColumns'] as int? ?? 1,
      bundles: {
        for (final e in (data['bundles'] as Map).entries)
          '${e.key}': (
            base64Decode(e.value['index'] as String),
            base64Decode(e.value['config'] as String),
          ),
      },
    );
  }
}
