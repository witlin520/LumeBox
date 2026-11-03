import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Upstream manga-image-translator multipart image API. Models stay on server.
class MangaTranslationClient {
  static const maxInput = 20 * 1024 * 1024, maxOutput = 30 * 1024 * 1024;
  static Uri endpoint(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException('请填写漫画翻译服务器的完整 http(s) 地址');
    }
    if (uri.path.endsWith('/translate/with-form/image')) return uri;
    if (uri.query.isNotEmpty) {
      throw const FormatException('服务器根地址不能带查询参数，请填写完整接口地址');
    }
    return uri.replace(
      path:
          '${uri.path.replaceFirst(RegExp(r'/+$'), '')}/translate/with-form/image',
    );
  }

  static const targets = {
    'zh-Hans': 'CHS',
    'zh-Hant': 'CHT',
    'ja': 'JPN',
    'en': 'ENG',
    'ko': 'KOR',
    'fr': 'FRA',
    'de': 'DEU',
    'es': 'ESP',
    'ru': 'RUS',
    'pt': 'PTB',
    'it': 'ITA',
    'ar': 'ARA',
  };

  static Future<Uint8List> translate(
    http.Client client,
    Uint8List image, {
    required String url,
    required String target,
    String ocr = '48px',
    String translator = 'chatgpt',
    String bearerToken = '',
  }) async {
    final language = targets[target];
    if (language == null) throw const FormatException('图片翻译服务器不支持此目标语言');
    if (!['48px', 'mocr'].contains(ocr)) {
      throw const FormatException('图片识别模型无效');
    }
    if (![
      'chatgpt',
      'deepl',
      'youdao',
      'baidu',
      'sakura',
    ].contains(translator)) {
      throw const FormatException('服务器翻译器无效');
    }
    if (image.isEmpty || image.length > maxInput) {
      throw const FormatException('图片为空或超过 20MB');
    }
    final request = http.MultipartRequest('POST', endpoint(url))
      ..followRedirects = false
      ..headers['User-Agent'] = 'Mozilla/5.0 (compatible; LumeBox/1.0)'
      ..fields['config'] = jsonEncode({
        'ocr': {'ocr': ocr},
        'translator': {'translator': translator, 'target_lang': language},
      })
      ..files.add(
        http.MultipartFile.fromBytes('image', image, filename: 'page.png'),
      );
    if (bearerToken.trim().isNotEmpty) {
      if (request.url.scheme != 'https') {
        throw const FormatException('带密钥的服务器必须使用 HTTPS');
      }
      request.headers['Authorization'] = 'Bearer ${bearerToken.trim()}';
    }
    return (() async {
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw StateError(
          '图片翻译服务器返回 HTTP ${response.statusCode}，请检查服务端模型、翻译器与密钥配置',
        );
      }
      if (response.contentLength != null &&
          response.contentLength! > maxOutput) {
        throw const FormatException('服务器图片超过 30MB');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxOutput) {
          throw const FormatException('服务器图片超过 30MB');
        }
        bytes.add(chunk);
      }
      final result = bytes.takeBytes();
      const png = [137, 80, 78, 71, 13, 10, 26, 10];
      if (result.length < 24 ||
          !List.generate(8, (i) => result[i] == png[i]).every((v) => v)) {
        throw const FormatException('服务器没有返回 PNG 图片，请检查接口地址');
      }
      final header = ByteData.sublistView(result);
      final width = header.getUint32(16), height = header.getUint32(20);
      if (width == 0 || height == 0 || width * height > 100000000) {
        throw const FormatException('服务器图片尺寸无效或过大');
      }
      return result;
    })().timeout(const Duration(minutes: 4));
  }
}
