/// 单图源的「换网址 + 账号登入」配置。
///
/// 与 [NetworkProfile] 的分工：网络配置管**请求怎么发出去**（UA / Cookie / 代理），
/// 本类管**脚本该打哪个站、用谁的账号**——两者的作用点不同，因此各自独立存一份，
/// 都落在本板块库里（跨板块不共享，也不新增文件）。
///
/// - [mirrors]：站点已知的镜像列表，**由脚本声明**（身份声明里的 `mirrors`），
///   下标 0 视为主站；最多 20 个（多的丢掉，不给用户一个滚不完的列表）。
/// - [mirrorIndex]：用户选中的镜像（下标落在列表内，越界即回到 0）。
/// - [domainOverride]：用户手填的自定义域名（可带 scheme，保存时归一）。
/// - [account] / [password]：本源的登录账号，**明文**给脚本（登录是站点业务，
///   宿主不代做——很多站点根本不支持登录，脚本自己决定怎么用）。
///
/// 域名解析优先级（唯一口径，见 [resolvedDomain]）：
/// **自定义域名 > mirrors[mirrorIndex] > mirrors[0] > 脚本自带默认（空串）**。
/// 用户手填的地址一定压过脚本声明的镜像：用户填它就是为了绕开脚本里那个打不开的站。
library;

import 'source_extension_settings.dart';
import 'source_settings_policy.dart';

/// 单图源的换网址 / 登录配置。
class SourceSiteConfig {
  const SourceSiteConfig({
    this.mirrors = const <String>[],
    this.mirrorIndex = 0,
    this.domainOverride = '',
    this.account = '',
    this.password = '',
    this.mirrorUrl = '',
    this.images = const SourceRoute(),
    this.video = const SourceRoute(),
    this.settingDefinitions = const [],
    this.settingValues = const {},
    this.commonDefinitions = const [],
    this.appSettingValues = const {},
  });

  /// 每组最多 20 条；设置页折叠展示较长的站点列表。
  static const int maxMirrors = 20;

  /// 未配置的空值（老库、老脚本读出来就是这个）。
  static const SourceSiteConfig none = SourceSiteConfig();

  /// 脚本声明的镜像（下标 0 = 主站）。
  final List<String> mirrors;

  /// 用户选中的镜像下标；读取时收敛到 `[0, mirrors.length)`。
  final int mirrorIndex;

  /// 用户手填的自定义域名（可能带 scheme，可能带尾斜杠；存的是原文）。
  final String domainOverride;

  /// 登录账号（明文，按源隔离）。
  final String account;

  /// 登录密码（明文，按源隔离）。
  final String password;
  final String mirrorUrl;
  final SourceRoute images, video;
  final List<SourceSetting> settingDefinitions;
  final Map<String, Object?> settingValues;
  final List<SourceSetting> commonDefinitions;
  final Map<String, Object?> appSettingValues;
  List<SourceSetting> get sourceDefinitions =>
      SourceSettingsPolicy.sourceFields(commonDefinitions, settingDefinitions);
  Map<String, Object?> get resolvedSourceSettings =>
      SourceSettingsPolicy.resolve(sourceDefinitions, settingValues);
  Map<String, Object?> get resolvedCommonSettings =>
      SourceSettingsPolicy.resolve(commonDefinitions, {
        ...settingValues,
        ...appSettingValues,
      });
  Map<String, Object?> get resolvedSettings => {
    ...resolvedSourceSettings,
    ...resolvedCommonSettings,
  };

  SourceSiteConfig redeclare({
    required List<String> mirrors,
    required SourceRoute images,
    required SourceRoute video,
    required List<SourceSetting> settings,
    List<SourceSetting>? common,
  }) {
    final previous = selectedMirror;
    final index = previous == null ? 0 : mirrors.indexOf(previous);
    return copyWith(
      mirrors: mirrors,
      mirrorIndex: index < 0 ? 0 : index,
      images: this.images.redeclare(images),
      video: this.video.redeclare(video),
      settingDefinitions: settings,
      commonDefinitions: common ?? commonDefinitions,
    ).normalized();
  }

  String rewriteUrl(String url, {String? kind}) {
    final site = SourceRoute(
      urls: mirrors,
      selected: selectedMirror ?? '',
      custom: domainOverride,
    );
    if (kind == 'image') {
      final target = images.rewrite(url);
      return target != url ? target : site.rewrite(url);
    }
    if (kind == 'video') {
      final target = video.rewrite(url);
      return target != url ? target : site.rewrite(url);
    }
    if (kind == 'site') return site.rewrite(url);
    var best = site, score = site.matchLength(url);
    for (final route in [images, video]) {
      final length = route.matchLength(url);
      if (length > score) {
        best = route;
        score = length;
      }
    }
    return best.rewrite(url);
  }

  /// 是否填了自定义域名（界面据此提示「自定义域名优先」）。
  bool get hasCustomDomain => normalizeDomain(domainOverride) != null;

  /// 是否填过账号（密码单独填也算配置过：有的站只用 token 当密码）。
  bool get hasLogin => account.trim().isNotEmpty || password.isNotEmpty;

  /// 收敛后的镜像下标（列表为空时恒为 0）。
  int get safeMirrorIndex {
    if (mirrors.isEmpty) return 0;
    if (mirrorUrl.isNotEmpty && mirrors.contains(mirrorUrl)) {
      return mirrors.indexOf(mirrorUrl);
    }
    if (mirrorIndex < 0) return 0;
    if (mirrorIndex >= mirrors.length) return mirrors.length - 1;
    return mirrorIndex;
  }

  /// 用户选中（或回落到主站）的镜像；没有镜像时为 null。
  String? get selectedMirror =>
      mirrors.isEmpty ? null : mirrors[safeMirrorIndex];

  /// **解析后的域名**（脚本读到的 `LumeSource.config.domain`）：
  /// 自定义域名 > 选中镜像 > 首个镜像 > `''`（脚本没有声明镜像时为空串，
  /// 脚本据此回落到自己脚本里的默认地址）。
  String get resolvedDomain {
    final override = normalizeDomain(domainOverride);
    if (override != null) return override;
    return selectedMirror ?? '';
  }

  SourceSiteConfig copyWith({
    List<String>? mirrors,
    int? mirrorIndex,
    String? domainOverride,
    String? account,
    String? password,
    String? mirrorUrl,
    SourceRoute? images,
    SourceRoute? video,
    List<SourceSetting>? settingDefinitions,
    Map<String, Object?>? settingValues,
    List<SourceSetting>? commonDefinitions,
    Map<String, Object?>? appSettingValues,
  }) => SourceSiteConfig(
    mirrors: mirrors ?? this.mirrors,
    mirrorIndex: mirrorIndex ?? this.mirrorIndex,
    domainOverride: domainOverride ?? this.domainOverride,
    account: account ?? this.account,
    password: password ?? this.password,
    mirrorUrl: mirrorUrl ?? (mirrorIndex != null ? '' : this.mirrorUrl),
    images: images ?? this.images,
    video: video ?? this.video,
    settingDefinitions: settingDefinitions ?? this.settingDefinitions,
    settingValues: settingValues ?? this.settingValues,
    commonDefinitions: commonDefinitions ?? this.commonDefinitions,
    appSettingValues: appSettingValues ?? this.appSettingValues,
  );

  /// 归一：镜像合法化 + 下标收敛。从库里读出来、或从脚本声明读进来时都过一遍，
  /// 保证内存里这份配置始终是可直接使用的形态。
  SourceSiteConfig normalized() {
    final list = normalizeMirrors(mirrors);
    final selected = selectedMirror;
    final index = selected == null ? 0 : list.indexOf(selected);
    return SourceSiteConfig(
      mirrors: list,
      mirrorIndex: index < 0 ? 0 : index,
      mirrorUrl: list.contains(selected) ? selected! : '',
      domainOverride: domainOverride.trim(),
      account: account,
      password: password,
      images: images,
      video: video,
      settingDefinitions: settingDefinitions,
      commonDefinitions: commonDefinitions,
      appSettingValues: _cleanValues(appSettingValues),
      settingValues: Map.unmodifiable(
        Map.fromEntries(
          settingValues.entries
              .where(
                (e) =>
                    RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(e.key) &&
                    (e.value is bool ||
                        e.value is num && (e.value as num).isFinite ||
                        e.value is String &&
                            (e.value as String).length <= 4096),
              )
              .take(128),
        ),
      ),
    );
  }

  /// 镜像归一：只留 http(s)、去空白、去重、截断到 [maxMirrors]。
  ///
  /// 脚本里写错一条（相对路径、`javascript:`、重复的主站）不该让整份声明不可用：
  /// 非法项丢掉，合法的照常生效。
  static List<String> normalizeMirrors(Object? raw) {
    if (raw is! List) return const <String>[];
    final result = <String>[];
    for (final entry in raw) {
      final text = '${entry is Map ? entry['url'] ?? '' : entry ?? ''}'.trim();
      if (text.isEmpty) continue;
      final uri = Uri.tryParse(text);
      if (uri == null ||
          !const <String>{'http', 'https'}.contains(uri.scheme) ||
          uri.userInfo.isNotEmpty ||
          !_isHostLike(uri.host)) {
        continue;
      }
      final value = text.replaceAll(RegExp(r'/+$'), '');
      if (value.isEmpty) continue;
      // 去重按整串（同一条镜像写两遍没有意义）。
      if (result.any((item) => item.toLowerCase() == value.toLowerCase())) {
        continue;
      }
      result.add(value);
      if (result.length >= maxMirrors) break;
    }
    return List<String>.unmodifiable(result);
  }

  /// 归一用户手填的域名：缺 scheme 补 `https://`、去尾斜杠；
  /// **非法返回 null**（不是域名也不是 http(s) 地址）。
  ///
  /// 非法输入在保存前由界面拦下（[domainIssue]），这里返回 null 只是让解析链
  /// 可以安全地「当作没填」——绝不把一段看不懂的文本当站点地址发给脚本。
  static String? normalizeDomain(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final withScheme = text.contains('://') ? text : 'https://$text';
    final uri = Uri.tryParse(withScheme);
    if (uri == null) return null;
    if (!const <String>{'http', 'https'}.contains(uri.scheme)) return null;
    if (uri.userInfo.isNotEmpty) return null;
    if (uri.hasQuery || uri.hasFragment) return null;
    if (!_isHostLike(uri.host)) return null;
    final value = withScheme.replaceAll(RegExp(r'/+$'), '');
    return value.isEmpty ? null : value;
  }

  /// 主机名形态校验。
  ///
  /// `Uri.tryParse` 对主机几乎不校验（`https://不是地址` 也能解析出一个「主机」），
  /// 因此这里补一道：只认 DNS 名 / IP / 带点的本机名，IPv6 按十六进制与冒号判。
  /// 挡掉的是「用户随手打了一句话」这种输入，不是要做域名解析。
  static bool _isHostLike(String host) {
    if (host.isEmpty) return false;
    if (host.length > 253) return false;
    // IPv6：Uri.host 已经剥掉方括号。
    if (host.contains(':')) {
      return RegExp(r'^[0-9A-Fa-f:.]+$').hasMatch(host);
    }
    return RegExp(r'^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$').hasMatch(host);
  }

  /// 自定义域名的可读校验原因；合法（或留空）返回 null。
  static String? domainIssue(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (normalizeDomain(text) != null) return null;
    return '自定义域名只能是域名或 http(s) 地址，例如 example.com 或 https://m.example.com';
  }

  /// 镜像在主界面上展示的主机名（列表只显示 host，不显示整串地址）。
  static String hostOf(String mirror) => Uri.tryParse(mirror)?.host ?? mirror;

  /// 落库 JSON（板块库的一列里存这一份）。
  Map<String, Object?> toJson() => <String, Object?>{
    'mirrors': mirrors,
    'mirrorIndex': mirrorIndex,
    'domainOverride': domainOverride,
    'account': account,
    'password': password,
    'mirrorUrl': selectedMirror ?? '',
    'images': images.toJson(),
    'video': video.toJson(),
    'settings': settingDefinitions.map((f) => f.toJson()).toList(),
    'settingValues': settingValues,
    'commonSettings': commonDefinitions.map((f) => f.toJson()).toList(),
    'appSettingValues': appSettingValues,
  };

  /// 从落库 JSON 还原；缺失 / 非法项一律回落到默认（老库照常读得出来）。
  static SourceSiteConfig fromJson(Object? json) {
    if (json is! Map) return none;
    return SourceSiteConfig(
      mirrors: normalizeMirrors(json['mirrors']),
      mirrorIndex: _int(json['mirrorIndex']) ?? 0,
      domainOverride: '${json['domainOverride'] ?? ''}',
      account: '${json['account'] ?? ''}',
      password: '${json['password'] ?? ''}',
      mirrorUrl: '${json['mirrorUrl'] ?? ''}',
      images: SourceRoute.fromJson(json['images']),
      video: SourceRoute.fromJson(json['video']),
      settingDefinitions: _savedDefinitions(json['settings']),
      commonDefinitions: _savedCommon(json['commonSettings']),
      appSettingValues: json['appSettingValues'] is Map
          ? (json['appSettingValues'] as Map).map((k, v) => MapEntry('$k', v))
          : const {},
      settingValues: json['settingValues'] is Map
          ? (json['settingValues'] as Map).map((k, v) => MapEntry('$k', v))
          : const {},
    ).normalized();
  }

  /// 发给脚本的只读快照（`LumeSource.config`）。
  ///
  /// [cookie] 来自单图源网络覆盖（与「网络配置」里那份是同一份数据）：
  /// 脚本可能要把它并进自己的请求头，因此一并给出。
  Map<String, Object?> toScriptJson({required String cookie}) =>
      <String, Object?>{
        'domain': resolvedDomain,
        'mirrors': mirrors,
        'mirrorIndex': safeMirrorIndex,
        'customDomain': normalizeDomain(domainOverride) ?? '',
        'account': account,
        'password': password,
        'cookie': cookie,
        'imageDomain': images.resolved,
        'imageMirrors': images.urls,
        'videoDomain': video.resolved,
        'videoMirrors': video.urls,
        'settings': resolvedSettings,
        'commonSettings': resolvedCommonSettings,
        'sourceSettings': resolvedSourceSettings,
      };

  static Map<String, Object?> _cleanValues(Map<String, Object?> raw) =>
      Map.unmodifiable(
        Map.fromEntries(
          raw.entries
              .where(
                (e) =>
                    RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(e.key) &&
                    (e.value is bool ||
                        e.value is num && (e.value as num).isFinite ||
                        e.value is String &&
                            (e.value as String).length <= 4096),
              )
              .take(128),
        ),
      );
  static List<SourceSetting> _savedCommon(Object? raw) {
    try {
      return SourceSettingsPolicy.parseCommon(raw);
    } on FormatException {
      return const [];
    }
  }

  static List<SourceSetting> _savedDefinitions(Object? raw) {
    try {
      return SourceSetting.parseAll(raw);
    } on FormatException {
      return const [];
    }
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  @override
  String toString() =>
      'SourceSiteConfig(镜像 ${mirrors.length} 个'
      '${mirrors.isEmpty ? '' : '，选中 ${safeMirrorIndex + 1}'}'
      '${hasCustomDomain ? '，自定义域名' : ''}'
      '${hasLogin ? '，已填账号' : ''})';
}
