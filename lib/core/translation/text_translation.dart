import '../reading/comic_image_tools_settings.dart';
import '../reading/translation_http_client.dart';
import '../util/lume_log.dart';
import 'ai_text_translation.dart';
import 'translation_result.dart';
export 'translation_result.dart' show unresolvedTranslation;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

typedef TextTranslator = Future<List<String>> Function(List<String> texts);

Map<String, String> _readTranslationCache(String json) {
  final data = jsonDecode(json);
  if (data is! Map) return {};
  return {
    for (final entry in data.entries.take(TextTranslationService.maxEntries))
      if (entry.key is String &&
          RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.key) &&
          entry.value is String &&
          (entry.value as String).length <= 100000)
        entry.key as String: entry.value as String,
  };
}

({String json, List<String> omitted}) _encodeTranslationCache(
  Map<String, String> cache,
) {
  final parts = <String>[], omitted = <String>[];
  var bytes = 2;
  for (final entry in cache.entries.toList().reversed) {
    final part = '${jsonEncode(entry.key)}:${jsonEncode(entry.value)}';
    final size = utf8.encode(part).length + (parts.isEmpty ? 0 : 1);
    if (bytes + size > 10 * 1024 * 1024) {
      omitted.add(entry.key);
    } else {
      parts.add(part);
      bytes += size;
    }
  }
  return (json: '{${parts.reversed.join(',')}}', omitted: omitted);
}

/// Display-only translations. IDs, original metadata and search queries stay intact.
class TextTranslationService extends ChangeNotifier {
  TextTranslationService({
    this.file,
    this.translator,
    this.aiTranslator,
    this.useGlobalSettings = false,
    ComicImageToolsSettings? settings,
  }) : settings = settings ?? ComicImageToolsSettings.instance {
    if (useGlobalSettings) this.settings.addListener(_settingsChanged);
  }
  static final shared = TextTranslationService(useGlobalSettings: true);
  final bool useGlobalSettings;
  final ComicImageToolsSettings settings;
  final TextTranslator? aiTranslator;
  void _settingsChanged() => notifyListeners();
  @override
  void dispose() {
    if (useGlobalSettings) settings.removeListener(_settingsChanged);
    super.dispose();
  }

  final File? file;
  final TextTranslator? translator;
  final Map<String, String> _cache = {};
  final _keys =
      <(String, String, String, TextTranslationMode, String), String>{};
  Future<void>? _boot;
  Future<void> _writes = Future.value();
  int _revision = 0;
  static Future<void> _nativeQueue = Future.value();
  static int _sequence = 0;
  static const channel = MethodChannel('lumebox/comicImages');
  static const maxEntries = 2000;
  bool displayOriginal = false;
  void toggleOriginal() {
    displayOriginal = !displayOriginal;
    notifyListeners();
  }

  String get _profile => jsonEncode([settings.endpoint, settings.model]);

  String _key(
    String text,
    String source,
    String target,
    TextTranslationMode mode, [
    String? profile,
  ]) {
    final identity = (
      text,
      source,
      target,
      mode,
      mode == TextTranslationMode.system ? '' : profile ?? _profile,
    );
    final known = _keys[identity];
    if (known != null) return known;
    final key = sha256
        .convert(
          utf8.encode(
            jsonEncode(
              mode == TextTranslationMode.system
                  ? [1, source, target, text]
                  : [2, mode.name, profile ?? _profile, source, target, text],
            ),
          ),
        )
        .toString();
    _keys[identity] = key;
    if (_keys.length > 4096) _keys.remove(_keys.keys.first);
    return key;
  }

  String? lookup(
    String text, {
    String? source,
    String? target,
    TextTranslationMode? mode,
    String? profile,
  }) {
    final language =
        target ?? (useGlobalSettings ? settings.target : 'zh-Hans');
    final value =
        _cache[_key(
          text,
          source ?? (useGlobalSettings ? settings.source : 'auto'),
          target ?? (useGlobalSettings ? settings.target : 'zh-Hans'),
          mode ??
              (useGlobalSettings
                  ? settings.translationMode
                  : TextTranslationMode.system),
          profile,
        )];
    return value != null && unresolvedTranslation(text, value, language)
        ? null
        : value;
  }

  Future<File> _file() async =>
      file ??
      File(
        '${(await getApplicationSupportDirectory()).path}/text_translations.json',
      );

  Future<void> boot() => _boot ??= () async {
    try {
      final store = await _file();
      if (await store.exists() && await store.length() <= 12 * 1024 * 1024) {
        final data = await compute(
          _readTranslationCache,
          await store.readAsString(),
        );
        for (final entry in data.entries) {
          _cache.putIfAbsent(entry.key, () => entry.value);
        }
      }
    } catch (_) {
      /* Cache failure must not block browsing or reading. */
    }
    notifyListeners();
  }();

  Future<List<String>> translate(
    List<String> texts, {
    String? source,
    String? target,
    TextTranslationMode? mode,
    TextTranslator? using,
    TextTranslator? aiUsing,
  }) async {
    source ??= useGlobalSettings ? settings.source : 'auto';
    target ??= useGlobalSettings ? settings.target : 'zh-Hans';
    mode ??= useGlobalSettings
        ? settings.translationMode
        : TextTranslationMode.system;
    final selectedSource = source, selectedTarget = target, selectedMode = mode;
    final selectedProfile = _profile;
    final selectedEndpoint = settings.endpoint, selectedModel = settings.model;
    await boot();
    final revision = _revision;
    if (texts.any((t) => t.runes.length > 40000) ||
        texts.fold<int>(0, (n, t) => n + t.runes.length) > 40000 ||
        texts.length > 100) {
      throw const FormatException('翻译文字过长，请分段处理');
    }
    final missing = texts
        .where(
          (t) =>
              t.trim().isNotEmpty &&
              lookup(
                    t,
                    source: selectedSource,
                    target: selectedTarget,
                    mode: selectedMode,
                    profile: selectedProfile,
                  ) ==
                  null,
        )
        .toSet()
        .toList();
    if (missing.isNotEmpty) {
      final result = Completer<List<String>>();
      // Apple's presentation owns one session. Serialize callers, then recheck
      // the cache so overlapping requests cannot open competing system sheets.
      _nativeQueue = _nativeQueue.catchError((Object _) {}).then((_) async {
        try {
          if (revision != _revision) throw StateError('译文缓存已清理，请重试');
          final pending = missing
              .where(
                (t) =>
                    lookup(
                      t,
                      source: selectedSource,
                      target: selectedTarget,
                      mode: selectedMode,
                      profile: selectedProfile,
                    ) ==
                    null,
              )
              .toList();
          if (pending.isNotEmpty) {
            PlatformException? partial;
            late final List<String> values;
            try {
              values = await translateWithPolicy(
                pending,
                target: selectedTarget,
                mode: selectedMode,
                native:
                    using ??
                    translator ??
                    (values) => _native(values, selectedSource, selectedTarget),
                ai:
                    aiUsing ??
                    aiTranslator ??
                    (values) => _ai(
                      values,
                      selectedTarget,
                      selectedEndpoint,
                      selectedModel,
                    ),
              );
            } on PlatformException catch (error) {
              final details = error.details;
              if (error.code != 'translation_partial' ||
                  details is! List ||
                  details.length != pending.length ||
                  details.any((v) => v is! String || v.length > 100000)) {
                rethrow;
              }
              values = details.cast<String>();
              partial = error;
            }
            if (revision != _revision) throw StateError('译文缓存已清理，请重试');
            if (values.length != pending.length ||
                values.any(
                  (v) =>
                      (partial == null && v.trim().isEmpty) ||
                      v.length > 100000,
                )) {
              throw const FormatException('翻译结果不完整，请重试');
            }
            for (var i = 0; i < pending.length; i++) {
              if (values[i].trim().isEmpty ||
                  unresolvedTranslation(
                    pending[i],
                    values[i],
                    selectedTarget,
                  )) {
                partial ??= PlatformException(
                  code: 'translation_partial',
                  message: '部分外文尚未得到中文译文，已保留成功译文；可重试或在全局翻译设置中选择自动识别原文、AI 补译。',
                );
                continue;
              }
              final key = _key(
                pending[i],
                selectedSource,
                selectedTarget,
                selectedMode,
                selectedProfile,
              );
              _cache.remove(key);
              _cache[key] = values[i];
            }
            while (_cache.length > maxEntries) {
              _cache.remove(_cache.keys.first);
            }
            notifyListeners();
            unawaited(_save());
            if (partial != null) throw partial;
          }
          result.complete(
            texts
                .map(
                  (t) =>
                      lookup(
                        t,
                        source: selectedSource,
                        target: selectedTarget,
                        mode: selectedMode,
                        profile: selectedProfile,
                      ) ??
                      t,
                )
                .toList(),
          );
        } catch (error, stack) {
          LumeLog.warn(
            '[翻译] ${selectedMode.name} $selectedSource → $selectedTarget，'
            '待处理 ${missing.length} 条，任务未全部完成（${error is PlatformException ? error.code : error.runtimeType}）',
          );
          result.completeError(error, stack);
        }
      });
      return result.future;
    }
    return texts
        .map(
          (t) =>
              lookup(
                t,
                source: selectedSource,
                target: selectedTarget,
                mode: selectedMode,
                profile: selectedProfile,
              ) ??
              t,
        )
        .toList();
  }

  Future<List<String>> _ai(
    List<String> texts,
    String target,
    String endpoint,
    String model,
  ) async {
    AiTextTranslation.endpoint(endpoint);
    if (model.trim().isEmpty) throw const FormatException('请先在全局翻译设置中填写 AI 模型');
    final key = await channel.invokeMethod<String>('getKey') ?? '';
    final transport = TranslationHttpClient();
    try {
      return await AiTextTranslation.translate(
        transport,
        texts,
        url: endpoint,
        model: model,
        key: key,
        language: ComicImageToolsSettings.languages[target] ?? target,
        target: target,
      );
    } finally {
      transport.close();
    }
  }

  Future<List<String>> _native(
    List<String> texts,
    String source,
    String target,
  ) async {
    final id = 'metadata-${_sequence++}';
    try {
      final values = await channel
          .invokeListMethod<String>('translate', {
            'id': id,
            'texts': texts,
            'source': source,
            'target': target,
          })
          .timeout(const Duration(minutes: 3));
      if (values == null) throw const FormatException('未返回译文');
      return values;
    } on TimeoutException {
      unawaited(
        channel
            .invokeMethod<void>('cancel', {'id': id})
            .catchError((Object _) {}),
      );
      rethrow;
    }
  }

  Future<void> _save() {
    final snapshot = Map<String, String>.of(_cache);
    _writes = _writes.catchError((Object _) {}).then((_) async {
      try {
        final data = await compute(_encodeTranslationCache, snapshot);
        for (final key in data.omitted) {
          if (_cache[key] == snapshot[key]) _cache.remove(key);
        }
        final store = await _file();
        await store.parent.create(recursive: true);
        final temporary = File('${store.path}.tmp');
        await temporary.writeAsString(data.json, flush: true);
        await temporary.rename(store.path);
      } catch (_) {
        /* The in-memory translation remains usable. */
      }
    });
    return _writes;
  }

  Future<void> flush() => _writes;
  Future<void> clear() async {
    await boot();
    _revision++;
    _cache.clear();
    _keys.clear();
    displayOriginal = false;
    notifyListeners();
    await _save();
  }
}

/// Preserve successful native translations; only unresolved entries go online.
Future<List<String>> translateWithPolicy(
  List<String> texts, {
  String target = 'zh-Hans',
  required TextTranslationMode mode,
  required TextTranslator native,
  required TextTranslator ai,
}) async {
  if (mode == TextTranslationMode.ai) return ai(texts);
  if (mode == TextTranslationMode.system) return native(texts);
  var values = List<String>.filled(texts.length, '');
  try {
    values = List<String>.of(await native(texts));
    if (values.length != texts.length) throw const FormatException('系统译文数量不一致');
  } catch (error) {
    if (error is StateError ||
        (error is PlatformException &&
            [
              'cancelled',
              'canceled',
              'translation_cancelled',
            ].contains(error.code))) {
      rethrow;
    }
    if (error is PlatformException &&
        error.code == 'translation_partial' &&
        error.details is List) {
      final details = error.details as List;
      if (details.length == texts.length && details.every((v) => v is String)) {
        values = details.cast<String>().toList();
      }
    }
  }
  if (values.length != texts.length) values = List.filled(texts.length, '');
  final missing = [
    for (var i = 0; i < values.length; i++)
      if (values[i].trim().isEmpty ||
          unresolvedTranslation(texts[i], values[i], target))
        i,
  ];
  for (final index in missing) {
    values[index] = '';
  }
  if (missing.isEmpty) return values;
  try {
    final translated = await ai([for (final index in missing) texts[index]]);
    if (translated.length != missing.length ||
        translated.any((v) => v.trim().isEmpty)) {
      throw const FormatException('AI 补译结果不完整');
    }
    for (var i = 0; i < missing.length; i++) {
      values[missing[i]] = translated[i];
    }
    return values;
  } catch (error) {
    if (error is PlatformException &&
        error.code == 'translation_partial' &&
        error.details is List &&
        (error.details as List).length == missing.length) {
      final recovered = error.details as List;
      for (var i = 0; i < missing.length; i++) {
        if (recovered[i] is String) values[missing[i]] = recovered[i] as String;
      }
    }
    if (values.any((v) => v.trim().isNotEmpty)) {
      throw PlatformException(
        code: 'translation_partial',
        message: 'AI 补译未完成，已保留系统成功译文，请检查全局 AI 配置和网络',
        details: values,
      );
    }
    rethrow;
  }
}
