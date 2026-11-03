import 'package:flutter/services.dart';

class TranslationLanguagePack {
  const TranslationLanguagePack({
    required this.code,
    required this.name,
    required this.installed,
  });
  final String code, name;
  final bool installed;

  factory TranslationLanguagePack.fromMap(Map<Object?, Object?> row) {
    final code = row['code'], name = row['name'], status = row['status'];
    if (code is! String ||
        code.isEmpty ||
        name is! String ||
        !const ['installed', 'supported'].contains(status)) {
      throw const FormatException('系统返回的语言包状态无效');
    }
    return TranslationLanguagePack(
      code: code,
      name: name,
      installed: status == 'installed',
    );
  }
}

/// Installation state always comes from iOS, since the system owns the assets.
class TranslationLanguages {
  const TranslationLanguages();
  static const channel = MethodChannel('lumebox/comicImages');
  Future<List<TranslationLanguagePack>> load() async {
    final rows = await channel.invokeListMethod<Object?>(
      'translationLanguages',
    );
    if (rows == null) throw const FormatException('系统未返回语言包状态');
    return rows
        .map((row) {
          if (row is! Map) throw const FormatException('语言包信息无效');
          return TranslationLanguagePack.fromMap(row);
        })
        .toList(growable: false);
  }

  Future<void> download(List<String> languages, {required String id}) async {
    if (languages.isEmpty) return;
    await channel.invokeListMethod<String>('prepareTranslationLanguages', {
      'id': id,
      'languages': languages.toSet().toList(),
      'target': 'zh-Hans',
    });
  }

  Future<void> cancel(String id) =>
      channel.invokeMethod<void>('cancel', {'id': id});
}
