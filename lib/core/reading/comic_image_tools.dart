import '../translation/ai_text_translation.dart';
import 'comic_image_tools_settings.dart';
import 'image_upscale_report.dart';
export 'image_upscale_report.dart';
export 'comic_image_tools_settings.dart';

import 'dart:async';
import 'dart:convert';

import 'translation_http_client.dart';

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../translation/text_translation.dart';
import 'manga_translation_client.dart';

class ComicTranslationReport {
  const ComicTranslationReport({
    required this.recognition,
    required this.translation,
    required this.regions,
    required this.characters,
    required this.deviceTranslation,
  });
  final Duration recognition, translation;
  final int regions, characters;
  final bool deviceTranslation;
  String get summary =>
      '识别 $regions 处 / $characters 字 · OCR ${(recognition.inMilliseconds / 1000).toStringAsFixed(2)} 秒 · 翻译 ${(translation.inMilliseconds / 1000).toStringAsFixed(2)} 秒 · ${deviceTranslation ? '设备端翻译（含缓存）' : '自填 AI 接口'}';
}

/// 自动超分作用的图片范围。
enum UpscaleSurface {
  /// 漫画阅读器正文（始终受「自动超分」总开关控制）。
  reader,

  /// 漫画 / 猫源 / 历史记录封面。
  cover,

  /// 视频海报。
  videoPoster,
}

/// 给非阅读器管线用的解码增强入口。
///
/// 退出时取消本页任务。
Future<Uint8List> automaticUpscale(Uint8List bytes, UpscaleSurface surface) =>
    ComicImageTools.shared.automatic(bytes, surface: surface);

class _UpscaleWaiter {
  _UpscaleWaiter(this.owner);
  final ComicImageTools owner;
  final ready = Completer<bool>();
}

class ComicTextRegion {
  const ComicTextRegion({
    required this.text,
    required this.translation,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
  final String text, translation;
  final double x, y, width, height;
  factory ComicTextRegion.fromMap(Map data) {
    double number(String key) {
      final value = data[key];
      if (value is! num || !value.isFinite) {
        throw const FormatException('文字坐标无效');
      }
      return value.toDouble().clamp(0, 1);
    }

    return ComicTextRegion(
      text: data['text'] as String,
      translation: data['translation'] as String? ?? '',
      x: number('x'),
      y: number('y'),
      width: number('width'),
      height: number('height'),
    );
  }
  ComicTextRegion translated(String value) => ComicTextRegion(
    text: text,
    translation: value,
    x: x,
    y: y,
    width: width,
    height: height,
  );
}

/// A reader-owned session. Disposing cancels all this reader's native jobs.
class ComicImageTools {
  ComicImageTools({this.settings, this.client, this.imageStyle});

  /// 封面 / 海报等非阅读器管线共用的一台处理器。
  ///
  /// 阅读器有自己的实例（退出时取消本页任务）；封面数量多、生命周期长，
  /// 用一个不随页面销毁的共享实例即可。
  static final ComicImageTools shared = ComicImageTools();

  String? imageStyle;
  static const channel = MethodChannel('lumebox/comicImages');
  final ComicImageToolsSettings? settings;
  final http.Client? client;
  ComicImageToolsSettings get preferences =>
      settings ?? ComicImageToolsSettings.instance;
  final Set<String> _jobs = {};
  final Set<http.Client> _ownedClients = {};
  static int _sequence = 0;
  bool _disposed = false;
  ComicTranslationReport? lastTranslationReport;
  String? lastTranslationWarning;
  ImageUpscaleReport? lastUpscaleReport;

  Uint8List _upscaleResult(Object? value, Uint8List original) {
    final bytes = value is Map ? value['bytes'] : value;
    if (bytes is! Uint8List || bytes.isEmpty) throw StateError('超分未返回图片');
    final map = value is Map ? value : const {};
    final report = ImageUpscaleReport(
      map['status'] as String? ??
          (listEquals(bytes, original) ? 'skipped' : 'processed'),
      width: map['width'] as int?,
      height: map['height'] as int?,
      outputWidth: map['outputWidth'] as int?,
      outputHeight: map['outputHeight'] as int?,
      reason: map['reason'] as String? ?? '',
    );
    lastUpscaleReport = report;
    report.publish();
    return bytes;
  }

  void _upscaleFailed(Object error) {
    final report = ImageUpscaleReport(
      'failed',
      reason: error is PlatformException
          ? error.message ?? '设备端处理失败'
          : '图片处理失败',
    );
    lastUpscaleReport = report;
    report.publish();
  }

  /// 自动超分的并发闸门。用户在设置里可以调到 4，默认 1。
  // Readers and cover pipelines share one device budget, rather than each
  // starting up to four independent Core ML jobs at once.
  static int _automaticActive = 0;
  static final List<_UpscaleWaiter> _automaticWaiters = [];
  @visibleForTesting
  static bool? debugAutomaticSupported;

  Future<T?> _invoke<T>(String method, Map<String, Object?> args) async {
    if (_disposed) throw StateError('图片处理已取消');
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    _jobs.add(id);
    try {
      final result = await channel
          .invokeMethod<T>(method, {...args, 'id': id})
          .timeout(const Duration(minutes: 3));
      if (_disposed) throw StateError('图片处理已取消');
      return result;
    } on TimeoutException {
      unawaited(
        channel
            .invokeMethod<void>('cancel', {'id': id})
            .catchError((Object _) {}),
      );
      rethrow;
    } finally {
      _jobs.remove(id);
    }
  }

  Future<Uint8List> superResolve(Uint8List bytes) async {
    if (!await _acquireAutomaticSlot()) throw StateError('图片处理已取消');
    try {
      final result = await _invoke<Object?>('superResolve', {
        'bytes': bytes,
        'noise': preferences.noise,
        'imageStyle': imageStyle ?? preferences.imageStyle,
      });
      return _upscaleResult(result, bytes);
    } catch (error) {
      _upscaleFailed(error);
      rethrow;
    } finally {
      _releaseAutomaticSlot();
    }
  }

  /// 某个范围当前是否应该自动超分。
  ///
  /// 阅读器正文不受范围开关影响（总开关打开就处理）。
  bool surfaceEnabled(UpscaleSurface surface) {
    final prefs = preferences;
    if (!prefs.automatic) return false;
    return switch (surface) {
      UpscaleSurface.reader => true,
      UpscaleSurface.cover => prefs.upscaleCovers,
      UpscaleSurface.videoPoster => prefs.upscaleVideoPosters,
    };
  }

  /// Only decoding uses this hook; original downloads/exports stay untouched.
  Future<Uint8List> automatic(
    Uint8List bytes, {
    UpscaleSurface surface = UpscaleSurface.reader,
  }) {
    if (_disposed ||
        !(debugAutomaticSupported ?? Platform.isIOS) ||
        !surfaceEnabled(surface) ||
        _automaticWaiters.length >= 32) {
      return Future.value(bytes);
    }
    final completer = Completer<Uint8List>();
    unawaited(() async {
      if (!await _acquireAutomaticSlot()) {
        completer.complete(bytes);
        return;
      }
      try {
        if (_disposed || !surfaceEnabled(surface)) {
          completer.complete(bytes);
          return;
        }
        final result = await _invoke<Object?>('superResolve', {
          'bytes': bytes,
          'noise': preferences.noise,
          'imageStyle': imageStyle ?? preferences.imageStyle,
          'threshold': preferences.threshold,
        });
        completer.complete(_upscaleResult(result, bytes));
      } catch (error) {
        if (!_disposed) _upscaleFailed(error);
        // A failed optional enhancement cannot break the original image.
        completer.complete(bytes);
      } finally {
        _releaseAutomaticSlot();
      }
    }());
    return completer.future;
  }

  Future<bool> _acquireAutomaticSlot() async {
    if (_disposed) return false;
    final limit = preferences.concurrency.clamp(1, 4);
    if (_automaticActive < limit) {
      _automaticActive++;
      return true;
    }
    final waiter = _UpscaleWaiter(this);
    _automaticWaiters.add(waiter);
    return waiter.ready.future;
  }

  void _releaseAutomaticSlot() {
    if (_automaticActive > 0) _automaticActive--;
    while (_automaticWaiters.isNotEmpty) {
      final waiter = _automaticWaiters.first;
      if (waiter.owner._disposed) {
        _automaticWaiters.removeAt(0).ready.complete(false);
        continue;
      }
      if (_automaticActive >=
          waiter.owner.preferences.concurrency.clamp(1, 4)) {
        break;
      }
      _automaticActive++;
      _automaticWaiters.removeAt(0).ready.complete(true);
    }
  }

  /// App 内置的 8 个 waifu2x 模型（anime/photo × 降噪 0–3）。
  static const List<String> bundledModelNames = <String>[
    'noise0',
    'noise1',
    'noise2',
    'noise3',
    'photo0',
    'photo1',
    'photo2',
    'photo3',
  ];

  /// 把随包提供的模型安装到设备（编译并写入 Application Support）。
  ///
  /// 首次安装 8 个模型需要一点时间，[onProgress] 用于设置页显示进度。
  Future<void> installBundledModels({
    void Function(int done, int total)? onProgress,
  }) async {
    final total = bundledModelNames.length;
    for (var i = 0; i < total; i++) {
      final name = bundledModelNames[i];
      final data = await rootBundle.load('assets/models/waifu2x/$name.mlmodel');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await _invoke<void>('importModel', {
        'name': '$name.mlmodel',
        'bytes': bytes,
      });
      onProgress?.call(i + 1, total);
    }
  }

  /// 只做文字识别、不翻译；漫画朗读用。
  ///
  /// 结果按「先上后下、同一行从左到右」排序：OCR 的原始顺序不保证适合朗读，
  /// 直接拼起来会把对白读反。坐标是归一化值，纵向差 2% 以内视为同一行。
  Future<List<String>> recognize(Uint8List bytes) async => [
    for (final region in await recognizeRegions(bytes)) region.text.trim(),
  ];

  /// Preserve OCR boxes for reader highlighting; recognition still stays on device.
  Future<List<ComicTextRegion>> recognizeRegions(Uint8List bytes) async {
    final raw = await _invoke<List<Object?>>('recognize', {
      'bytes': bytes,
      'source': preferences.source,
    });
    final regions = <ComicTextRegion>[];
    for (final item in raw ?? const <Object?>[]) {
      if (item is! Map) continue;
      try {
        regions.add(ComicTextRegion.fromMap(item));
      } on FormatException {
        // 单个坏坐标不拖垮整页朗读。
      }
    }
    regions.sort((a, b) {
      // A fixed 2% of a long strip can span several dialogue panels.
      final sameLine = math.min(.02, math.min(a.height, b.height) * .5);
      if ((a.y - b.y).abs() > sameLine) return a.y.compareTo(b.y);
      return a.x.compareTo(b.x);
    });
    return regions.where((region) => region.text.trim().isNotEmpty).toList();
  }

  Future<List<ComicTextRegion>> translate(Uint8List bytes) async {
    lastTranslationReport = null;
    lastTranslationWarning = null;
    final timer = Stopwatch()..start();
    final regions = await recognizeRegions(bytes);
    final recognition = timer.elapsed;
    timer.reset();
    if (regions.isEmpty) {
      lastTranslationReport = ComicTranslationReport(
        recognition: recognition,
        translation: Duration.zero,
        regions: 0,
        characters: 0,
        deviceTranslation: !preferences.ai,
      );
      return [];
    }
    final strings = <String>[];
    // Long-strip OCR can exceed a single native translation session's limits.
    // Keep requests bounded in both count and characters and preserve ordering.
    var start = 0;
    while (start < regions.length) {
      if (_disposed) throw StateError('图片处理已取消');
      var end = start, characters = 0;
      while (end < regions.length && end - start < 100) {
        final length = regions[end].text.runes.length;
        if (length > 40000) throw const FormatException('单个文字区域过长，请分段处理');
        if (characters + length > 40000) break;
        characters += length;
        end++;
      }
      final texts = regions.sublist(start, end).map((r) => r.text).toList();
      late final List<String> translated;
      try {
        translated = await TextTranslationService.shared.translate(
          texts,
          source: preferences.source,
          target: preferences.target,
          mode: preferences.translationMode,
          aiUsing: _translateAI,
          using: (pending) async =>
              (await _invoke<List<Object?>>('translate', {
                'texts': pending,
                'source': preferences.source,
                'target': preferences.target,
              }))?.cast<String>() ??
              [],
        );
      } on PlatformException catch (error) {
        if (error.code != 'translation_partial') rethrow;
        translated = texts
            .map(
              (text) =>
                  TextTranslationService.shared.lookup(
                    text,
                    source: preferences.source,
                    target: preferences.target,
                    mode: preferences.translationMode,
                  ) ??
                  '',
            )
            .toList();
        lastTranslationWarning = '部分文字未翻译，成功译文与原图已保留。请检查全局翻译设置。';
      }
      if (translated.length != texts.length) {
        throw const FormatException('译文数量与识别结果不一致');
      }
      strings.addAll(translated);
      start = end;
    }
    lastTranslationReport = ComicTranslationReport(
      recognition: recognition,
      translation: timer.elapsed,
      regions: regions.length,
      characters: regions.fold(0, (n, r) => n + r.text.runes.length),
      deviceTranslation: !preferences.ai,
    );
    return [
      for (var i = 0; i < regions.length; i++)
        if (strings[i].trim().isNotEmpty) regions[i].translated(strings[i]),
    ];
  }

  /// A hand-selected speech bubble is translated as one paragraph.
  Future<List<ComicTextRegion>> translateSelectedRegion(Uint8List bytes) async {
    final regions = await recognizeRegions(bytes);
    final text = regions
        .map((r) => r.text.trim())
        .where((s) => s.isNotEmpty)
        .join('\n');
    if (text.isEmpty) return const [];
    if (text.runes.length > 40000) {
      throw const FormatException('选区文字过多，请缩小范围后重试');
    }
    final translated = await TextTranslationService.shared.translate(
      [text],
      source: preferences.source,
      target: preferences.target,
      mode: preferences.translationMode,
      aiUsing: _translateAI,
      using: (pending) async =>
          (await _invoke<List<Object?>>('translate', {
            'texts': pending,
            'source': preferences.source,
            'target': preferences.target,
          }))?.cast<String>() ??
          [],
    );
    if (translated.isEmpty || translated.first.trim().isEmpty) return const [];
    return [
      ComicTextRegion(
        text: text,
        translation: translated.first,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
      ),
    ];
  }

  Future<String> testAITranslation() async =>
      (await _translateAI(['Hello'])).first;

  /// Explicit whole-page server translation. Originals and downloads stay intact.
  Future<Uint8List> translateImageOnServer(Uint8List bytes) async {
    if (_disposed) throw StateError('图片处理已取消');
    final owned = client == null;
    final transport =
        client ??
        TranslationHttpClient(
          timeout: const Duration(minutes: 4),
          maxBytes: 30 * 1024 * 1024,
        );
    if (owned) _ownedClients.add(transport);
    try {
      String serverKey = '';
      try {
        serverKey =
            await channel.invokeMethod<String>('getKey', {
              'slot': 'imageServer',
            }) ??
            '';
      } on MissingPluginException {
        /* Anonymous servers also work without native key storage. */
      }
      final result = await MangaTranslationClient.translate(
        transport,
        bytes,
        url: preferences.imageTranslationEndpoint,
        target: preferences.target,
        ocr: preferences.serverOcr,
        translator: preferences.serverTranslator,
        bearerToken: serverKey,
      );
      if (_disposed) throw StateError('图片处理已取消');
      return result;
    } finally {
      if (owned) {
        _ownedClients.remove(transport);
        transport.close();
      }
    }
  }

  /// 云端 AI 上色（通用图片编辑或 Seedream 图生图接口）。
  ///
  /// 设备端上色模型不在本仓库内；这里把图片以 multipart 发到用户自填的
  /// `/v1/images/edits` 类接口，并要求返回 `data[0].b64_json`。图片会上传到
  /// 该服务，界面上必须如实标注；上色可单独保存 API Key。
  Future<Uint8List> colorize(Uint8List bytes) async {
    final uri = validateColorizeEndpoint(preferences.colorizeEndpoint);
    final model = preferences.colorizeModel.trim();
    if (model.isEmpty) throw const FormatException('请先填写 AI 上色模型');
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('图片为空或超过 20MB');
    }
    var key =
        await channel.invokeMethod<String>('getKey', {
          'slot': preferences.colorizeProtocol == 'seedream'
              ? 'colorizeSeedream'
              : 'colorize',
        }) ??
        '';
    // 保留旧版共用密钥的配置；单独填写后不再受翻译密钥影响。
    if (key.isEmpty && preferences.colorizeProtocol != 'seedream') {
      key = await channel.invokeMethod<String>('getKey') ?? '';
    }
    if (key.isEmpty) throw const FormatException('请先保存当前上色服务的 API Key');
    final owned = client == null;
    final transport = client ?? http.Client();
    if (_disposed) {
      if (owned) transport.close();
      throw StateError('图片处理已取消');
    }
    if (owned) _ownedClients.add(transport);
    try {
      final prompt = preferences.colorizePrompt.trim().isEmpty
          ? ComicImageToolsSettings.defaultColorizePrompt
          : preferences.colorizePrompt.trim();
      final imageType = _imageType(bytes);
      final http.BaseRequest request;
      if (preferences.colorizeProtocol == 'seedream') {
        request = http.Request('POST', uri)
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode({
            'model': model,
            'prompt': prompt,
            'image': 'data:${imageType.$2};base64,${base64Encode(bytes)}',
            'size': '2K',
            'response_format': 'b64_json',
            if (model.contains('seedream-5-')) 'output_format': 'png',
            if (model.contains('seedream-4-') ||
                model.contains('seedream-5-0-lite'))
              'sequential_image_generation': 'disabled',
            'stream': false,
            'watermark': true,
          });
      } else {
        final multipart = http.MultipartRequest('POST', uri)
          ..fields['model'] = model
          ..fields['prompt'] = prompt;
        final gptImage =
            model.startsWith('gpt-image-') || model == 'chatgpt-image-latest';
        if (gptImage) {
          // GPT Image 默认返回 base64，不接受旧版 response_format 参数。
          multipart.fields['output_format'] = 'png';
        } else {
          multipart.fields['response_format'] = 'b64_json';
        }
        multipart.files.add(
          http.MultipartFile.fromBytes(
            gptImage ? 'image[]' : 'image',
            bytes,
            filename: imageType.$1,
            contentType: imageType.$2,
          ),
        );
        request = multipart;
      }
      request.headers['Authorization'] = 'Bearer $key';
      final response = await transport
          .send(request)
          .timeout(const Duration(seconds: 120));
      if (response.statusCode != 200) {
        final detail = await response.stream.bytesToString().timeout(
          const Duration(seconds: 15),
        );
        final clipped = detail.length <= 240
            ? detail
            : detail.substring(0, 240);
        throw StateError('AI 上色请求失败（HTTP ${response.statusCode}）：$clipped');
      }
      final buffer = BytesBuilder();
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 120),
      )) {
        buffer.add(chunk);
        if (buffer.length > 32 * 1024 * 1024) {
          throw const FormatException('AI 上色返回内容过大');
        }
      }
      if (_disposed) throw StateError('图片处理已取消');
      final body = jsonDecode(utf8.decode(buffer.takeBytes()));
      if (body is! Map) throw const FormatException('AI 上色返回格式不正确');
      final data = body['data'];
      final first = data is List && data.isNotEmpty ? data.first : null;
      final b64 = first is Map ? first['b64_json'] as String? : null;
      if (b64 == null || b64.isEmpty) {
        throw const FormatException('上色接口没有返回 b64_json；请换用返回 base64 的图片编辑接口');
      }
      final result = base64Decode(b64);
      if (result.isEmpty || result.length > 32 * 1024 * 1024) {
        throw const FormatException('AI 上色返回的图片为空或过大');
      }
      return result;
    } finally {
      if (owned) {
        transport.close();
        _ownedClients.remove(transport);
      }
    }
  }

  /// 按魔数推断上传图片的 MIME，别把 JPEG/WebP 标成 PNG。
  static (String, MediaType) _imageType(Uint8List bytes) {
    bool startsWith(List<int> magic, {int offset = 0}) {
      if (bytes.length < offset + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (bytes[offset + i] != magic[i]) return false;
      }
      return true;
    }

    if (startsWith(<int>[0x89, 0x50, 0x4E, 0x47])) {
      return ('page.png', MediaType('image', 'png'));
    }
    if (startsWith(<int>[0xFF, 0xD8, 0xFF])) {
      return ('page.jpg', MediaType('image', 'jpeg'));
    }
    if (startsWith(<int>[0x52, 0x49, 0x46, 0x46]) &&
        startsWith(<int>[0x57, 0x45, 0x42, 0x50], offset: 8)) {
      return ('page.webp', MediaType('image', 'webp'));
    }
    if (startsWith(<int>[0x66, 0x74, 0x79, 0x70], offset: 4)) {
      return ('page.heic', MediaType('image', 'heic'));
    }
    return ('page.jpg', MediaType('image', 'jpeg'));
  }

  static Uri validateEndpoint(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException('请填写完整 HTTPS Chat Completions 接口地址');
    }
    return uri;
  }

  static Uri validateColorizeEndpoint(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException('请填写服务商提供的完整 HTTPS 图片编辑接口地址');
    }
    if (uri.host.toLowerCase() == 'api.deepseek.com') {
      throw const FormatException(
        'DeepSeek 官方接口不能生成上色图片，请换用支持图片编辑的服务；DeepSeek 可继续用于 AI 翻译',
      );
    }
    if (uri.path.contains('/chat/completions')) {
      throw const FormatException('这是文字对话接口，请填写图片编辑接口地址（通常以 /images/edits 结尾）');
    }
    return uri;
  }

  Future<List<String>> _translateAI(List<String> texts) async {
    validateEndpoint(preferences.endpoint);
    if (preferences.model.trim().isEmpty) {
      throw const FormatException('请先填写 AI 模型');
    }
    final key = await channel.invokeMethod<String>('getKey') ?? '';
    if (key.isEmpty) throw const FormatException('请先保存 AI API Key');
    final owned = client == null;
    final transport = client ?? TranslationHttpClient();
    if (_disposed) {
      if (owned) transport.close();
      throw StateError('图片处理已取消');
    }
    if (owned) _ownedClients.add(transport);
    try {
      final values = await AiTextTranslation.translate(
        transport,
        texts,
        url: preferences.endpoint,
        model: preferences.model,
        key: key,
        target: preferences.target,
        language:
            ComicImageToolsSettings.languages[preferences.target] ??
            preferences.target,
      );
      if (_disposed) throw StateError('图片处理已取消');
      return values;
    } finally {
      if (owned) transport.close();
      _ownedClients.remove(transport);
    }
  }

  void dispose() {
    _disposed = true;
    // 只取消本实例排队的任务，其他页面继续遵守设备并发预算。
    for (final waiter
        in _automaticWaiters.where((w) => w.owner == this).toList()) {
      _automaticWaiters.remove(waiter);
      waiter.ready.complete(false);
    }
    for (final transport in _ownedClients) {
      transport.close();
    }
    _ownedClients.clear();
    for (final id in _jobs.toList()) {
      unawaited(
        channel
            .invokeMethod<void>('cancel', {'id': id})
            .catchError((Object _) {}),
      );
    }
  }
}
