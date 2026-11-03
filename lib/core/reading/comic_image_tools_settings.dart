import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum TextTranslationMode { system, ai, fallback }

class ComicImageToolsSettings extends ChangeNotifier {
  static final instance = ComicImageToolsSettings();
  static const fileName = 'comic_image_tools.json';
  bool automatic = false;
  bool upscaleCovers = false;
  bool upscaleVideoPosters = false;
  int concurrency = 1;
  int threshold = 1080;
  int noise = 0;
  String imageStyle = 'anime';
  String target = 'zh-Hans';
  String source = 'auto';
  bool liveTranslation = false;
  bool ai = false;
  bool aiFallback = false;
  TextTranslationMode get translationMode => ai
      ? TextTranslationMode.ai
      : aiFallback
      ? TextTranslationMode.fallback
      : TextTranslationMode.system;
  set translationMode(TextTranslationMode value) {
    ai = value == TextTranslationMode.ai;
    aiFallback = value == TextTranslationMode.fallback;
  }

  bool serverTranslation = false;
  String imageTranslationEndpoint = '';
  String serverOcr = '48px';
  String serverTranslator = 'chatgpt';
  String endpoint = '';
  String model = '';
  String colorizeEndpoint = '';
  String colorizeProtocol = 'openai';
  String colorizeModel = '';
  String colorizePrompt = defaultColorizePrompt;

  static const String defaultColorizePrompt =
      'Colorize this black-and-white manga page with natural, muted colors. '
      'Keep the original line art, composition and text unchanged.';
  Future<void> _pending = Future.value();

  Future<void> boot() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$fileName');
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return;
      automatic = data['automatic'] == true;
      upscaleCovers = data['upscaleCovers'] == true;
      upscaleVideoPosters = data['upscaleVideoPosters'] == true;
      final rawConcurrency = data['concurrency'];
      concurrency = rawConcurrency is int ? rawConcurrency.clamp(1, 4) : 1;
      imageStyle = data['imageStyle'] == 'photo' ? 'photo' : 'anime';
      threshold = [720, 1080, 1440, 2160].contains(data['threshold'])
          ? data['threshold'] as int
          : 1080;
      noise = [0, 1, 2, 3].contains(data['noise']) ? data['noise'] as int : 0;
      target = languages.containsKey(data['target'])
          ? data['target'] as String
          : 'zh-Hans';
      source = data['source'] == 'auto' || languages.containsKey(data['source'])
          ? data['source'] as String
          : 'auto';
      liveTranslation = data['liveTranslation'] == true;
      ai = data['ai'] == true;
      aiFallback = !ai && data['aiFallback'] == true;
      serverTranslation = data['serverTranslation'] == true;
      imageTranslationEndpoint = '${data['imageTranslationEndpoint'] ?? ''}';
      serverOcr = data['serverOcr'] == 'mocr' ? 'mocr' : '48px';
      serverTranslator =
          [
            'chatgpt',
            'deepl',
            'youdao',
            'baidu',
            'sakura',
          ].contains(data['serverTranslator'])
          ? data['serverTranslator'] as String
          : 'chatgpt';
      endpoint = data['endpoint'] is String ? data['endpoint'] as String : '';
      model = data['model'] is String ? data['model'] as String : '';
      colorizeEndpoint = data['colorizeEndpoint'] is String
          ? data['colorizeEndpoint'] as String
          : '';
      colorizeModel = data['colorizeModel'] is String
          ? data['colorizeModel'] as String
          : '';
      colorizeProtocol = data['colorizeProtocol'] == 'seedream'
          ? 'seedream'
          : 'openai';
      final prompt = data['colorizePrompt'];
      if (prompt is String && prompt.trim().isNotEmpty) {
        colorizePrompt = prompt;
      }
    } catch (_) {
      // Optional preferences must never prevent reading.
    }
    notifyListeners();
  }

  Future<void> save() {
    final text = jsonEncode({
      'automatic': automatic,
      'upscaleCovers': upscaleCovers,
      'upscaleVideoPosters': upscaleVideoPosters,
      'concurrency': concurrency.clamp(1, 4),
      'threshold': threshold,
      'noise': noise,
      'imageStyle': imageStyle,
      'target': target,
      'source': source,
      'liveTranslation': liveTranslation,
      'ai': ai,
      'aiFallback': aiFallback,
      'serverTranslation': serverTranslation,
      'imageTranslationEndpoint': imageTranslationEndpoint,
      'serverOcr': serverOcr,
      'serverTranslator': serverTranslator,
      'endpoint': endpoint,
      'model': model,
      'colorizeEndpoint': colorizeEndpoint,
      'colorizeProtocol': colorizeProtocol,
      'colorizeModel': colorizeModel,
      'colorizePrompt': colorizePrompt,
    });
    notifyListeners();
    _pending = _pending.catchError((Object _) {}).then((_) async {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$fileName');
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(file.path);
    });
    return _pending;
  }

  static const languages = {
    'zh-Hans': '简体中文',
    'zh-Hant': '繁体中文',
    'en': '英语',
    'ja': '日语',
    'ko': '韩语',
    'fr': '法语',
    'de': '德语',
    'es': '西班牙语',
    'ru': '俄语',
    'pt': '葡萄牙语',
    'it': '意大利语',
    'ar': '阿拉伯语',
  };
}
