import 'dart:convert';

import 'comic_image_tools.dart';

/// Private connection files are imported into Keychain, never into backups.
class TranslationConnectionConfig {
  const TranslationConnectionConfig(
    this.endpoint,
    this.model,
    this.apiKey,
    this.target,
  );
  final String endpoint, model, apiKey, target;

  factory TranslationConnectionConfig.parse(String text) {
    if (utf8.encode(text).length > 16384) {
      throw const FormatException('翻译配置文件超过 16KB');
    }
    final data = jsonDecode(text);
    if (data is! Map ||
        data['format'] != 'lumebox.translation-connection' ||
        data['version'] != 1) {
      throw const FormatException('请选择 LumeBox 翻译配置文件');
    }
    String field(String key, int max) {
      final value = data[key];
      if (value is! String ||
          value.trim().isEmpty ||
          value.length > max ||
          value.contains(RegExp(r'[\r\n]'))) {
        throw FormatException('翻译配置的 $key 无效');
      }
      return value.trim();
    }

    final endpoint = field('endpoint', 2048);
    ComicImageTools.validateEndpoint(endpoint);
    final target = data['target'] ?? 'zh-Hans';
    if (target is! String ||
        !ComicImageToolsSettings.languages.containsKey(target)) {
      throw const FormatException('翻译目标语言无效');
    }
    return TranslationConnectionConfig(
      endpoint,
      field('model', 256),
      field('apiKey', 4096),
      target,
    );
  }
}
