import 'dart:convert';

import '../reading/reading_library.dart';
import '../session/section.dart';
import '../net/web_session_lifecycle.dart';

/// Per-section display and routing preferences, kept separate from downloaded scripts.
class SourcePreferences {
  const SourcePreferences({
    this.pinned = false,
    this.iconUrl = '',
    this.iconData = '',
    this.originalOrigin = '',
    this.customOrigin = '',
    this.newestFirst = false,
    this.pickerGroup = '',
    this.contentCategory = '',
  });
  final bool pinned, newestFirst;

  /// 主动获取的图标独立保存，不依赖可清理的网络缓存。
  final String iconData;
  final String iconUrl, originalOrigin, customOrigin;
  final String pickerGroup;
  final String contentCategory;
  static String _key(String id) => 'source.preferences.$id';
  static SourcePreferences read(Section section, String id) {
    try {
      final raw = ReadingLibrary.find(section)?.setting(_key(id));
      final map = raw == null ? null : jsonDecode(raw);
      if (map is! Map) return const SourcePreferences();
      return SourcePreferences(
        pinned: map['pinned'] == true,
        iconUrl: '${map['iconUrl'] ?? ''}',
        iconData: '${map['iconData'] ?? ''}',
        originalOrigin: '${map['originalOrigin'] ?? ''}',
        customOrigin: '${map['customOrigin'] ?? ''}',
        newestFirst: map['newestFirst'] == true,
        pickerGroup: '${map['pickerGroup'] ?? ''}',
        contentCategory: '${map['contentCategory'] ?? ''}',
      );
    } catch (_) {
      return const SourcePreferences();
    }
  }

  Future<void> save(Section section, String id) async {
    final library = await ReadingLibrary.open(section);
    final previous = read(section, id);
    if (previous.originalOrigin != originalOrigin ||
        previous.customOrigin != customOrigin) {
      WebSessionLifecycle.invalidate(
        hosts: {
          for (final value in [
            previous.originalOrigin,
            previous.customOrigin,
            originalOrigin,
            customOrigin,
          ])
            if (Uri.tryParse(value)?.host.isNotEmpty == true)
              Uri.parse(value).host,
        },
      );
    }
    library.setSetting(
      _key(id),
      jsonEncode({
        'pinned': pinned,
        'iconUrl': iconUrl,
        'iconData': iconData,
        'originalOrigin': originalOrigin,
        'customOrigin': customOrigin,
        'newestFirst': newestFirst,
        'pickerGroup': pickerGroup,
        'contentCategory': contentCategory,
      }),
    );
  }

  SourcePreferences copyWith({
    bool? pinned,
    bool? newestFirst,
    String? iconUrl,
    String? iconData,
    String? originalOrigin,
    String? customOrigin,
    String? pickerGroup,
    String? contentCategory,
  }) => SourcePreferences(
    pinned: pinned ?? this.pinned,
    newestFirst: newestFirst ?? this.newestFirst,
    pickerGroup: pickerGroup ?? this.pickerGroup,
    contentCategory: contentCategory ?? this.contentCategory,
    iconUrl: iconUrl ?? this.iconUrl,
    iconData: iconData ?? this.iconData,
    originalOrigin: originalOrigin ?? this.originalOrigin,
    customOrigin: customOrigin ?? this.customOrigin,
  );
  String rewrite(String url) {
    final from = Uri.tryParse(originalOrigin),
        to = Uri.tryParse(customOrigin),
        uri = Uri.tryParse(url);
    if (from == null ||
        to == null ||
        uri == null ||
        !uri.hasAuthority ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        !validOrigin(originalOrigin) ||
        !validOrigin(customOrigin) ||
        uri.origin != from.origin) {
      return url;
    }
    return uri
        .replace(scheme: to.scheme, host: to.host, port: to.port, userInfo: '')
        .toString();
  }

  static bool validOrigin(String text) {
    final u = Uri.tryParse(text.trim());
    return u != null &&
        (u.scheme == 'https' || u.scheme == 'http') &&
        u.host.isNotEmpty &&
        u.userInfo.isEmpty &&
        (u.path.isEmpty || u.path == '/') &&
        !u.hasQuery &&
        !u.hasFragment;
  }
}
