import 'source_extension_settings.dart';

/// App-owned definitions and merge rules. Source JSON can supply supported
/// options/default suggestions, but never change the host's field type/title,
/// operation binding, hard limits or reserved configuration fields.
class SourceSettingsPolicy {
  const SourceSettingsPolicy._();
  static const apiVersion = 2;
  static const features = {
    'commonSettings',
    'settingsActions',
    'actionInputs',
    'settingsGroups',
    'resourceRoutes',
  };
  static const _reserved = {
    'domain',
    'mirrors',
    'mirrorIndex',
    'customDomain',
    'imageDomain',
    'imageMirrors',
    'videoDomain',
    'videoMirrors',
    'account',
    'password',
    'cookie',
    'proxy',
    'userAgent',
    'allowBadCertificate',
    'bridge',
    'capabilities',
    'commonSettings',
    'sourceSettings',
    'settingsApiVersion',
  };
  static bool reserved(String key) =>
      key.startsWith('app_') || _reserved.contains(key);
  static const titles = {
    'quality': '默认画质',
    'imageQuality': '图片质量',
    'playbackMode': '播放方式',
    'searchMode': '搜索方式',
    'pageSize': '每页数量',
    'autoNext': '自动翻页',
  };
  static const hostActions = [
    SourceSetting(
      key: 'app_openWebsite',
      title: '打开当前站点',
      type: 'action',
      action: 'openWebsite',
      appOwned: true,
    ),
    SourceSetting(
      key: 'app_testConnection',
      title: '测试源连接',
      type: 'action',
      action: 'testConnection',
      description: '使用已保存的线路与设置',
      appOwned: true,
    ),
    SourceSetting(
      key: 'app_clearCache',
      title: '清理源浏览缓存',
      type: 'action',
      action: 'clearCache',
      appOwned: true,
    ),
  ];

  static void validateProtocol(Object? version, Object? requirements) {
    if (version != null &&
        (version is! int || version < 1 || version > apiVersion)) {
      throw const SourceSettingsFormatException(
        '扩展设置版本不受支持，请升级 App 或检查 settingsApiVersion',
      );
    }
    if (requirements == null) return;
    if (requirements is! List ||
        requirements.length > features.length ||
        requirements.any((v) => v is! String || !features.contains(v))) {
      throw const SourceSettingsFormatException('源要求了当前 App 不支持的设置能力');
    }
  }

  /// 源扩展功能里实际展示的项。
  ///
  /// 宿主已有入口的不重复展示：`login`（站点账号里统一登录）、`clearCache`（源设置底部）；
  /// `openWebsite` 只有源带了 `url`（例如「打开发布页」）时才展示——不带 url 的等价于
  /// 「打开当前站点」，宿主本来就提供。
  static List<SourceSetting> visibleExtensions(
    List<SourceSetting> fields, {
    bool embedded = true,
  }) {
    if (!embedded) return fields;
    return fields.where((field) {
      if (field.action == 'login' || field.action == 'clearCache') return false;
      if (field.action == 'openWebsite' && field.url.isEmpty) return false;
      return true;
    }).toList(growable: false);
  }

  static List<SourceSetting> parseCommon(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List || raw.length > titles.length) {
      throw const SourceSettingsFormatException('通用设置声明无效');
    }
    final result = <SourceSetting>[], seen = <String>{};
    for (final item in raw) {
      if (item is! Map ||
          !titles.containsKey(item['key']) ||
          !seen.add('${item['key']}')) {
        throw const SourceSettingsFormatException('通用设置未知或重复');
      }
      final key = item['key'] as String;
      final String type;
      final options = <String, String>{};
      Object fallback;
      num? min, max;
      if (key == 'autoNext') {
        type = 'toggle';
        fallback = false;
      } else if (key == 'pageSize') {
        type = 'number';
        fallback = 20;
        min = 1;
        max = 200;
        if (item['min'] is num && (item['min'] as num).isFinite) {
          min = (item['min'] as num).clamp(1, 200);
        }
        if (item['max'] is num && (item['max'] as num).isFinite) {
          max = (item['max'] as num).clamp(1, 200);
        }
        min = min.ceil();
        max = max.floor();
        if (min > max) throw const SourceSettingsFormatException('每页数量范围无效');
        fallback = (fallback as num).clamp(min, max);
      } else {
        type = 'select';
        fallback = 'auto';
        options['auto'] = '自动';
        if (key == 'playbackMode') {
          options.addAll({'native': '原生播放', 'webpage': '网页播放'});
        }
        final proposed = item['options'];
        if (proposed != null) {
          final parsed = SourceSetting.parseAll([
            {
              'key': key,
              'title': titles[key],
              'type': 'select',
              'options': proposed,
            },
          ]).single;
          if (key == 'playbackMode') {
            final supported = parsed.options.keys.toSet()..add('auto');
            options.removeWhere((k, v) => !supported.contains(k));
          } else {
            options.addAll(parsed.options);
            options['auto'] = '自动';
          }
        }
      }
      final validator = SourceSetting(
        key: key,
        title: titles[key]!,
        type: type,
        defaultValue: fallback,
        options: options,
        minValue: min,
        maxValue: max,
        appOwned: true,
        integerOnly: key == 'pageSize',
      );
      final proposed = item['default'];
      final selected =
          item.containsKey('default') && validator.valueIssue(proposed) == null
          ? proposed
          : fallback;
      result.add(
        SourceSetting(
          key: key,
          title: titles[key]!,
          type: type,
          defaultValue: selected,
          options: Map.unmodifiable(options),
          minValue: min,
          maxValue: max,
          appOwned: true,
          integerOnly: key == 'pageSize',
        ),
      );
    }
    return List.unmodifiable(result);
  }

  static List<SourceSetting> sourceFields(
    List<SourceSetting> common,
    List<SourceSetting> extensions,
  ) {
    final owned = common.map((f) => f.key).toSet();
    return List.unmodifiable(
      extensions.where((f) => !reserved(f.key) && !owned.contains(f.key)),
    );
  }

  static Map<String, Object?> resolve(
    List<SourceSetting> definitions,
    Map<String, Object?> userValues, {
    Map<String, Object?> appRules = const {},
  }) => {
    for (final f in definitions)
      if (!{'info', 'action'}.contains(f.type))
        f.key:
            appRules.containsKey(f.key) && f.valueIssue(appRules[f.key]) == null
            ? appRules[f.key]
            : userValues.containsKey(f.key) &&
                  f.valueIssue(userValues[f.key]) == null
            ? userValues[f.key]
            : f.fallback,
  };
}
