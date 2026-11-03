class SourceSettingsFormatException extends FormatException {
  const SourceSettingsFormatException(super.message);
}

/// Declarative settings and explicitly interchangeable URL bases from a source.
/// No source-provided widget code or JavaScript is evaluated by the settings UI.
class SourceSetting {
  const SourceSetting({
    required this.key,
    required this.title,
    required this.type,
    this.description = '',
    this.defaultValue,
    this.options = const {},
    this.action = 'source',
    this.url = '',
    this.group = '',
    this.placeholder = '',
    this.minValue,
    this.maxValue,
    this.maxLength = 4096,
    this.inputs = const [],
    this.appOwned = false,
    this.requiredValue = false,
    this.integerOnly = false,
  });
  final String key, title, type, description, action, group, placeholder;

  /// 操作按钮的目标网址（目前只给 `action: openWebsite` 用：填了就打开它，
  /// 不填仍打开源当前站点）。仅接受 http(s)。
  final String url;
  final num? minValue, maxValue;
  final int maxLength;
  final List<SourceSetting> inputs;
  final bool appOwned, requiredValue, integerOnly;
  final Object? defaultValue;
  final Map<String, String> options;
  static const types = {'toggle', 'select', 'text', 'number', 'info', 'action'};
  static List<SourceSetting> parseAll(Object? raw, {bool allowActions = true}) {
    if (raw is! List) return const [];
    if (raw.length > 32) {
      throw const SourceSettingsFormatException('源专用设置最多 32 项');
    }
    final result = <SourceSetting>[], keys = <String>{};
    for (final item in raw) {
      if (item is! Map) throw const SourceSettingsFormatException('源设置项必须是对象');
      final key = '${item['key'] ?? ''}',
          type = '${item['type'] ?? ''}',
          title = '${item['title'] ?? ''}';
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(key) ||
          !keys.add(key) ||
          !types.contains(type) ||
          title.trim().isEmpty ||
          title.length > 100) {
        throw const SourceSettingsFormatException('源设置的 key、标题或类型无效');
      }
      if (!allowActions && {'action', 'info'}.contains(type)) {
        throw const SourceSettingsFormatException('操作参数不能包含按钮或说明项');
      }
      final min = item['min'],
          max = item['max'],
          length = item['maxLength'] ?? 4096;
      if (min != null && (min is! num || !min.isFinite) ||
          max != null && (max is! num || !max.isFinite) ||
          min is num && max is num && min > max ||
          length is! int ||
          length < 1 ||
          length > 4096) {
        throw const SourceSettingsFormatException('设置范围或长度限制无效');
      }
      if (item['inputs'] != null &&
          (type != 'action' ||
              !allowActions ||
              item['inputs'] is! List ||
              (item['inputs'] as List).length > 8)) {
        throw const SourceSettingsFormatException('操作最多允许 8 个输入参数');
      }
      final inputs = item['inputs'] == null
          ? const <SourceSetting>[]
          : parseAll(item['inputs'], allowActions: false);
      if (type == 'number' &&
          item['integer'] == true &&
          min is num &&
          max is num &&
          min.ceil() > max.floor()) {
        throw const SourceSettingsFormatException('整数设置的范围内没有有效整数');
      }
      final options = <String, String>{};
      if (type == 'select') {
        final list = item['options'];
        if (list is! List || list.isEmpty || list.length > 50) {
          throw const SourceSettingsFormatException('下拉选项需要 1–50 项');
        }
        for (final entry in list) {
          if (entry is! Map ||
              entry['value'] is! String ||
              entry['title'] is! String ||
              (entry['value'] as String).length > 256 ||
              (entry['title'] as String).length > 100 ||
              options.containsKey(entry['value'])) {
            throw const SourceSettingsFormatException('源下拉选项无效或重复');
          }
          options[entry['value'] as String] = entry['title'] as String;
        }
      }
      final action = '${item['action'] ?? 'source'}';
      final url = '${item['url'] ?? ''}'.trim();
      if (url.isNotEmpty &&
          (url.length > 2048 || !RegExp(r'^https?://', caseSensitive: false).hasMatch(url))) {
        throw const SourceSettingsFormatException('设置里的网址必须是 http(s) 地址');
      }
      if (type == 'action' &&
          !{
            'source',
            'login',
            'openWebsite',
            'testConnection',
            'clearCache',
          }.contains(action)) {
        throw const SourceSettingsFormatException('源设置操作类型无效');
      }
      final field = SourceSetting(
        key: key,
        title: title,
        type: type,
        description: '${item['description'] ?? ''}'.substring(
          0,
          '${item['description'] ?? ''}'.length.clamp(0, 500),
        ),
        defaultValue: item['default'],
        options: Map.unmodifiable(options),
        action: action,
        url: url,
        group: '${item['group'] ?? ''}'.substring(
          0,
          '${item['group'] ?? ''}'.length.clamp(0, 60),
        ),
        placeholder: '${item['placeholder'] ?? ''}'.substring(
          0,
          '${item['placeholder'] ?? ''}'.length.clamp(0, 200),
        ),
        minValue: min as num?,
        maxValue: max as num?,
        maxLength: length,
        inputs: inputs,
        requiredValue: item['required'] == true,
        integerOnly: item['integer'] == true,
      );
      if (item.containsKey('default') &&
          field.valueIssue(item['default']) != null) {
        throw SourceSettingsFormatException('源设置默认值无效：$key');
      }
      result.add(field);
    }
    return List.unmodifiable(result);
  }

  Object? get fallback =>
      defaultValue ??
      switch (type) {
        'toggle' => false,
        'number' => (0).clamp(
          integerOnly
              ? minValue?.ceil() ?? -double.maxFinite
              : minValue ?? -double.maxFinite,
          integerOnly
              ? maxValue?.floor() ?? double.maxFinite
              : maxValue ?? double.maxFinite,
        ),
        'select' => options.keys.first,
        _ => '',
      };
  String? valueIssue(Object? value) => switch (type) {
    'toggle' => value is bool ? null : '请选择开关状态',
    'select' =>
      value is String && options.containsKey(value) ? null : '请选择有效选项',
    'number' =>
      value is! num || !value.isFinite
          ? '请输入有效数字'
          : integerOnly && value % 1 != 0
          ? '请输入整数'
          : minValue != null && value < minValue!
          ? '不能小于 $minValue'
          : maxValue != null && value > maxValue!
          ? '不能大于 $maxValue'
          : null,
    'text' =>
      requiredValue && (value is! String || value.trim().isEmpty)
          ? '此项必填'
          : value is String && value.length <= maxLength
          ? null
          : '输入不能超过 $maxLength 字',
    _ => null,
  };
  Map<String, Object?> toJson() => {
    'key': key,
    'title': title,
    'type': type,
    'description': description,
    if (defaultValue != null) 'default': defaultValue,
    if (options.isNotEmpty)
      'options': [
        for (final o in options.entries) {'value': o.key, 'title': o.value},
      ],
    if (type == 'action') 'action': action,
    if (group.isNotEmpty) 'group': group,
    if (placeholder.isNotEmpty) 'placeholder': placeholder,
    if (minValue != null) 'min': minValue,
    if (maxValue != null) 'max': maxValue,
    if (maxLength != 4096) 'maxLength': maxLength,
    if (requiredValue) 'required': true,
    if (integerOnly) 'integer': true,
    if (inputs.isNotEmpty) 'inputs': inputs.map((f) => f.toJson()).toList(),
  };
}

class SourceRoute {
  const SourceRoute({
    this.urls = const [],
    this.labels = const {},
    this.selected = '',
    this.custom = '',
  });
  final List<String> urls;
  final Map<String, String> labels;
  final String selected, custom;
  String get selectedUrl =>
      urls.contains(selected) ? selected : urls.firstOrNull ?? '';
  String get resolved => normalizeBase(custom) ?? selectedUrl;
  SourceRoute copyWith({String? selected, String? custom}) => SourceRoute(
    urls: urls,
    labels: labels,
    selected: selected ?? this.selected,
    custom: custom ?? this.custom,
  );
  SourceRoute redeclare(SourceRoute declaration) => SourceRoute(
    urls: declaration.urls,
    labels: declaration.labels,
    selected: declaration.urls.contains(selectedUrl)
        ? selectedUrl
        : declaration.urls.firstOrNull ?? '',
    custom: custom,
  );
  static SourceRoute parse(Object? raw) {
    if (raw is! List) return const SourceRoute();
    final urls = <String>[], labels = <String, String>{};
    for (final item in raw) {
      final url = normalizeBase(item is Map ? '${item['url'] ?? ''}' : '$item');
      if (url == null || urls.contains(url)) continue;
      urls.add(url);
      if (item is Map && item['title'] is String) {
        labels[url] = (item['title'] as String).substring(
          0,
          (item['title'] as String).length.clamp(0, 100),
        );
      }
      if (urls.length >= 20) break;
    }
    return SourceRoute(
      urls: List.unmodifiable(urls),
      labels: Map.unmodifiable(labels),
    );
  }

  factory SourceRoute.fromJson(Object? raw) {
    if (raw is! Map) return const SourceRoute();
    final route = SourceRoute.parse(raw['urls']);
    return route.copyWith(
      selected: '${raw['selected'] ?? ''}',
      custom: normalizeBase('${raw['custom'] ?? ''}') ?? '',
    );
  }
  Map<String, Object?> toJson() => {
    'urls': [
      for (final url in urls) {'url': url, 'title': labels[url] ?? url},
    ],
    'selected': selectedUrl,
    'custom': custom,
  };
  int matchLength(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      return -1;
    }
    var score = -1;
    for (final text in urls) {
      final base = Uri.tryParse(text);
      if (base == null || !base.hasAuthority) continue;
      final path = base.path.replaceAll(RegExp(r'/+$'), '');
      if (uri.origin == base.origin &&
          (path.isEmpty || uri.path == path || uri.path.startsWith('$path/')) &&
          path.length > score) {
        score = path.length;
      }
    }
    return score;
  }

  String rewrite(String value) {
    final target = normalizeBase(resolved), uri = Uri.tryParse(value);
    if (target == null ||
        uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      return value;
    }
    // Longest declared prefix wins. Host equality alone must not rewrite a
    // different signed path on a shared CDN host.
    final bases = urls.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final text in bases) {
      final base = Uri.parse(text);
      if (uri.origin != base.origin) continue;
      final prefix = base.path.replaceAll(RegExp(r'/+$'), '');
      if (prefix.isNotEmpty &&
          uri.path != prefix &&
          !uri.path.startsWith('$prefix/')) {
        continue;
      }
      final to = Uri.parse(target);
      return uri
          .replace(
            scheme: to.scheme,
            host: to.host,
            port: to.port,
            path:
                to.path.replaceAll(RegExp(r'/+$'), '') +
                uri.path.substring(prefix.length),
          )
          .toString();
    }
    return value;
  }

  static String? normalizeBase(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9.:-]*$')
            .hasMatch(uri.host.replaceAll('[', '').replaceAll(']', ''))) {
      return null;
    }
    return uri.toString().replaceAll(RegExp(r'/+$'), '');
  }
}
